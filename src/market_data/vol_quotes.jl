# ----------------------------------------
# Underlying observation (what we know)
# ----------------------------------------

abstract type UnderlyingObs{T<:Real} end
struct SpotObs{T<:Real}    <: UnderlyingObs{T}; S::T; end
struct ForwardObs{T<:Real} <: UnderlyingObs{T}; F::T; end
struct FuturesObs{T<:Real} <: UnderlyingObs{T}; G::T; end

function underlying_spot(
    und::UnderlyingObs{T},
    r::T,
    ref_ms::Int64,
    expiry::Union{Int64,TimeType},
) where {T<:Real}
    D = df(FlatRateCurve(ref_ms, r), expiry)  # DF = e^{-r τ}
    return _spot_from_obs(und, D)
end

# tiny, inlinable methods (no curve creation here)
@inline _spot_from_obs(und::SpotObs{T},    D::T) where {T} = und.S
@inline _spot_from_obs(und::ForwardObs{T}, D::T) where {T} = und.F * D

# We treat futures as forwards; convexity adjustment not applied.
@inline _spot_from_obs(und::FuturesObs{T}, D::T) where {T} = und.G * D 

function underlying_forward(
    und::UnderlyingObs{T},
    r::T,
    ref_ms::Union{TimeType,Int64},
    expiry::Union{Int64,TimeType},
) where {T<:Real}
    D = df(FlatRateCurve(to_ticks(ref_ms), r), expiry)  # DF = e^{-rτ}
    return _forward_from_obs(und, D)
end

@inline _forward_from_obs(und::SpotObs{T},    D::T) where {T} = und.S / D   # F = S / DF
@inline _forward_from_obs(und::ForwardObs{T}, D::T) where {T} = und.F
@inline _forward_from_obs(und::FuturesObs{T}, D::T) where {T} = und.G

# ----------------------------------------
# Vol quote (prices are truth; IVs are cached views)
# ----------------------------------------

"""
VolQuote represents a market option quote with a snapshot interest rate
and cached implied vols computed under `iv_model` (default: BlackScholesAnalytical()).

Conventions:
- Use NaN for missing bid/ask/IV to stay concrete & AD-friendly.
- `interest_rate` is the continuous zero rate from `reference_date` to `payoff.expiry`.
"""
struct VolQuote{TPayoff, T<:Real, A<:AbstractPricingMethod}
    payoff::TPayoff
    underlying::UnderlyingObs{T}
    interest_rate::T
    mid_price::T
    bid_price::T
    ask_price::T
    mid_iv::T
    bid_iv::T
    ask_iv::T
    reference_date::Int64   # ms since epoch (quote observation / valuation clock for τ)
    source::Symbol
    iv_model::A             # canonically BlackScholesAnalytic()
end

# =========================
# VolQuote policy builder
# =========================

const ABS_TOL_P  = 1e-10
const REL_TOL_P  = 5e-7
const ABS_TOL_IV = 1e-8
const REL_TOL_IV = 1e-6

_isnan(x) = isnan(x)

"""
    make_volquote(payoff, underlying, interest_rate; kwargs...) -> VolQuote

Build a `VolQuote` enforcing the library policy:

Policy
- Mid is required: provide at least one of `mid_price` or `mid_iv`.
- For each of (bid, mid, ask):
  - If both (price, iv) are provided, check consistency and keep both (warn/throw on mismatch).
  - If only price is provided, compute iv.
  - If only iv is provided, compute price.
  - If neither, leave both as `NaN`.
- Prices are stored in **underlying units** (e.g., BTC). If you pass `normalized_input=true`,
  provided prices are assumed forward-normalized (price/F) and are denormalized internally.

Keyword arguments
- `mid_price`, `mid_iv`, `bid_price`, `bid_iv`, `ask_price`, `ask_iv` (default NaN)
- `reference_date::Int64` (required), `source::Symbol=:unknown`
- `iv_model::AbstractPricingMethod = BlackScholesAnalytic()`
- `normalized_input::Bool = false`  # inputs are price/F; builder multiplies by F
- `iv_guess::Real = 0.5`
- Tolerances: `abs_tol_p`, `rel_tol_p`, `abs_tol_iv`, `rel_tol_iv`
- Behavior: `warn_inconsistency::Bool = true`, `throw_inconsistency::Bool = false`,
            `throw_on_missing_mid::Bool = true`, `warn_monotonicity::Bool = true`,
            `throw_monotonicity::Bool = false`
"""
function VolQuote(
    payoff::TPayoff,
    underlying::UnderlyingObs{T},
    interest_rate::T;
    # sides
    mid_price::T = T(NaN), mid_iv::T = T(NaN),
    bid_price::T = T(NaN), bid_iv::T = T(NaN),
    ask_price::T = T(NaN), ask_iv::T = T(NaN),
    # meta
    reference_date::Int64,
    source::Symbol = :unknown,
    iv_model::A = BlackScholesAnalytic(),
    # options
    normalized_input::Bool = false,
    iv_guess::T = T(0.5),
    abs_tol_p::T = T(ABS_TOL_P),
    rel_tol_p::T = T(REL_TOL_P),
    abs_tol_iv::T = T(ABS_TOL_IV),
    rel_tol_iv::T = T(REL_TOL_IV),
    warn_inconsistency::Bool = true,
    throw_inconsistency::Bool = false,
    throw_on_missing_mid::Bool = true,
    warn_monotonicity::Bool = true,
    throw_monotonicity::Bool = false,
    warn_iv_monotonicity::Bool = true,
    throw_iv_monotonicity::Bool = false
) where {TPayoff, T<:AbstractFloat, A<:AbstractPricingMethod}

    # Build DF once; get spot-equivalent S* and forward F from the same snapshot.
    D = df(FlatRateCurve(reference_date, interest_rate), payoff.expiry)
    Sspot = _spot_from_obs(underlying, D)      # S* for BlackScholesAnalytic
    F     = _forward_from_obs(underlying, D)   # for (de)normalization

    # If inputs are forward-normalized, denormalize to absolute (underlying units).
    if normalized_input
        if ! _isnan(bid_price); bid_price *= F; end
        if ! _isnan(mid_price); mid_price *= F; end
        if ! _isnan(ask_price); ask_price *= F; end
    end

    # Require mid provided in at least one form
    if _isnan(mid_price) && _isnan(mid_iv)
        if throw_on_missing_mid
            throw(ArgumentError("VolQuote requires at least one of mid_price or mid_iv"))
        else
            @warn "VolQuote built without mid (both price and iv missing)"
        end
    end

    # Local helpers (absolute prices, underlying units)
    price_from_iv(iv::T) =
        iv_to_price(payoff, Sspot, interest_rate, iv, reference_date, iv_model)
    iv_from_price(p::T) =
        price_to_iv(payoff, Sspot, interest_rate, p, reference_date, iv_model; iv_guess=iv_guess)

    # Side resolver with consistency checks
    function resolve_side(P::T, σ::T)
        if !isnan(P) && !isnan(σ)
            P_chk = price_from_iv(σ)
            okP = abs(P - P_chk) ≤ max(abs_tol_p, rel_tol_p*max(one(T), abs(P)))
            if !okP
                if throw_inconsistency
                    throw(ArgumentError("Inconsistent price/IV: price=$P price_from_iv=$P_chk"))
                elseif warn_inconsistency
                    σ_chk = iv_from_price(P)  # compute only on mismatch
                    @warn "Inconsistent price/IV" price=P price_from_iv=P_chk iv_from_price=σ_chk
                end
            end
            return P, σ
        elseif !isnan(P)
            return P, iv_from_price(P)
        elseif !isnan(σ)
            return price_from_iv(σ), σ
        else
            return T(NaN), T(NaN)
        end
    end


    bid_price, bid_iv = resolve_side(bid_price, bid_iv)
    mid_price, mid_iv = resolve_side(mid_price, mid_iv)
    ask_price, ask_iv = resolve_side(ask_price, ask_iv)

    # Monotonicity checks (only when all sides are present)
    if (!_isnan(bid_price) && !_isnan(mid_price) && !_isnan(ask_price)) &&
       !(bid_price ≤ mid_price ≤ ask_price)
        if throw_monotonicity
            throw(ArgumentError("Price monotonicity violated: bid=$bid_price mid=$mid_price ask=$ask_price"))
        elseif warn_monotonicity
            @warn "Price monotonicity violated" bid=bid_price mid=mid_price ask=ask_price
        end
    end
    if (!_isnan(bid_iv) && !_isnan(mid_iv) && !_isnan(ask_iv)) &&
       !(bid_iv ≤ mid_iv ≤ ask_iv)
        if throw_iv_monotonicity
            throw(ArgumentError("IV monotonicity violated: bid_iv=$bid_iv mid_iv=$mid_iv ask_iv=$ask_iv"))
        elseif warn_iv_monotonicity
            @warn "IV monotonicity violated" bid_iv=bid_iv mid_iv=mid_iv ask_iv=ask_iv
        end
    end

    return VolQuote(
        payoff, underlying, interest_rate,
        mid_price, bid_price, ask_price,
        mid_iv, bid_iv, ask_iv,
        reference_date, source, iv_model
    )
end

function iv_to_price(
    payoff::AbstractPayoff,
    underlying_price::Real,
    interest_rate::Real,
    iv::Real,
    reference_date::Union{TimeType, Real},
    method::AbstractPricingMethod,
)
    zero_rate_curve = FlatRateCurve(to_ticks(reference_date), interest_rate)
    market_inputs = BlackScholesInputs(reference_date, zero_rate_curve, underlying_price, iv)
    prob = PricingProblem(payoff, market_inputs)
    return solve(prob, method).price
end
    
"""
    price_to_iv(payoff, underlying_price, interest_rate, price, reference_date, method;
                iv_guess=0.5, normalized_input=false)

Compute implied volatility under `method` (e.g., BlackScholesAnalytic()).

- `underlying_price` is the **spot-equivalent** S* you pass to the analytic BS pricer.
- If `normalized_input=true`, `price` is assumed **forward-normalized** (price/F); it is
  denormalized internally via `F = S* / DF`, where `DF = exp(-r*τ)`, `τ = yearfrac(reference_date, payoff.expiry)`.
- Returns σ.
"""
function price_to_iv(
    payoff::AbstractPayoff,
    underlying_price::Real,            # S* (spot-equivalent used by BS analytic)
    interest_rate::Real,
    price::Real,
    reference_date::Union{TimeType, Real},
    method::AbstractPricingMethod;
    iv_guess::Real = 0.5,
    normalized_input::Bool = false,
)
    # Curve & tenor
    rc = FlatRateCurve(interest_rate; reference_date=reference_date)
    DF = df(rc, payoff.expiry)

    # Denormalize if needed: F = S*/DF
    F = underlying_price / DF
    target_price = normalized_input ? price * F : price

    # Market inputs use S* (spot-equivalent), not F
    mi   = BlackScholesInputs(reference_date, rc, underlying_price, iv_guess)
    prob = BasketPricingProblem([payoff], mi)

    calib = CalibrationProblem(
        prob,
        method,
        [VolLens(1, 1)],               # calibrate the single vol parameter
        [target_price],
        [iv_guess],
    )
    sol = Hedgehog.solve(calib, RootFinderAlgo())
    return sol.u[1]
end

"""
    price_to_iv(vq::VolQuote, price; iv_guess=0.5, normalized_input=false)

Implied vol using `vq`’s interest rate, reference clock, and pricing model.

- If `normalized_input=true`, `price` is forward-normalized (price/F).
"""
function price_to_iv(
    vq::VolQuote,
    price::Real;
    iv_guess::Real = 0.5,
    normalized_input::Bool = false,
)
    Sspot = underlying_spot(vq.underlying, vq.interest_rate, vq.reference_date, vq.payoff.expiry)
    return price_to_iv(
        vq.payoff,
        Sspot,                    # S*
        vq.interest_rate,
        price,
        vq.reference_date,
        vq.iv_model;
        iv_guess=iv_guess,
        normalized_input=normalized_input,
    )
end

"""
    iv_to_price(vq::VolQuote, iv::Real; normalize::Bool = true)

Price the option under `vq.iv_model` for a given implied volatility.

# Arguments
- `vq`:       the volatility quote
- `iv`:       implied volatility
- `normalize`: if `true`, returns price / forward (forward-normalized);  
               if `false`, returns absolute price.

# Returns
- Option price (absolute or forward-normalized)
"""
function iv_to_price(vq::VolQuote, iv::Real; normalize::Bool = true)
    # spot-equivalent
    Sspot = underlying_spot(
        vq.underlying,
        vq.interest_rate,
        vq.reference_date,
        vq.payoff.expiry,
    )

    price_abs = iv_to_price(
        vq.payoff,
        Sspot,
        vq.interest_rate,
        iv,
        vq.reference_date,
        vq.iv_model,
    )

    if normalize
        F = underlying_forward(
            vq.underlying,
            vq.interest_rate,
            vq.reference_date,
            vq.payoff.expiry,
        )
        return price_abs / F
    else
        return price_abs
    end
end
