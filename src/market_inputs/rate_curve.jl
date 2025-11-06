# -- Structs --

"""
    AbstractRateCurve

Abstract supertype for all rate curve representations (e.g., flat, interpolated).
"""
abstract type AbstractRateCurve end

"""
    RateCurve{F, I <: DataInterpolations.AbstractInterpolation} <: AbstractRateCurve

Represents an interpolated rate curve based on zero rates derived from input discount factors.

# Fields
- `reference_date::Int64`: The reference date for the curve, represented in internal tick units (e.g., milliseconds since epoch).
- `interpolator::I`: An interpolation object (from `DataInterpolations.jl`) representing the zero rate curve as a function of year fractions.
- `builder::F`: A function `(u, t) -> interpolator` used to reconstruct the interpolator (e.g., during calibration), where `u` are zero rates and `t` are year fractions.
"""
struct RateCurve{F, I <: DataInterpolations.AbstractInterpolation} <: AbstractRateCurve
    reference_date::Int64
    interpolator::I
    builder::F
end

"""
    FlatRateCurve{S <: Number} <: AbstractRateCurve

Represents a flat curve with a constant continuously compounded zero rate.

# Fields
- `reference_date::Int64`: The reference date for the curve, in internal tick units.
- `rate::S`: The constant zero rate applied across all tenors.
"""
struct FlatRateCurve{S <: Number} <: AbstractRateCurve
    reference_date::Int64
    rate::S
end

# -- Constructors --

"""
    FlatRateCurve(rate::Number; reference_date::TimeType = Date(0))

Creates a flat curve with constant zero rate.

# Arguments
- `rate`: The constant continuously compounded rate.
- `reference_date`: The reference date (default is the Julia epoch).

# Returns
- A `FlatRateCurve` instance.
"""
function FlatRateCurve(rate::Number; reference_date::TimeType = Date(0))
    return FlatRateCurve(to_ticks(reference_date), rate)
end

"""
    RateCurve(reference_date::Real, tenors::AbstractVector, dfs::AbstractVector; interp = ...)

Constructs a `RateCurve` from discount factors and tenors.

# Arguments
- `reference_date`: Time reference in internal tick units.
- `tenors`: Vector of year fractions (must be sorted and non-empty).
- `dfs`: Discount factors matching each tenor.
- `interp`: A builder function `(u, t) -> interpolator` mapping zero rates and tenors to an interpolation object.

# Returns
- A `RateCurve` instance.
"""
function RateCurve(
    reference_date::Real,
    tenors::AbstractVector,
    dfs::AbstractVector;
    interp = (u, t) -> LinearInterpolation(u, t; extrapolation = ExtrapolationType.Constant),
)
    if isempty(tenors)
        throw(ArgumentError("Input 'tenors' cannot be empty."))
    end
    if length(tenors) != length(dfs)
        throw(ArgumentError("Mismatched lengths for 'tenors' and 'dfs'."))
    end
    if !issorted(tenors)
        throw(ArgumentError("'tenors' must be sorted."))
    end
    if tenors[1] < 0
        throw(ArgumentError("First tenor must be non-negative."))
    end
    if !all(>(0), dfs)
        throw(ArgumentError("All discount factors must be positive."))
    end

    zr = @. -log(dfs) / tenors
    itp = interp(zr, tenors)
    return RateCurve(reference_date, itp, interp)
end

"""
    RateCurve(reference_date::Date, tenors::AbstractVector, dfs::AbstractVector; interp = ...)

Date-based overload for `RateCurve`.

# Arguments
- `reference_date`: A `Date` object.
- `tenors`: Vector of year fractions.
- `dfs`: Discount factors.
- `interp`: Interpolator builder.

# Returns
- A `RateCurve` instance.
"""
function RateCurve(
    reference_date::Date,
    tenors::AbstractVector,
    dfs::AbstractVector;
    interp = (u, t) -> LinearInterpolation(u, t; extrapolation = ExtrapolationType.Constant),
)
    return RateCurve(to_ticks(reference_date), tenors, dfs; interp = interp)
end

"""
    RateCurve(reference_date::Date, itp::I, builder::F) where {I, F}

Constructs a `RateCurve` from pre-built interpolation components and a `Date`.

# Arguments
- `reference_date`: The date of the curve.
- `itp`: A `DataInterpolations.AbstractInterpolation` object.
- `builder`: The interpolator reconstruction function.

# Returns
- A `RateCurve` instance.
"""
function RateCurve(reference_date::Date, itp::I, builder::F) where {I, F}
    return RateCurve(to_ticks(reference_date), itp, builder)
end

# -- Accessors --

"""
    df(curve::AbstractRateCurve, ticks::Number)

Compute the discount factor at a given time point (in ticks).

# Returns
- Discount factor as a real number.
"""
df(curve::R, ticks::T) where {T <: Number, R <: AbstractRateCurve} =
    exp(-zero_rate(curve, ticks) * yearfrac(curve.reference_date, ticks))

"""
    df(curve::AbstractRateCurve, t::TimeType)

Compute the discount factor at a `Date` or `DateTime`.

# Returns
- Discount factor as a real number.
"""
df(curve::R, t::D) where {R <: AbstractRateCurve, D <: TimeType} =
    df(curve, to_ticks(t))

"""
    df_yf(curve::AbstractRateCurve, yf::Number)

Compute the discount factor from a year fraction.

# Returns
- Discount factor as a real number.
"""
df_yf(curve::R, yf::T) where {R <: AbstractRateCurve, T <: Number} =
    exp(-zero_rate_yf(curve, yf) * yf)

"""
    zero_rate(curve::AbstractRateCurve, ticks::Number)

Compute the zero rate for a time point given in ticks.

# Returns
- Continuously compounded rate as a real number.
"""
zero_rate(curve::RateCurve, ticks::T) where T <: Number =
    curve.interpolator(yearfrac(curve.reference_date, ticks))

zero_rate(curve::FlatRateCurve, ticks::T) where T <: Number =
    curve.rate

"""
    zero_rate(curve::AbstractRateCurve, t::TimeType)

Compute the zero rate for a `Date` or `DateTime`.

# Returns
- Continuously compounded rate as a real number.
"""
zero_rate(curve::R, t::D) where {R <: AbstractRateCurve, D <: TimeType} =
    zero_rate(curve, to_ticks(t))

"""
    zero_rate_yf(curve::AbstractRateCurve, yf::Number)

Compute the zero rate from a year fraction.

# Returns
- Continuously compounded rate as a real number.
"""
zero_rate_yf(curve::RateCurve, yf::R) where R <: Number = curve.interpolator(yf)
zero_rate_yf(curve::FlatRateCurve, yf::R) where R <: Number = curve.rate

# -- Forward Rates --

"""
    forward_rate(curve::RateCurve, t1::Real, t2::Real)

Calculate the forward rate between two year fractions.

# Returns
- Forward rate as a real number.
"""
function forward_rate(curve::RateCurve, t1::Real, t2::Real)
    if t1 >= t2
        throw(ArgumentError("Start time must be before end time."))
    end
    df1 = df_yf(curve, t1)
    df2 = df_yf(curve, t2)
    return log(df1 / df2) / (t2 - t1)
end

"""
    forward_rate(curve::RateCurve, d1::Date, d2::Date)

Calculate the forward rate between two dates.

# Returns
- Forward rate as a real number.
"""
forward_rate(curve::RateCurve, d1::Date, d2::Date) = forward_rate(
    curve,
    yearfrac(curve.reference_date, d1),
    yearfrac(curve.reference_date, d2),
)

# -- Spine Access --

"""
    spine_tenors(curve::RateCurve)

Get the x-values (year fractions) used in the interpolator.

# Returns
- A vector of year fractions.
"""
spine_tenors(curve::RateCurve) = curve.interpolator.t

"""
    spine_zeros(curve::RateCurve)

Get the y-values (zero rates) used in the interpolator.

# Returns
- A vector of zero rates.
"""
spine_zeros(curve::RateCurve) = curve.interpolator.u
