import DataInterpolations: LinearInterpolation, ExtrapolationType
import Dates: Date, value
import Base: getindex
export RateCurve, df, zero_rate, forward_rate, spine_tenors, spine_zeros

# -- Curve struct --
struct RateCurve{I}
    reference_date::Date
    interpolator::I  # Should be a callable interpolating function
end

# -- Constructor from discount factors (interpolate in zero rates) --
function RateCurve(
    reference_date::Date,
    tenors::AbstractVector{<:Real},
    dfs::AbstractVector{<:Real};
    interp = LinearInterpolation,
    extrap = ExtrapolationType.Constant
)
    @assert length(tenors) == length(dfs) "Mismatched tenor/DF lengths"
    @assert issorted(tenors) "Tenors must be sorted"

    zr = @. -log(dfs) / tenors  # continuous zero rate
    itp = interp(zr, tenors; extrapolation=extrap)
    return RateCurve(reference_date, itp)
end

# -- Accessors --
df(curve::RateCurve, t::Real) = exp(-zero_rate(curve, t) * t)
df(curve::RateCurve, t::Date) = df(curve, yearfrac(curve.reference_date, t))

zero_rate(curve::RateCurve, t::Real) = curve.interpolator(t)
zero_rate(curve::RateCurve, t::Date) = zero_rate(curve, yearfrac(curve.reference_date, t))

# -- Forward rate between two times --
function forward_rate(curve::RateCurve, t1::Real, t2::Real)
    df1 = df(curve, t1)
    df2 = df(curve, t2)
    return log(df1 / df2) / (t2 - t1)
end

forward_rate(curve::RateCurve, d1::Date, d2::Date) =
    forward_rate(curve, yearfrac(curve.reference_date, d1), yearfrac(curve.reference_date, d2))

# -- Diagnostic accessors --
spine_tenors(curve::RateCurve) = curve.interpolator.x
spine_zeros(curve::RateCurve) = curve.interpolator.y

FlatRateCurve(r::Float64) = RateCurve(
    Date(0),                  # reference_date (arbitrary, won't be used)
    [1e-8],                   # tiny positive tenor
    [exp(-r * 1e-8)],         # corresponding DF, gives back r via interpolation
    interp = LinearInterpolation,
    extrap = ExtrapolationType.Constant
)
