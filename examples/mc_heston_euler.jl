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

# Pricing with Euler-Maruyama using Antithetic variance reduction
mc_euler_method = MonteCarlo(
    HestonDynamics(),
    EulerMaruyama(),
    SimulationConfig(10*num_paths; steps=200, seeds=seeds, variance_reduction=Hedgehog.Antithetic())
)
solution_euler = solve(problem, mc_euler_method)
sample_at_expiry = Hedgehog.get_final_samples(problem, mc_euler_method)
sde_prob = Hedgehog.sde_problem(problem, mc_euler_method)
ens = Hedgehog.simulate_paths(sde_prob, mc_euler_method, mc_euler_method.config.variance_reduction)

config = mc_euler_method.config
dt = sde_prob.tspan[2] / config.steps
ensemble_prob = Hedgehog.get_ensemble_problem(sde_prob, config)
normal_sol = StochasticDiffEq.solve(ensemble_prob, EM(); dt = dt, trajectories=config.trajectories)

price_euler = solution_euler.price