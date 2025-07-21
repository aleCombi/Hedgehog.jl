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
        SimulationConfig(num_paths; steps=200, seeds=seeds, variance_reduction=Hedgehog.Antithetic())
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