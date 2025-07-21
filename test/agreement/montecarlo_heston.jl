using Test
using Hedgehog
using Dates
using Random
using Statistics
using Printf

@testset "Heston Model Monte Carlo Test / Variance reduction test" begin
    # --------------------------
    # Setup common test parameters
    # --------------------------
    # Heston model parameters
    spot = 100.0
    strike = 100.0
    reference_date = Date(2020, 1, 1)
    expiry = reference_date + Year(1)
    r = 0.03             # Risk-free rate
    V0 = 0.04            # Initial variance
    κ = 2.0              # Mean reversion speed
    θ = 0.04             # Long-term variance
    σ = 0.3              # Vol-of-vol
    ρ = -0.7             # Correlation

    # Print parameter configuration for debugging
    println("Test Parameters:")
    println("  Spot: $spot")
    println("  Strike: $strike")
    println("  Rate: $r")
    println("  Initial variance (V0): $V0")
    println("  Mean reversion (κ): $κ")
    println("  Long-term variance (θ): $θ")
    println("  Vol-of-vol (σ): $σ")
    println("  Correlation (ρ): $ρ")
    println("  Time to maturity: 1 year")
    println("  Option type: European Call")

    # Define payoff and market inputs
    payoff = VanillaOption(strike, expiry, European(), Call(), Spot())
    market_inputs = HestonInputs(reference_date, r, spot, V0, κ, θ, σ, ρ)
    prob = PricingProblem(payoff, market_inputs)

    # Define test parameters - increase trajectories for more reliable results
    trajectories = 5000
    steps = 100

    # Reference price using Carr-Madan (Fourier) method
    carr_madan_method = CarrMadan(1.0, 32.0, HestonDynamics())
    carr_madan_sol = Hedgehog.solve(prob, carr_madan_method)
    reference_price = carr_madan_sol.price

    # Print reference price
    println("Reference price (Carr-Madan): $reference_price")

    # Test scenarios for Euler-Maruyama
    scenarios = [
        (
            "Euler-Maruyama without antithetic",
            EulerMaruyama(),
            HestonDynamics(),
            SimulationConfig(trajectories, seeds = nothing, variance_reduction=Hedgehog.NoVarianceReduction())
        ),
        (
            "Euler-Maruyama with antithetic",
            EulerMaruyama(),
            HestonDynamics(),
            SimulationConfig(trajectories ÷ 2, seeds = nothing, variance_reduction=Hedgehog.Antithetic())
        ),
    ]

    results = Dict()

    # Run all scenarios
    for (scenario_name, strategy, dynamics, config) in scenarios
        # Print current scenario
        println("Running scenario: ", scenario_name)

        # Execute multiple trials to measure variance
        prices = Float64[]
        for trial = 1:5
            # Create a new RNG with a trial-specific seed
            trial_rng = MersenneTwister(42 + trial)

            # Generate random seeds for each path
            trial_seeds = rand(trial_rng, 1:10^9, trajectories)

            # Create modified strategy with trial seeds
            modified_config = @set config.seeds = trial_seeds

            # Create Monte Carlo method
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

        # Test the result with a generous tolerance (Heston MC typically needs more paths)
        @test isapprox(mean_price, reference_price, rtol = 0.05)
    end

    # Compare variance reduction
    if length(scenarios) >= 2
        std_var = results["Euler-Maruyama without antithetic"].variance
        anti_var = results["Euler-Maruyama with antithetic"].variance
        var_reduction = std_var / anti_var

        @info "Variance reduction (Euler-Maruyama): $(var_reduction)×"
        @test var_reduction > 1.0  # Antithetic should reduce variance
    end

    # Print summary
    println("\n=== Heston Model Monte Carlo Test Results ===")
    println("Reference price (Carr-Madan): $reference_price")
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

using Test
using Hedgehog
using Dates
using Random

@testset "Heston Exact Simulation vs Euler Maruyama" begin
    # Define the vanilla option payoff
    strike = 100.0
    expiry_date = Date(2025, 12, 31)
    payoff = VanillaOption(strike, expiry_date, European(), Call(), Spot())

    # Define the Heston model market inputs using positional arguments
    reference_date = Date(2025, 1, 1)
    spot = 100.0
    rate = 0.05
    heston_inputs = HestonInputs(
        reference_date,
        rate,
        spot,
        1.5,    # kappa
        0.04,   # theta
        0.3,    # sigma
        -0.6,   # rho
        0.04    # v0
    )

    # Create the pricing problem
    problem = PricingProblem(payoff, heston_inputs)

    # Generate a vector of seeds for reproducibility
    num_paths = 10_000
    rng = MersenneTwister(42)
    seeds = rand(rng, UInt, 10*num_paths)

    # Pricing with Broadie-Kaya (Heston Exact) using Antithetic variance reduction
    mc_exact_method = MonteCarlo(
        HestonDynamics(),
        HestonBroadieKaya(),
        SimulationConfig(num_paths; seeds=seeds)
    )
    solution_exact = solve(problem, mc_exact_method)
    price_exact = solution_exact.price

    # Pricing with Euler-Maruyama using Antithetic variance reduction
    mc_euler_method = MonteCarlo(
        HestonDynamics(),
        EulerMaruyama(),
        SimulationConfig(5*num_paths; steps=200, seeds=seeds, variance_reduction=Hedgehog.Antithetic())
    )
    solution_euler = solve(problem, mc_euler_method)
    price_euler = solution_euler.price

        # Pricing with Carr-Madan
    carr_madan_method = CarrMadan(1.0, 32.0, HestonDynamics())
    solution_carr_madan = solve(problem, carr_madan_method)
    price_carr_madan = solution_carr_madan.price

    # Compare the prices with a lower tolerance
    @test isapprox(price_exact, price_euler, rtol=5e-2)
    @test isapprox(price_exact, price_carr_madan, rtol=2e-2)
end

@testset "Heston Exact Simulation vs Carr-Madan" begin
    # Define the vanilla option payoff
    strike = 100.0
    expiry_date = Date(2025, 12, 31)
    payoff = VanillaOption(strike, expiry_date, European(), Call(), Spot())

    # Define the Heston model market inputs using positional arguments
    reference_date = Date(2025, 1, 1)
    spot = 100.0
    rate = 0.05
    heston_inputs = HestonInputs(
        reference_date,
        rate,
        spot,
        1.5,    # kappa
        0.04,   # theta
        0.3,    # sigma
        -0.6,   # rho
        0.04    # v0
    )

    # Create the pricing problem
    problem = PricingProblem(payoff, heston_inputs)

    # Generate a vector of seeds for reproducibility
    num_paths = 10_000
    rng = MersenneTwister(42)
    seeds = rand(rng, UInt, num_paths)

    # Pricing with Broadie-Kaya (Heston Exact) using Antithetic variance reduction
    mc_exact_method = MonteCarlo(
        HestonDynamics(),
        HestonBroadieKaya(),
        SimulationConfig(num_paths; seeds=seeds)
    )
    solution_exact = solve(problem, mc_exact_method)
    price_exact = solution_exact.price

    # Pricing with Carr-Madan
    carr_madan_method = CarrMadan(1.0, 32.0, HestonDynamics())
    solution_carr_madan = solve(problem, carr_madan_method)
    price_carr_madan = solution_carr_madan.price

    # Compare the prices with a lower tolerance
    @test isapprox(price_exact, price_carr_madan, rtol=2e-2)
end