# ----------------------------------------
# Underlying observation (what we know)
# ----------------------------------------

abstract type UnderlyingObs{T<:Real} end
struct SpotObs{T<:Real}    <: UnderlyingObs{T}; S::T; end
struct ForwardObs{T<:Real} <: UnderlyingObs{T}; F::T; end
struct FuturesObs{T<:Real} <: UnderlyingObs{T}; G::T; end

# ----------------------------------------
# Volatility quote (prices are truth)
# ----------------------------------------

"""
VolQuote represents a market option quote under the Black–Scholes analytical model.

Fields:
- `payoff`           : option payoff (strike, expiry_ms, call/put, etc.)
- `underlying`       : SpotObs | ForwardObs | FuturesObs
- `rate_to_expiry`   : continuous zero rate from quote time → expiry
- `mid_price`        : mid market price (canonical)
- `bid_price`, `ask_price` : optional sides (NaN if missing)
- `mid_iv`, `bid_iv`, `ask_iv` : implied vols (NaN if not computed)
- `timestamp_ms`     : quote observation time (ms since epoch)
- `source`           : data origin (e.g., :deribit)
- `valuation_time_ms`: clock used for τ when computing IVs (default = timestamp)
- `iv_model`         : model used to compute IVs (:black_scholes by default)
"""
struct VolQuote{TPayoff, T<:Real}
    payoff::TPayoff
    underlying::UnderlyingObs{T}
    rate_to_expiry::T
    mid_price::T
    bid_price::T
    ask_price::T
    mid_iv::T
    bid_iv::T
    ask_iv::T
    timestamp_ms::Int64
    source::Symbol
    valuation_time_ms::Int64
    iv_model::Symbol
end

# ----------------------------------------
# Constructors with sensible defaults
# ----------------------------------------

"Convenient constructor using NaN for missing sides and Black–Scholes as model."
function VolQuote(
    payoff::TPayoff,
    underlying::UnderlyingObs{T},
    rate_to_expiry::T,
    mid_price::T;
    bid_price::T = NaN,
    ask_price::T = NaN,
    mid_iv::T = NaN,
    bid_iv::T = NaN,
    ask_iv::T = NaN,
    timestamp_ms::Int64 = 0,
    source::Symbol = :unknown,
    valuation_time_ms::Int64 = timestamp_ms,
    iv_model::Symbol = :black_scholes,
) where {TPayoff, T<:Real}
    return VolQuote(
        payoff, underlying, rate_to_expiry,
        mid_price, bid_price, ask_price,
        mid_iv, bid_iv, ask_iv,
        timestamp_ms, source,
        valuation_time_ms, iv_model
    )
end
