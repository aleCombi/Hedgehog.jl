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
@inline _spot_from_obs(und::SpotObs{T},    D::Real) where {T} = und.S
@inline _spot_from_obs(und::ForwardObs{T}, D::Real) where {T} = und.F * D

# We treat futures as forwards; convexity adjustment not applied.
@inline _spot_from_obs(und::FuturesObs{T}, D::Real) where {T} = und.G * D 

function underlying_forward(
    und::UnderlyingObs{T},
    r::T,
    ref_ms::Union{TimeType,Int64},
    expiry::Union{Int64,TimeType},
) where {T<:Real}
    D = df(FlatRateCurve(to_ticks(ref_ms), r), to_ticks(expiry))  # DF = e^{-rτ}
    return _forward_from_obs(und, D)
end

@inline _forward_from_obs(und::SpotObs{T},    D::Real) where {T} = und.S / D   # F = S / DF
@inline _forward_from_obs(und::ForwardObs{T}, D::Real) where {T} = und.F
@inline _forward_from_obs(und::FuturesObs{T}, D::Real) where {T} = und.G

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

# ============================================================================
# Step 1: Input Normalization (Pure Function)
# ============================================================================

"""
    denormalize_prices(bid, mid, ask, F, normalized_input)

Convert forward-normalized prices (price/F) to absolute prices if needed.
"""
function denormalize_prices(
    bid_price::T,
    mid_price::T,
    ask_price::T,
    F::T,
    normalized_input::Bool
) where {T<:AbstractFloat}
    if !normalized_input
        return (bid_price, mid_price, ask_price)
    end
    
    return (
        isnan(bid_price) ? bid_price : bid_price * F,
        isnan(mid_price) ? mid_price : mid_price * F,
        isnan(ask_price) ? ask_price : ask_price * F
    )
end

# ============================================================================
# Step 2: Price/IV Resolution (Using Closures)
# ============================================================================

"""
    resolve_price_iv_pair(price, iv, price_from_iv, iv_from_price; 
                          abs_tol_p, rel_tol_p, warn, throw_err)

Given a price and/or IV, return consistent (price, iv).
"""
function resolve_price_iv_pair(
    price::T,
    iv::T,
    price_from_iv::Function,
    iv_from_price::Function;
    abs_tol_p::T = T(ABS_TOL_P),
    rel_tol_p::T = T(REL_TOL_P),
    vol_price_inconsistency_handling::Symbol = :warn # :warn, :throw, :ignore
) where {T<:AbstractFloat}
    # Both missing
    if isnan(price) && isnan(iv)
        return (T(NaN), T(NaN))
    end
    
    # Only price provided
    if !isnan(price) && isnan(iv)
        return (price, iv_from_price(price))
    end
    
    # Only IV provided
    if isnan(price) && !isnan(iv)
        return (price_from_iv(iv), iv)
    end
    
    # Both provided - check consistency
    price_check = price_from_iv(iv)
    is_consistent = isapprox(price, price_check; rtol=rel_tol_p, atol=abs_tol_p)
    
    if !is_consistent
        if vol_price_inconsistency_handling == :throw
            throw(ArgumentError(
                "Inconsistent price/IV: price=$price, price_from_iv=$price_check"
            ))
        elseif vol_price_inconsistency_handling == :warn
            iv_check = iv_from_price(price)
            @warn "Inconsistent price/IV" price price_from_iv=price_check iv iv_from_price=iv_check
        elseif vol_price_inconsistency_handling == :ignore
        # do nothing
        else 
            throw(ArgumentError("Invalid vol_price_inconsistency_handling: $vol_price_inconsistency_handling"))
        end
    end
    
    return (price, iv)
end

# ============================================================================
# Step 3: Validation (Pure Functions)
# ============================================================================

"""
    validate_required_mid(mid_price, mid_iv; throw_on_missing=true)

Ensure at least one of mid_price or mid_iv is provided.
"""
function validate_required_mid(
    mid_price::T,
    mid_iv::T;
    missing_mid_handling::Symbol = :throw # :throw, :warn
) where {T<:AbstractFloat}
    if isnan(mid_price) && isnan(mid_iv)
        msg = "VolQuote requires at least one of mid_price or mid_iv"
        if missing_mid_handling == :throw
            throw(ArgumentError(msg))
        elseif missing_mid_handling == :warn
            @warn msg
        else 
            throw(ArgumentError("Invalid missing_mid_handling: $missing_mid_handling"))
    
        end
    end
end

"""
    validate_monotonicity(bid, mid, ask, label; warn=true, throw_err=false)

Check that bid ≤ mid ≤ ask when all three are present.
"""
function validate_monotonicity(
    bid::T,
    mid::T,
    ask::T,
    label::String;
    monotonicity_handling::Symbol = :warn # :warn, :throw
) where {T<:AbstractFloat}
    # Skip if any value is missing
    (isnan(bid) || isnan(mid) || isnan(ask)) && return
    
    if !(bid ≤ mid ≤ ask)
        msg = "$label monotonicity violated: bid=$bid mid=$mid ask=$ask"
        if monotonicity_handling == :throw 
            throw(ArgumentError(msg))
        elseif monotonicity_handling == :warn
            @warn msg
        else 
            throw(ArgumentError("Invalid validation_outcome: $monotonicity_handling"))
        end
    end
end

"""
    validate_inputs(payoff, underlying, interest_rate, reference_date)

Check that input parameters are reasonable.
"""
function validate_inputs(
    payoff,
    underlying::UnderlyingObs{T},
    interest_rate::T,
    reference_date::Int64
) where {T<:Real}
    # Expiry after reference
    if payoff.expiry <= reference_date
        throw(ArgumentError(
            "Expiry ($(payoff.expiry)) must be after reference_date ($reference_date)"
        ))
    end
    
    # Positive underlying price
    S = underlying isa SpotObs ? underlying.S :
        underlying isa ForwardObs ? underlying.F : underlying.G
    
    S <= 0 && throw(ArgumentError("Underlying price must be positive, got $S"))
    
    # Reasonable rate (warn only)
    abs(interest_rate) > 1.0 && @warn "Interest rate seems unrealistic" rate=interest_rate
end

# ============================================================================
# Configuration Struct
# ============================================================================

"""
    VolQuoteConfig{T<:AbstractFloat, A<:AbstractPricingMethod}

Configuration parameters for VolQuote construction and validation.

# Fields
- `iv_model::A`: Pricing model for price/IV conversions (default: BlackScholesAnalytic())
- `iv_guess::T`: Initial guess for implied volatility solver (default: 0.5)
- `abs_tol_p::T`: Absolute tolerance for price consistency checks (default: 1e-10)
- `rel_tol_p::T`: Relative tolerance for price consistency checks (default: 5e-7)
- `vol_price_inconsistency_handling::Symbol`: How to handle price/IV mismatches (default: :warn)
  - `:throw` - throw an error
  - `:warn` - emit a warning
  - `:ignore` - silently accept inconsistencies
- `missing_mid_handling::Symbol`: How to handle missing mid price/IV (default: :throw)
  - `:throw` - throw an error
  - `:warn` - emit a warning
- `price_monotonicity_handling::Symbol`: How to handle bid > mid > ask violations in prices (default: :warn)
- `iv_monotonicity_handling::Symbol`: How to handle bid > mid > ask violations in IVs (default: :warn)
- `normalized_input::Bool`: Whether input prices are forward-normalized (price/F) (default: false)

# Examples
```julia
# Use defaults (BlackScholesAnalytic)
config = VolQuoteConfig{Float64}()

# Customize specific parameters
config = VolQuoteConfig{Float64}(
    vol_price_inconsistency_handling = :throw,
    iv_guess = 0.3
)

# Use different pricing model
config = VolQuoteConfig{Float64}(
    iv_model = CarrMadan(1.0, 32.0, HestonDynamics())
)

# Strict validation
strict_config = VolQuoteConfig{Float64}(
    vol_price_inconsistency_handling = :throw,
    missing_mid_handling = :throw,
    price_monotonicity_handling = :throw,
    iv_monotonicity_handling = :throw
)
```
"""
struct VolQuoteConfig{T<:AbstractFloat, A<:AbstractPricingMethod}
    iv_model::A
    iv_guess::T
    abs_tol_p::T
    rel_tol_p::T
    vol_price_inconsistency_handling::Symbol
    missing_mid_handling::Symbol
    price_monotonicity_handling::Symbol
    iv_monotonicity_handling::Symbol
    normalized_input::Bool
    
    function VolQuoteConfig{T, A}(;
        iv_model::A = BlackScholesAnalytic(),
        iv_guess::T = T(0.5),
        abs_tol_p::T = T(ABS_TOL_P),
        rel_tol_p::T = T(REL_TOL_P),
        vol_price_inconsistency_handling::Symbol = :warn,
        missing_mid_handling::Symbol = :throw,
        price_monotonicity_handling::Symbol = :warn,
        iv_monotonicity_handling::Symbol = :warn,
        normalized_input::Bool = false
    ) where {T<:AbstractFloat, A<:AbstractPricingMethod}
        # Validate handling symbols
        valid_inconsistency = (:throw, :warn, :ignore)
        valid_missing = (:throw, :warn)
        valid_monotonicity = (:throw, :warn)
        
        vol_price_inconsistency_handling ∈ valid_inconsistency || 
            throw(ArgumentError("vol_price_inconsistency_handling must be one of $valid_inconsistency"))
        missing_mid_handling ∈ valid_missing || 
            throw(ArgumentError("missing_mid_handling must be one of $valid_missing"))
        price_monotonicity_handling ∈ valid_monotonicity || 
            throw(ArgumentError("price_monotonicity_handling must be one of $valid_monotonicity"))
        iv_monotonicity_handling ∈ valid_monotonicity || 
            throw(ArgumentError("iv_monotonicity_handling must be one of $valid_monotonicity"))
        
        new{T, A}(
            iv_model, iv_guess, abs_tol_p, rel_tol_p,
            vol_price_inconsistency_handling, missing_mid_handling,
            price_monotonicity_handling, iv_monotonicity_handling,
            normalized_input
        )
    end
end

# Convenience constructor that infers types
function VolQuoteConfig(; 
    iv_model::A = BlackScholesAnalytic(),
    iv_guess::T = 0.5,
    kwargs...
) where {T<:AbstractFloat, A<:AbstractPricingMethod}
    return VolQuoteConfig{T, A}(; iv_model=iv_model, iv_guess=iv_guess, kwargs...)
end

# ============================================================================
# Refactored VolQuote Constructor
# ============================================================================

"""
    VolQuote(payoff, underlying, interest_rate;
             mid_price=NaN, mid_iv=NaN,
             bid_price=NaN, bid_iv=NaN,
             ask_price=NaN, ask_iv=NaN,
             reference_date::Int64,
             source=:unknown,
             config=VolQuoteConfig())

Construct a VolQuote from market data with optional bid/mid/ask prices and IVs.

At least one of `mid_price` or `mid_iv` must be provided. Missing values are inferred
using the pricing model specified in `config`. Prices and IVs are validated for consistency 
and monotonicity according to the settings in `config`.

# Arguments
- `payoff`: Option payoff specification
- `underlying`: Underlying observation (SpotObs, ForwardObs, or FuturesObs)
- `interest_rate`: Continuous zero rate from reference_date to expiry
- `mid_price`, `bid_price`, `ask_price`: Option prices (use NaN for missing)
- `mid_iv`, `bid_iv`, `ask_iv`: Implied volatilities (use NaN for missing)
- `reference_date`: Quote observation time in milliseconds since epoch
- `source`: Data source identifier (default: :unknown)
- `config`: Configuration for pricing model, validation and solver behavior (default: VolQuoteConfig())

# Examples
```julia
# Minimal construction with mid IV only (uses default BlackScholesAnalytic)
opt = VanillaOption(100.0, Date(2025,7,1), European(), Call(), Spot())
und = SpotObs(100.0)
vq = VolQuote(opt, und, 0.02; mid_iv=0.25, reference_date=to_ticks(Date(2025,1,1)))

# Full bid/mid/ask with custom configuration
config = VolQuoteConfig(
    vol_price_inconsistency_handling = :throw,
    iv_guess = 0.3
)
vq = VolQuote(
    opt, und, 0.02;
    bid_price=4.5, mid_price=5.0, ask_price=5.5,
    reference_date=to_ticks(Date(2025,1,1)),
    config=config
)

# Forward-normalized prices with different pricing model
config = VolQuoteConfig(
    iv_model = CarrMadan(1.0, 32.0, HestonDynamics()),
    normalized_input = true
)
vq = VolQuote(opt, und, 0.02; mid_price=0.05, reference_date=ref, config=config)
```
"""
function VolQuote(
    payoff::TPayoff,
    underlying::UnderlyingObs{T},
    interest_rate::T;
    # Prices and IVs
    mid_price::T = T(NaN), 
    mid_iv::T = T(NaN),
    bid_price::T = T(NaN), 
    bid_iv::T = T(NaN),
    ask_price::T = T(NaN), 
    ask_iv::T = T(NaN),
    # Metadata
    reference_date::Int64,
    source::Symbol = :unknown,
    # Configuration
    config::VolQuoteConfig{T, A} = VolQuoteConfig{T, typeof(BlackScholesAnalytic())}()
) where {TPayoff, T<:AbstractFloat, A<:AbstractPricingMethod}
    
    # Validate inputs
    validate_inputs(payoff, underlying, interest_rate, reference_date)
    validate_required_mid(mid_price, mid_iv; missing_mid_handling=config.missing_mid_handling)
    
    # Compute helpers
    D = df(FlatRateCurve(reference_date, interest_rate), payoff.expiry)
    Sspot = _spot_from_obs(underlying, D)
    F = _forward_from_obs(underlying, D)
    
    # Denormalize prices
    (bid_price, mid_price, ask_price) = denormalize_prices(
        bid_price, mid_price, ask_price, F, config.normalized_input
    )
    
    # Create converter functions (closures capture Sspot, interest_rate, etc.)
    price_from_iv(iv) = iv_to_price(payoff, Sspot, interest_rate, iv, reference_date, config.iv_model)
    iv_from_price(p) = price_to_iv(payoff, Sspot, interest_rate, p, reference_date, config.iv_model; 
                                    iv_guess=config.iv_guess)
    
    # Resolve all three sides
    (bid_price, bid_iv) = resolve_price_iv_pair(
        bid_price, bid_iv, price_from_iv, iv_from_price;
        abs_tol_p=config.abs_tol_p, 
        rel_tol_p=config.rel_tol_p, 
        vol_price_inconsistency_handling=config.vol_price_inconsistency_handling
    )
    (mid_price, mid_iv) = resolve_price_iv_pair(
        mid_price, mid_iv, price_from_iv, iv_from_price;
        abs_tol_p=config.abs_tol_p, 
        rel_tol_p=config.rel_tol_p, 
        vol_price_inconsistency_handling=config.vol_price_inconsistency_handling
    )
    (ask_price, ask_iv) = resolve_price_iv_pair(
        ask_price, ask_iv, price_from_iv, iv_from_price;
        abs_tol_p=config.abs_tol_p, 
        rel_tol_p=config.rel_tol_p, 
        vol_price_inconsistency_handling=config.vol_price_inconsistency_handling
    )
    
    # Validate monotonicity
    validate_monotonicity(
        bid_price, mid_price, ask_price, "Price"; 
        monotonicity_handling=config.price_monotonicity_handling
    )
    validate_monotonicity(
        bid_iv, mid_iv, ask_iv, "IV";
        monotonicity_handling=config.iv_monotonicity_handling
    )
    
    # Construct
    return VolQuote(
        payoff, underlying, interest_rate,
        mid_price, bid_price, ask_price,
        mid_iv, bid_iv, ask_iv,
        reference_date, source, config.iv_model
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
    rc = FlatRateCurve(to_ticks(reference_date), interest_rate)
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
