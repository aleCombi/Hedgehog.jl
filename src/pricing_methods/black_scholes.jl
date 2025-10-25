"""
    BlackScholesAnalytic <: AbstractPricingMethod

Analytical Black-Scholes pricing method.

Represents the closed-form Black-Scholes model for pricing European-style vanilla options.
Assumes lognormal dynamics for the underlying asset with constant volatility and interest rate.
"""
struct BlackScholesAnalytic <: AbstractPricingMethod end

"""
    log_dynamics(::BlackScholesAnalytic) -> LognormalDynamics

Returns the assumed price dynamics under the Black-Scholes model.

This corresponds to lognormal dynamics with constant volatility and risk-free rate.
"""
function log_dynamics(::BlackScholesAnalytic)
    return LognormalDynamics()
end

"""
    solve(prob::PricingProblem{VanillaOption{European}}, ::BlackScholesAnalytic) -> AnalyticSolution

Computes the price of a European vanilla option under the Black-Scholes model.

# Arguments
- `prob::PricingProblem`: The pricing problem, including the payoff and market inputs.
- `BlackScholesAnalytic`: Marker for the analytic pricing method.

# Returns
- `AnalyticSolution`: The priced solution under Black-Scholes assumptions.

# Notes
- Uses the forward measure formulation.
- Falls back to intrinsic value if volatility is zero.
"""
function solve(
    prob::PricingProblem{VanillaOption{TS,TE,European,B,C}, I},
    method::BlackScholesAnalytic,
) where {TS,TE,B,C, I <: BlackScholesInputs}

    payoff = prob.payoff
    market = prob.market_inputs

    K = payoff.strike
    σ = get_vol(market.sigma, payoff.expiry, K)
    cp = payoff.call_put()
    T = yearfrac(market.referenceDate, payoff.expiry)
    D = df(market.rate, payoff.expiry)
    F = market.spot / D

    price = if σ == 0
        D * payoff(F)
    else
        sqrtT = sqrt(T)
        d1 = (log(F / K) + 0.5 * σ^2 * T) / (σ * sqrtT)
        d2 = d1 - σ * sqrtT
        N = Normal()
        D * cp * (F * cdf(N, cp * d1) - K * cdf(N, cp * d2))
    end
    
    return AnalyticSolution(prob, method, price)
end