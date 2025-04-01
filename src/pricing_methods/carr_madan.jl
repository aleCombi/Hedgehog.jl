using Dates, Distributions
import Integrals
export CarrMadan 

"""
    CarrMadan <: AbstractPricingMethod

Fourier transform-based pricing method for European options.

Implements the Carr-Madan method, which prices European options using the inverse Fourier transform
of the characteristic function of the log-price under the risk-neutral measure.

# Fields
- `α`: Damping factor to ensure integrability of the Fourier transform.
- `bound`: Integration bound for numerical quadrature.
- `dynamics`: The model dynamics providing the terminal characteristic function.
- `kwargs`: Additional keyword arguments passed to the integral solver.
"""
struct CarrMadan <: AbstractPricingMethod
    α 
    bound
    dynamics
    kwargs # integral keyword arguments
end

"""
    log_dynamics(m::CarrMadan)

Returns the log-price dynamics (distribution) used in the Carr-Madan method.
"""
function log_dynamics(m::CarrMadan) 
    return m.distribution
end

"""
    CarrMadan(α, bound, dynamics; kwargs...)

Constructs a `CarrMadan` method with optional integration settings for `quadgk`.

# Arguments
- `α`: Damping factor.
- `bound`: Integration bound (positive real number).
- `dynamics`: The price dynamics (must support `marginal_law`).
- `kwargs...`: Additional keyword arguments for `quadgk`.
"""
function CarrMadan(α, bound, dynamics; kwargs...) 
    return CarrMadan(α, bound, dynamics, Dict(kwargs...))
end

function solve(
    prob::PricingProblem{VanillaOption{European, C, Spot}, I},
    method::CarrMadan
) where {C, I <: AbstractMarketInputs}

    println("started carr madan")
    if !is_flat(prob.market.rate)
        throw(ArgumentError("Carr–Madan pricing only supports flat rate curves."))
    end
        
    K = prob.payoff.strike
    r = prob.market.rate
    S = prob.market.spot

    terminal_law = marginal_law(method.dynamics, prob.market, prob.payoff.expiry)
    ϕ(u) = cf(terminal_law, u)

    logK = log(K)
    damp = exp(-method.α * logK) / (2π)
    integrand(v, p) = damp * call_transform(r, prob.payoff.expiry, ϕ, v, method) * exp(-im * v * logK)

    iprob = IntegralProblem(integrand, -method.bound, method.bound, nothing)
    integral_result = Integrals.solve(iprob, Integrals.HCubatureJL(); method.kwargs...)

    call_price = real(integral_result.u)
    price = parity_transform(call_price, prob.payoff, S)

    return CarrMadanSolution(price, integral_result)
end

"""
    call_transform(rate, time, ϕ, v, method::CarrMadan)

Returns the Fourier-space representation of the damped call payoff.

# Arguments
- `rate`: Risk-free rate.
- `time`: Time to maturity.
- `ϕ`: Characteristic function of the log-price.
- `v`: Fourier variable.
- `method`: The `CarrMadan` pricing method instance.

# Returns
- The value of the integrand for the Carr-Madan integral.
"""
function call_transform(rate, time, ϕ, v, method::CarrMadan)
    numerator = df(rate, time) * ϕ(v - (method.α + 1)im)
    denominator = method.α^2 + method.α - v^2 + v * (2 * method.α + 1)im
    return numerator / denominator
end