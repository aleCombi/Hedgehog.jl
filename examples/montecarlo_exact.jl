using Revise, Hedgehog, BenchmarkTools, Dates
using Accessors
import Accessors: @optic
using StochasticDiffEq

# ------------------------------
# Define payoff and pricing problem
# ------------------------------
strike = 1.0
expiry = Date(2021, 1, 1)

euro_payoff = VanillaOption(strike, expiry, European(), Put(), Spot())

reference_date = Date(2020, 1, 1)
rate = 0.03
spot = 1.0
sigma = 0.04

market_inputs = BlackScholesInputs(reference_date, rate, spot, sigma)
euro_pricing_prob = PricingProblem(euro_payoff, market_inputs)

dynamics = LognormalDynamics()
trajectories = 10000
config = Hedgehog.SimulationConfig(trajectories; steps=100, variance_reduction=Hedgehog.Antithetic())
strategy = EulerMaruyama()
montecarlo_method = MonteCarlo(dynamics, strategy, config)

solution_analytic = Hedgehog.solve(euro_pricing_prob, BlackScholesAnalytic()).price
solution = Hedgehog.solve(euro_pricing_prob, montecarlo_method).price

@show Hedgehog.solve(euro_pricing_prob, montecarlo_method).price
@show Hedgehog.solve(euro_pricing_prob, BlackScholesAnalytic()).price

law = Hedgehog.marginal_law(euro_pricing_prob, LognormalDynamics(), expiry) #log-marginal law
log_sample = rand(law, trajectories)
final_sample = exp.(log_sample) 
payoff_sample = euro_payoff.(final_sample)
discount = df(euro_pricing_prob.market_inputs.rate, euro_pricing_prob.payoff.expiry)
price = discount * mean(payoff_sample)

antithetic_sample = exp.(2 * mean(law) .- log_sample)
payoff_anti_sample = (euro_payoff.(final_sample) + euro_payoff.(antithetic_sample)) / 2
price_anti = discount * mean(payoff_anti_sample)

montecarlo_method_exact = MonteCarlo(dynamics, BlackScholesExact(), config)
solution_exact = Hedgehog.solve(euro_pricing_prob, montecarlo_method_exact).price
@btime Hedgehog.solve($euro_pricing_prob, $montecarlo_method_exact).price
@show solution_exact