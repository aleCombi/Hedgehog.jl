"""
    AbstractExerciseStyle

Abstract type representing the exercise style of an option (e.g., European or American).
"""
abstract type AbstractExerciseStyle end

"""
    European <: AbstractExerciseStyle

Represents a European-style option that can only be exercised at expiry.
"""
struct European <: AbstractExerciseStyle end

"""
    American <: AbstractExerciseStyle

Represents an American-style option that can be exercised at any time before or at expiry.
"""
struct American <: AbstractExerciseStyle end

"""
    AbstractPayoff

An abstract type representing a financial payoff, such as a vanilla European option, an Asian option, or a forward.
"""
abstract type AbstractPayoff end

"""
    Underlying

Abstract type representing the nature of the underlying asset.
"""
abstract type Underlying end

"""
    Spot <: Underlying

Represents an underlying defined in terms of spot price.
"""
struct Spot <: Underlying end

"""
    Forward <: Underlying

Represents an underlying defined in terms of forward price.
"""
struct Forward <: Underlying end

"""
    AbstractCallPut

Abstract type representing whether an option is a call or a put.
"""
abstract type AbstractCallPut end

"""
    Put <: AbstractCallPut

Represents a put option.
"""
struct Put <: AbstractCallPut end

"""
    Call <: AbstractCallPut

Represents a call option.
"""
struct Call <: AbstractCallPut end

"""
    (call_put::Call)() -> 1.0

Returns the call-put indicator for a call option (+1).
"""
function (call_put::Call)()
    return 1.0
end

"""
    (call_put::Put)() -> -1.0

Returns the call-put indicator for a put option (-1).
"""
function (call_put::Put)()
    return -1.0
end

"""
    VanillaOption{TS,TE,E,C,U} <: AbstractPayoff

A vanilla option with specified exercise style, call/put type, and underlying type.

# Fields
- `strike`: The strike price of the option.
- `expiry`: The expiry (maturity) time in internal tick units.
- `exercise_style`: Instance of `European` or `American`.
- `call_put`: Instance of `Call` or `Put`.
- `underlying`: Either `Spot` or `Forward`.
"""
struct VanillaOption{TS,TE,E,C,U} <: AbstractPayoff where {
    TS<:Real,
    E<:AbstractExerciseStyle,
    C<:AbstractCallPut,
    U<:Underlying,
}
    strike::TS
    expiry::Int64
    exercise_style::E
    call_put::C
    underlying::U
end

"""
    VanillaOption(strike, expiry_date, exercise_style, call_put, underlying)

Constructs a `VanillaOption` using a calendar `expiry_date` (e.g. `Date`, `DateTime`, etc.),
which is converted internally to tick units via `to_ticks`.

# Arguments
- `strike`: Strike price of the option.
- `expiry_date`: Maturity as a date/time object (converted to ticks).
- `exercise_style`: `European()` or `American()`.
- `call_put`: `Call()` or `Put()`.
- `underlying`: `Spot()` or `Forward()`.

# Returns
- A fully constructed `VanillaOption` instance.
"""
function VanillaOption(
    strike::TS,
    expiry_date::TimeType,
    exercise_style::E,
    call_put::C,
    underlying::U,
) where {E<:AbstractExerciseStyle,C<:AbstractCallPut,U<:Underlying,TS<:Real}
    expiry_ticks = to_ticks(expiry_date)
    return VanillaOption{TS,TS,E,C,U}(strike, expiry_ticks, exercise_style, call_put, underlying)
end

"""
    (payoff::VanillaOption)(spot)

Computes the intrinsic payoff of a vanilla option for a given spot price or array of spot prices.

# Arguments
- `payoff`: A `VanillaOption` instance.
- `spot`: A single spot price (`Real`) or an array of spot prices.

# Returns
- The intrinsic value(s), i.e. `max(cp * (S - K), 0)`, where `cp` is +1 for a call and -1 for a put.
"""
function (payoff::VanillaOption)(spot)
    return max.(payoff.call_put() .* (spot .- payoff.strike), 0.0)
end

"""
    parity_transform(call_price, opt::VanillaOption{T, E, Call, U}, spot, rate_curve)

Returns the call price unchanged. Useful for unified pricing APIs that accept both calls and puts.

# Arguments
- `call_price`: Price of the call option.
- `opt`: A `VanillaOption` with `Call()` payoff.
- `spot`: Spot price.
- `rate_curve`: Rate curve.

# Returns
- The same `call_price`, unchanged.
"""
function parity_transform(call_price, ::VanillaOption{TS,TE,E,Call,U}, spot, rate) where {TS,TE,E,U}
    return call_price
end

"""
    parity_transform(call_price, opt::VanillaOption{T, E, Put, U}, spot, rate_curve)

Applies put-call parity to recover the put price from a known call price.

# Arguments
- `call_price`: Price of the call option.
- `opt`: A `VanillaOption` with `Put()` payoff.
- `spot`: Spot price.
- `rate_curve`: Rate curve.

# Returns
- The corresponding put price using the formula: `put = call - S + K * exp(-rT)`
  where `T` is extracted from `opt.expiry`.
"""
function parity_transform(call_price, opt::VanillaOption{TS,TE,E,Put,U}, spot, rate_curve) where {TS,TE,E,U}
    return call_price - spot + opt.strike * df(rate_curve, opt.expiry)
end
