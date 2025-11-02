# -- Abstract Type --

"""
    AbstractForwardCurve

Abstract supertype for all forward/futures curve representations.
"""
abstract type AbstractForwardCurve end

# -- Structs --

"""
    FuturesCurve{F, R <: Real, I <: DataInterpolations.AbstractInterpolation} <: AbstractForwardCurve

Represents an interpolated futures/forward curve.

# Fields
- `reference_date::R`: The reference date for the curve, in internal tick units (milliseconds since epoch).
- `interpolator::I`: An interpolation object (from `DataInterpolations.jl`) representing forward prices as a function of year fractions.
- `builder::F`: A function `(u, t) -> interpolator` used to reconstruct the interpolator, where `u` are forward prices and `t` are year fractions.
"""
struct FuturesCurve{F, R <: Real, I <: DataInterpolations.AbstractInterpolation} <: AbstractForwardCurve
    reference_date::R
    interpolator::I
    builder::F
end

"""
    FlatForwardCurve{R <: Number, S <: Number} <: AbstractForwardCurve

Represents a flat forward curve with a constant forward price.

# Fields
- `reference_date::R`: The reference date for the curve, in internal tick units.
- `forward_price::S`: The constant forward price applied across all tenors.
"""
struct FlatForwardCurve{R <: Number, S <: Number} <: AbstractForwardCurve
    reference_date::R
    forward_price::S
end

# -- Constructors --

"""
    FlatForwardCurve(forward_price::Number; reference_date::TimeType = Date(0))

Creates a flat forward curve with constant forward price.

# Arguments
- `forward_price`: The constant forward/futures price.
- `reference_date`: The reference date (default is the Julia epoch).

# Returns
- A `FlatForwardCurve` instance.
"""
function FlatForwardCurve(forward_price::Number; reference_date::TimeType = Date(0))
    return FlatForwardCurve(to_ticks(reference_date), forward_price)
end

"""
    FuturesCurve(reference_date::Real, tenors::AbstractVector, forward_prices::AbstractVector; interp = ...)

Constructs a `FuturesCurve` from forward prices and tenors.

# Arguments
- `reference_date`: Time reference in internal tick units.
- `tenors`: Vector of year fractions (must be sorted and non-empty).
- `forward_prices`: Forward/futures prices matching each tenor.
- `interp`: A builder function `(u, t) -> interpolator` mapping forward prices and tenors to an interpolation object.

# Returns
- A `FuturesCurve` instance.
"""
function FuturesCurve(
    reference_date::Real,
    tenors::AbstractVector,
    forward_prices::AbstractVector;
    interp = (u, t) -> LinearInterpolation(u, t; extrapolation = ExtrapolationType.Constant),
)
    if isempty(tenors)
        throw(ArgumentError("Input 'tenors' cannot be empty."))
    end
    if length(tenors) != length(forward_prices)
        throw(ArgumentError("Mismatched lengths for 'tenors' and 'forward_prices'."))
    end
    if !issorted(tenors)
        throw(ArgumentError("'tenors' must be sorted."))
    end
    if tenors[1] < 0
        throw(ArgumentError("First tenor must be non-negative."))
    end
    if !all(>(0), forward_prices)
        throw(ArgumentError("All forward prices must be positive."))
    end

    itp = interp(forward_prices, tenors)
    return FuturesCurve(reference_date, itp, interp)
end

"""
    FuturesCurve(reference_date::Date, tenors::AbstractVector, forward_prices::AbstractVector; interp = ...)

Date-based overload for `FuturesCurve`.

# Arguments
- `reference_date`: A `Date` object.
- `tenors`: Vector of year fractions.
- `forward_prices`: Forward/futures prices.
- `interp`: Interpolator builder.

# Returns
- A `FuturesCurve` instance.
"""
function FuturesCurve(
    reference_date::Date,
    tenors::AbstractVector,
    forward_prices::AbstractVector;
    interp = (u, t) -> LinearInterpolation(u, t; extrapolation = ExtrapolationType.Flat),
)
    return FuturesCurve(to_ticks(reference_date), tenors, forward_prices; interp = interp)
end

"""
    FuturesCurve(reference_date::Date, itp::I, builder::F) where {I, F}

Constructs a `FuturesCurve` from pre-built interpolation components and a `Date`.

# Arguments
- `reference_date`: The date of the curve.
- `itp`: A `DataInterpolations.AbstractInterpolation` object.
- `builder`: The interpolator reconstruction function.

# Returns
- A `FuturesCurve` instance.
"""
function FuturesCurve(reference_date::Date, itp::I, builder::F) where {I, F}
    return FuturesCurve(to_ticks(reference_date), itp, builder)
end

# -- Accessors --

"""
    get_forward(curve::AbstractForwardCurve, ticks::Number)

Get the forward price at a given time point (in ticks).

# Returns
- Forward price as a real number.
"""
get_forward(curve::FuturesCurve, ticks::T) where T <: Number =
    curve.interpolator(yearfrac(curve.reference_date, ticks))

get_forward(curve::FlatForwardCurve, ticks::T) where T <: Number =
    curve.forward_price

"""
    get_forward(curve::AbstractForwardCurve, t::TimeType)

Get the forward price at a `Date` or `DateTime`.

# Returns
- Forward price as a real number.
"""
get_forward(curve::C, t::D) where {C <: AbstractForwardCurve, D <: TimeType} =
    get_forward(curve, to_ticks(t))

"""
    get_forward_yf(curve::AbstractForwardCurve, yf::Number)

Get the forward price from a year fraction.

# Returns
- Forward price as a real number.
"""
get_forward_yf(curve::FuturesCurve, yf::R) where R <: Number = curve.interpolator(yf)
get_forward_yf(curve::FlatForwardCurve, yf::R) where R <: Number = curve.forward_price

# -- Spine Access --

"""
    spine_tenors(curve::FuturesCurve)

Get the x-values (year fractions) used in the interpolator.

# Returns
- A vector of year fractions.
"""
spine_tenors(curve::FuturesCurve) = curve.interpolator.t

"""
    spine_forwards(curve::FuturesCurve)

Get the y-values (forward prices) used in the interpolator.

# Returns
- A vector of forward prices.
"""
spine_forwards(curve::FuturesCurve) = curve.interpolator.u

Base.length(curve::FuturesCurve) = length(curve.interpolator.t)
Base.length(curve::FlatForwardCurve) = 1