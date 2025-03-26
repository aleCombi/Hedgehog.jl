using Polynomials
export LSM

"""
    LSM <: AbstractPricingMethod

Least Squares Monte Carlo (LSM) pricing method for American options.

Uses regression to estimate continuation values and determine optimal stopping times.

# Fields
- `mc_method`: A `MonteCarlo` method specifying dynamics and simulation strategy.
- `degree`: Degree of the polynomial basis for regression.
"""
struct LSM <: AbstractPricingMethod
    mc_method::MonteCarlo
    degree::Int  # degree of polynomial basis
end

"""
    LSM(dynamics::PriceDynamics, strategy::SimulationStrategy, degree::Int; kwargs...)

Constructs an `LSM` pricing method with a given degree polynomial regression and Monte Carlo simulation backend.

# Arguments
- `dynamics`: The price dynamics.
- `strategy`: The simulation strategy.
- `degree`: Degree of polynomial basis.
- `kwargs...`: Additional arguments passed to the `MonteCarlo` constructor.
"""
function LSM(dynamics::PriceDynamics, strategy::SimulationStrategy, degree::Int; kwargs...)
    mc = MonteCarlo(dynamics, strategy; kwargs...)
    return LSM(mc, degree)
end

"""
    extract_spot_grid(sol)

Extracts the simulated spot paths from a `Vector` of state vectors. Returns a matrix of size (nsteps, npaths).
Each column corresponds to a single simulation path.
"""
function extract_spot_grid(sol)
    # Each path is a Vector of state vectors; we extract first component at each time step
    return hcat([getindex.(s.u, 1) for s in sol.u]...)  # size: (nsteps, npaths)
end

"""
    compute_price(payoff::VanillaOption{American, C, Spot}, market_inputs::I, method::LSM) -> Float64

Computes the price of an American-style vanilla option using the Longstaff-Schwartz (LSM) algorithm.

# Arguments
- `payoff`: American-style vanilla option.
- `market_inputs`: Market data (spot, rate, reference date).
- `method`: An `LSM` method instance.

# Returns
- Estimated price of the American option based on backward induction.

# Notes
- Simulates paths using the underlying Monte Carlo method.
- Uses polynomial regression at each timestep to estimate the continuation value.
- Determines early exercise opportunities and computes expected discounted payoff.
"""
function compute_price(
    payoff::VanillaOption{American, C, Spot},
    market_inputs::I,
    method::LSM
) where {I <: AbstractMarketInputs, C}

    T = Dates.value(payoff.expiry - market_inputs.referenceDate) / 365
    sol = simulate_paths(method.mc_method, market_inputs, T)
    spot_grid = extract_spot_grid(sol) ./ market_inputs.spot

    ntimes, npaths = size(spot_grid)
    nsteps = ntimes - 1
    discount = exp(-market_inputs.rate * T / nsteps)

    # (time_index, payoff_value) per path
    stopping_info = [(nsteps, payoff(spot_grid[nsteps + 1, p])) for p in 1:npaths]

    for i in (ntimes - 1):-1:2
        t = i - 1 #the matrix indices are 1-based, but times are 0-based

        continuation = [
            discount^(stopping_info[p][1] - t) * stopping_info[p][2]
            for p in 1:npaths
        ]

        payoff_t = payoff.(spot_grid[i, :])

        in_the_money = findall(payoff_t .> 0)
        isempty(in_the_money) && continue

        x = spot_grid[i, in_the_money]
        y = continuation[in_the_money]
        poly = Polynomials.fit(x, y, method.degree)
        cont_value = poly.(x)

        update_stopping_info!(stopping_info, in_the_money, cont_value, payoff_t, t)
    end

    discounted_values = [discount^t * val for (t, val) in stopping_info]
    return market_inputs.spot * mean(discounted_values)
end

"""
    update_stopping_info!(
        stopping_info::Vector{Tuple{Int, Float64}},
        paths::Vector{Int},
        cont_value::Vector{Float64},
        payoff_t::Vector{Float64},
        t::Int
    )

Updates the stopping times and payoffs based on exercise decision.
Replaces values in `stopping_info` if immediate exercise is better than continuation.
"""
function update_stopping_info!(
    stopping_info::Vector{Tuple{Int, Float64}},
    paths::Vector{Int},
    cont_value::Vector{Float64},
    payoff_t::Vector{Float64},
    t::Int
)
    exercise = payoff_t[paths] .> cont_value
    stopping_info[paths[exercise]] .= [(t, payoff_t[p]) for p in paths[exercise]]
end
