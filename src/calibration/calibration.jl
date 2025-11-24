using OptimizationOptimJL

"""
    CalibrationProblem{P, M, A, Accessor, I, Q}

Wraps a `BasketPricingProblem` and defines which market parameters
should be calibrated using Accessors.jl access paths.

# Fields
- `pricing_problem::BasketPricingProblem{P, M}`: The basket of payoffs and shared market input.
- `pricing_method::A`: The pricing method used (e.g., Black-Scholes).
- `accessors::Vector{Accessor}`: List of `Accessors.jl` lenses specifying which parameters to calibrate.
- `quotes::Vector{Q}`: Observed market prices to match.
- `initial_guess::Vector{I}`: Initial guesses for each calibrated parameter.
"""
struct CalibrationProblem{
    P<:AbstractPayoff,
    M<:AbstractMarketInputs,
    A<:AbstractPricingMethod,
    Accessor,
    I<:Real,
    Q<:Real
}
    pricing_problem::BasketPricingProblem{P, M}
    pricing_method::A
    accessors::Vector{Accessor}
    quotes::Vector{Q}
    initial_guess::Vector{I}
end

"""
    abstract type CalibrationAlgo

Marker type for calibration algorithms.
Subtypes include `OptimizerAlgo` for optimization-based calibration
and `RootFinderAlgo` for root-finding-based single-point calibration.
"""
abstract type CalibrationAlgo end

"""
    OptimizerAlgo{D, O}

A calibration algorithm using optimization. `D` is the differentiation backend
(e.g., `AutoForwardDiff()`), and `O` is the optimization algorithm (e.g., `LBFGS()`).
"""
struct OptimizerAlgo{D, O} <: CalibrationAlgo
    diff::D
    optim_algo::O
end

"""
    OptimizerAlgo()

Constructs an `OptimizerAlgo` with `AutoForwardDiff()` and `LBFGS()` as defaults.
"""
function OptimizerAlgo()
    return OptimizerAlgo(Optimization.AutoForwardDiff(), OptimizationOptimJL.LBFGS())
end

"""
    solve(calib::CalibrationProblem, calib_algo::OptimizerAlgo; lb=nothing, ub=nothing, kwargs...)

Calibrates a basket of pricing problems using an optimization algorithm.

# Arguments
- `calib`: The calibration problem definition.
- `calib_algo`: The optimization algorithm configuration.
- `lb`: Lower bounds for the parameters (optional, but highly recommended for models like Heston).
- `ub`: Upper bounds for the parameters (optional).
- `kwargs...`: Additional arguments passed to the solver (e.g., `maxiters`, `abstol`).

Returns the optimization result, which contains the fitted parameters.
"""
function solve(calib::CalibrationProblem, calib_algo::OptimizerAlgo; lb=nothing, ub=nothing, kwargs...)
    function objective(x, p)
        basket_prob = calib.pricing_problem

        updated_problem = foldl(
            (prob, (lens, val)) -> set(prob, lens, val),
            zip(calib.accessors, x),
            init = basket_prob,
        )

        basket_solution = solve(updated_problem, calib.pricing_method)
        sol_prices = map(sol -> sol.price, basket_solution.solutions)
        errors = sol_prices .- calib.quotes
        return sum(abs2, errors)
    end

    optf = OptimizationFunction(objective, calib_algo.diff)
    
    # Explicitly pass bounds to the problem definition
    opt_prob = OptimizationProblem(optf, calib.initial_guess, nothing; lb=lb, ub=ub)
    
    # Pass remaining kwargs (like maxiters) to the solver
    result = Optimization.solve(opt_prob, calib_algo.optim_algo; kwargs...)
    return result
end

"""
    RootFinderAlgo{R}

Calibration algorithm using scalar root finding.
Only supports single-instrument calibration.
"""
struct RootFinderAlgo{R} <: CalibrationAlgo
    root_method::R
end

"""
    RootFinderAlgo()

Constructs a `RootFinderAlgo` using the default method (Brent’s method inside `NonlinearSolve`).
"""
function RootFinderAlgo()
    return RootFinderAlgo(OptimizationOptimJL.Brent())
end

"""
    solve(calib::CalibrationProblem, calib_algo::RootFinderAlgo; kwargs...)

Solves for a single implied parameter (e.g., implied volatility) using root-finding.

Returns the solution object with `.u` as the calibrated value.
"""
function solve(calib::CalibrationProblem, calib_algo::RootFinderAlgo; kwargs...)
    @assert length(calib.accessors) == 1 "Root-finding only supports calibration of a single parameter"
    @assert length(calib.quotes) == 1 "Root-finding expects a single target quote"

    lens = calib.accessors[1]
    quote_val = calib.quotes[1]
    pricing_problem = PricingProblem(
        calib.pricing_problem.payoffs[1],
        calib.pricing_problem.market_inputs
    )

    function f(x, _)
        updated_prob = set(pricing_problem, lens, x)
        sol = solve(updated_prob, calib.pricing_method)
        return sol.price - quote_val
    end

    problem = IntervalNonlinearProblem(f, (1e-6, 5.0))
    return NonlinearSolve.solve(problem, calib_algo.root_method; kwargs...)
end