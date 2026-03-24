"""
    COSMethod <: AbstractPricingMethod

Fourier-cosine series expansion pricing method for European options (Fang & Oosterlee, 2008).

Approximates the risk-neutral density via a cosine expansion on a truncated interval,
then computes option prices as weighted sums of analytically known payoff coefficients.
Often faster than Carr-Madan for single-strike pricing at comparable accuracy.

# Fields
- `N`: Number of cosine expansion terms (higher = more accurate, typical: 64–256).
- `L`: Truncation parameter for the density support in standard deviations (typical: 10–12).
- `dynamics`: The model dynamics providing the terminal characteristic function.

# References
- Fang, F. and Oosterlee, C.W. (2008). "A Novel Pricing Method for European Options Based
  on Fourier-Cosine Series Expansions." SIAM J. Sci. Comput., 31(2), 826–848.
"""
struct COSMethod{TN<:Integer, TL<:Real, TDynamics} <: AbstractPricingMethod
    N::TN
    L::TL
    dynamics::TDynamics
end

"""
    COSMethod(dynamics; N=128, L=10)

Constructs a `COSMethod` with `N` expansion terms, truncation width `L` standard deviations,
and the given price dynamics.

# Arguments
- `dynamics`: The price dynamics (must support `marginal_law`).
- `N`: Number of cosine terms (default: 128; use 256 for Heston).
- `L`: Truncation width in standard deviations (default: 10).
"""
COSMethod(dynamics; N=128, L=10) = COSMethod(N, L, dynamics)

function solve(
    prob::PricingProblem{VanillaOption{TS,TE,European,C,Spot},I},
    method::COSMethod,
) where {TS,TE,C,I<:AbstractMarketInputs}

    K = prob.payoff.strike
    r = prob.market_inputs.rate
    S = prob.market_inputs.spot

    terminal_law = marginal_law(prob, method.dynamics, prob.payoff.expiry)
    ϕ(u) = cf(terminal_law, u)

    # Determine truncation range [a, b] from cumulants
    a, b = _cos_truncation_range(ϕ, method.L)

    N = method.N
    logK = log(K)
    call_price = _cos_price_call(ϕ, a, b, N, logK, r, prob.payoff.expiry)
    price = parity_transform(call_price, prob.payoff, S, r)

    return COSSolution(prob, method, price)
end

"""
    _cos_truncation_range(ϕ, L)

Determines the truncation range [a, b] for the COS method using cumulants
estimated from the log-characteristic function via finite differences.

Cumulants are extracted from ln ϕ(u):
- κ₁ = -i · (d/du) ln ϕ(0)   (mean)
- κ₂ = -(d²/du²) ln ϕ(0)     (variance)
- κ₄ = (d⁴/du⁴) ln ϕ(0)      (excess kurtosis contribution)
"""
function _cos_truncation_range(ϕ, L)
    h = 1e-4

    # Evaluate CF at real points for finite differences of ln ϕ(u) w.r.t. u
    lnϕ0  = log(ϕ(0.0))
    lnϕp1 = log(ϕ(h))
    lnϕm1 = log(ϕ(-h))
    lnϕp2 = log(ϕ(2h))
    lnϕm2 = log(ϕ(-2h))

    # First cumulant (mean): κ₁ = -i · d/du ln ϕ(0)
    c1 = real(-im * (lnϕp1 - lnϕm1) / (2h))

    # Second cumulant (variance): κ₂ = -d²/du² ln ϕ(0)
    c2 = real(-(lnϕp1 - 2lnϕ0 + lnϕm1) / h^2)

    # Fourth cumulant: five-point stencil
    c4 = abs(real((lnϕp2 - 4lnϕp1 + 6lnϕ0 - 4lnϕm1 + lnϕm2) / h^4))

    # Truncation range (Fang & Oosterlee recommend L ≈ 10–12)
    width = L * sqrt(abs(c2) + sqrt(c4))
    a = c1 - width
    b = c1 + width

    return a, b
end

"""
    _cos_price_call(ϕ, a, b, N, logK, rate, expiry)

Computes the European call price using the COS expansion:

    C = e^{-rT} Σ'_{k=0}^{N-1} Re{ ϕ(kπ/(b-a)) · e^{-ikπa/(b-a)} } · V_k

where V_k are analytical payoff coefficients and the prime denotes halving the k=0 term.
"""
function _cos_price_call(ϕ, a, b, N, logK, rate, expiry)
    discount = df(rate, expiry)
    bma = b - a
    K = exp(logK)

    price = 0.0
    for k in 0:(N-1)
        # CF coefficient: Re{ ϕ(kπ/(b-a)) · exp(-ikπa/(b-a)) }
        ω = k * π / bma
        cf_coeff = real(ϕ(ω) * exp(-im * ω * a))

        # Payoff coefficient for call: V_k = (2/(b-a)) * [χ_k(logK, b) - K · ψ_k(logK, b)]
        Vk = (2.0 / bma) * (_cos_chi(k, logK, b, a, bma) - K * _cos_psi(k, logK, b, a, bma))

        # First term halved (Σ' convention)
        weight = k == 0 ? 0.5 : 1.0
        price += weight * cf_coeff * Vk
    end

    return discount * price
end

"""
    _cos_chi(k, c, d, a, bma)

Computes χ_k(c, d) = ∫_c^d e^y cos(kπ(y-a)/(b-a)) dy in closed form.
"""
function _cos_chi(k, c, d, a, bma)
    if k == 0
        return exp(d) - exp(c)
    end
    ω = k * π / bma
    denom = 1.0 + ω^2
    term_d = exp(d) * (cos(ω * (d - a)) + ω * sin(ω * (d - a)))
    term_c = exp(c) * (cos(ω * (c - a)) + ω * sin(ω * (c - a)))
    return (term_d - term_c) / denom
end

"""
    _cos_psi(k, c, d, a, bma)

Computes ψ_k(c, d) = ∫_c^d cos(kπ(y-a)/(b-a)) dy in closed form.
"""
function _cos_psi(k, c, d, a, bma)
    if k == 0
        return d - c
    end
    ω = k * π / bma
    return (sin(ω * (d - a)) - sin(ω * (c - a))) / ω
end
