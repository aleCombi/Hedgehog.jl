using Revise
using Hedgehog
using Dates
using Printf
using BenchmarkTools
using Random 

function test_eur()
    spot = 100.0
    strike = 100.0
    rate = 0.05
    sigma = 0.20
    reference_date = Date(2023, 1, 1)
    expiry = reference_date + Year(1)

    # Create the payoff (European call option)
    payoff = VanillaOption(strike, expiry, European(), Call(), Spot())

    # Create market inputs
    market_inputs = BlackScholesInputs(reference_date, rate, spot, sigma)

    # Create pricing problem
    prob = PricingProblem(payoff, market_inputs)

    trajectories = 5_000
    mc_exact_method =
        MonteCarlo(LognormalDynamics(), BlackScholesExact(), SimulationConfig(trajectories))
    mc_exact_solution = solve(prob, mc_exact_method)
    @show mc_exact_solution.price

    display(@benchmark solve($prob, $mc_exact_method))
end

function test_am()
    @show "american"
    # Define market inputs
    strike = 10.0
    reference_date = Date(2020, 1, 1)
    expiry = reference_date + Year(1)
    rate = 0.05
    spot = 10.0
    sigma = 0.2
    market_inputs = BlackScholesInputs(reference_date, rate, spot, sigma)

    # Define payoff
    american_payoff = VanillaOption(strike, expiry, American(), Put(), Spot())

    # -- Wrap everything into a pricing problem
    prob = PricingProblem(american_payoff, market_inputs)

    # --- LSM using `solve(...)` style
    dynamics = LognormalDynamics()
    trajectories = 10_000
    steps_lsm = 100

    strategy = BlackScholesExact()
    config = Hedgehog.SimulationConfig(trajectories; steps=steps_lsm, variance_reduction=Hedgehog.Antithetic()
    #variance_reduction=Hedgehog.NoVarianceReduction()
    )
    degree = 5
    lsm_method = LSM(dynamics, strategy, config, degree)

    lsm_solution = Hedgehog.solve(prob, lsm_method)

    @show lsm_solution.price

    display(@benchmark Hedgehog.solve($prob, $lsm_method))
end

test_eur()
test_am()
