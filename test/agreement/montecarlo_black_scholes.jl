using Test
using Hedgehog
using Dates
using Random
using Statistics
using Printf

@testset "Black-Scholes Monte Carlo vs Analytic - Antithetic effectiveness" begin
    # --------------------------
    # Setup common test parameters
    # --------------------------
    # Using a standard example from financial literature
    strike = 100.0
    reference_date = Date(2020, 1, 1)
    expiry = reference_date + Year(1)
    rate = 0.05
    spot = 100.0
    sigma = 0.20

    # Print parameter configuration for debugging
    println("Test Parameters:")
    println("  Spot: $spot")
    println("  Strike: $strike")
    println("  Rate: $rate")
    println("  Volatility: $sigma")
    println("  Time to maturity: 1 year")
    println("  Option type: European Call")

    # Define payoff and market inputs
    payoff = VanillaOption(strike, expiry, European(), Call(), Spot())
    market_inputs = BlackScholesInputs(reference_date, rate, spot, sigma)
    prob = PricingProblem(payoff, market_inputs)

    # Define test parameters - increase trajectories for more reliable results
    trajectories = 10_000
    steps = 1

    # Analytic reference solution
    analytic_method = BlackScholesAnalytic()
    analytic_sol = Hedgehog.solve(prob, analytic_method)
    reference_price = analytic_sol.price

    # Print reference price for debugging
    println("Reference price (BlackScholesAnalytic): $reference_price")

    # Double-check with manual Black-Scholes formula calculation
    d1 = (log(spot / strike) + (rate + 0.5 * sigma^2)) / (sigma)
    d2 = d1 - sigma
    manual_bs_price = spot * cdf(Normal(), d1) - strike * exp(-rate) * cdf(Normal(), d2)
    println("Manual Black-Scholes calculation: $manual_bs_price")

    simulation_config = SimulationConfig(trajectories, seeds = nothing)
    # Test scenarios - we'll use Accessors to set seeds in the trial loop
    scenarios = [
        (
            "BlackScholesExact without antithetic",
            BlackScholesExact(),
            LognormalDynamics(),
            SimulationConfig(trajectories, seeds = nothing)
        ),
        (
            "BlackScholesExact with antithetic",
            BlackScholesExact(),
            LognormalDynamics(),
            SimulationConfig(trajectories, seeds = nothing; variance_reduction=Hedgehog.Antithetic())
        ),
        (
            "EulerMaruyama without antithetic",
            EulerMaruyama(),
            LognormalDynamics(),
            SimulationConfig(trajectories, seeds = nothing)
        ),
        (
            "EulerMaruyama with antithetic",
            EulerMaruyama(),
            LognormalDynamics(),
            SimulationConfig(trajectories, seeds = nothing; variance_reduction=Hedgehog.Antithetic())
        ),
    ]

    results = Dict()

    # Run all scenarios
    for (scenario_name, strategy, dynamics, config) in scenarios
        # Print current scenario for debugging
        println("Running scenario: ", scenario_name)

        # Execute multiple trials to measure variance, with DIFFERENT seeds per trial
        prices = Float64[]
        for trial = 1:5  # Reduced to 5 trials to focus on seed control
            # Create a new RNG with a trial-specific seed
            trial_rng = MersenneTwister(42 + trial)

            # Generate random seeds for each path
            # The key is that each trial gets a completely different set of seeds
            # But the seeds are still deterministic based on the trial number
            trial_seeds = rand(trial_rng, 1:10^9, trajectories)

            # Create modified strategy with updated kwargs
            modified_config = @set config.seeds = trial_seeds

            # Create Monte Carlo method with modified strategy
            mc_method = MonteCarlo(dynamics, strategy, modified_config)

            # Solve with current seed
            sol = Hedgehog.solve(prob, mc_method)
            push!(prices, sol.price)

            # Print diagnostic info
            println("  Trial $trial: Price = $(sol.price)")
        end

        # Calculate statistics
        mean_price = mean(prices)
        price_variance = var(prices)
        error = abs(mean_price - reference_price)
        rel_error = error / reference_price

        # Store results
        results[scenario_name] = (
            mean_price = mean_price,
            reference_price = reference_price,
            error = error,
            rel_error = rel_error,
            variance = price_variance,
        )

        # Test the result with a more generous tolerance 
        # (Monte Carlo will have some error, especially with fewer trials)
        @test isapprox(mean_price, reference_price, rtol = 0.02)
    end

    # Compare variance reduction for antithetic variants
    if haskey(results, "BlackScholesExact without antithetic") &&
       haskey(results, "BlackScholesExact with antithetic")
        std_var = results["BlackScholesExact without antithetic"].variance
        anti_var = results["BlackScholesExact with antithetic"].variance
        var_reduction = std_var / anti_var

        @info "Variance reduction (BlackScholesExact): $(var_reduction)×"
        @test var_reduction > 1.0  # Antithetic should reduce variance
    end

    if haskey(results, "EulerMaruyama without antithetic") &&
       haskey(results, "EulerMaruyama with antithetic")
        std_var = results["EulerMaruyama without antithetic"].variance
        anti_var = results["EulerMaruyama with antithetic"].variance
        var_reduction = std_var / anti_var

        @info "Variance reduction (EulerMaruyama): $(var_reduction)×"
        @test var_reduction > 1.0  # Antithetic should reduce variance
    end

    # Print summary
    println("\n=== Black-Scholes Monte Carlo Test Results ===")
    println("Reference price (Analytic): $reference_price")
    println("Scenario                    | Price      | Rel Error | Variance")
    println("----------------------------|------------|-----------|----------")

    for (name, res) in results
        @printf(
            "%-28s | %.6f | %.6f | %.2e\n",
            name,
            res.mean_price,
            res.rel_error,
            res.variance
        )
    end
end
