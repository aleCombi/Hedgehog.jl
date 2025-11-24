using Dates
using Hedgehog
using Accessors
using Optimization
using OptimizationOptimJL
using Integrals # Essential for QuadGKJL

# ==========================================
# 1. SETUP
# ==========================================

reference_date = Date(2020, 1, 1)
S0 = 100.0
true_params = (v0 = 0.010201, κ = 6.21, θ = 0.019, σ = 0.61, ρ = -0.7)
r = 0.0319

market_inputs = HestonInputs(
    reference_date, r, S0,
    true_params.v0, true_params.κ, true_params.θ, true_params.σ, true_params.ρ,
)

strikes = collect(60.0:5.0:140.0)
expiries = [
    reference_date + Day(90),
    reference_date + Day(180),
    reference_date + Day(365),
]

payoffs = [
    VanillaOption(K, expiry, European(), Call(), Spot()) 
    for K in strikes, expiry in expiries
] |> vec

# ==========================================
# 2. CRITICAL FIX: INTEGRATOR SETTINGS
# ==========================================

# 1. Use QuadGKJL() -> Much faster/stable for 1D integrals than default
# 2. Set abstol/reltol -> Prevent infinite refinement on numerical noise
α, boundary = 1.0, 40.0
method_heston = CarrMadan(
    α, 
    boundary, 
    HestonDynamics(), 
    Integrals.QuadGKJL(); 
    abstol=1e-5, 
    reltol=1e-5
)

# Generate Target Quotes
println("Generating target quotes...")
quotes = [Hedgehog.solve(PricingProblem(p, market_inputs), method_heston).price for p in payoffs]

# ==========================================
# 3. CALIBRATION SETUP
# ==========================================

# Initial Guess [V0, κ, θ, σ, ρ]
initial_guess = [0.02, 3.0, 0.03, 0.4, -0.3]

accessors = [
    @optic(_.market_inputs.V0),
    @optic(_.market_inputs.κ),
    @optic(_.market_inputs.θ),
    @optic(_.market_inputs.σ),
    @optic(_.market_inputs.ρ),
]

basket_problem = BasketPricingProblem(payoffs, market_inputs)

# Define Objective Function
function calibration_objective(x, p)
    # Update problem with current parameters
    updated_problem = foldl(
        (prob, (lens, val)) -> Accessors.set(prob, lens, val),
        zip(accessors, x),
        init = basket_problem
    )

    # Solve
    # Note: Because we use QuadGK + Bounds, this is now safe.
    basket_solution = Hedgehog.solve(updated_problem, method_heston)
    
    model_prices = [sol.price for sol in basket_solution.solutions]
    
    # Sum of Squared Errors
    loss = sum(abs2, model_prices .- quotes)
    return loss
end

# ==========================================
# 4. SOLVE WITH LBFGS + BOUNDS
# ==========================================

# Bounds are MANDATORY for Heston to prevent math explosions
# [V0, κ, θ, σ, ρ]
lower_bounds = [1e-5, 1e-3, 1e-5, 1e-3, -0.99]
upper_bounds = [1.0,  20.0, 1.0,  5.0,   0.99]

# Use AutoFiniteDiff (Faster than ForwardDiff for integrals)
opt_func = OptimizationFunction(calibration_objective, Optimization.AutoForwardDiff())

opt_prob = OptimizationProblem(
    opt_func, 
    initial_guess, 
    nothing,
    lb = lower_bounds,
    ub = upper_bounds
)

println("Starting Calibration (LBFGS)...")
result = Optimization.solve(opt_prob, OptimizationOptimJL.LBFGS(), maxiters = 100)

println("\n=== Calibration Results ===")
println("True Params: [$(true_params.v0), $(true_params.κ), $(true_params.θ), $(true_params.σ), $(true_params.ρ)]")
println("Calibrated:  $(result.u)")
println("Final Loss:  $(result.objective)")