include("rate_conventions.jl")
include("fixed_rate.jl")
include("margin.jl")
include("float_rate.jl")

export 
    # rate_conventions.jl
    RateType, LinearRate, Compounded, Exponential, calculate_interest, discount_interest, compounding_factor, implied_rate, margined_rate,
    # fixed_rate.jl
    FixedRateConfig, FixedRate,CompoundedRate,AverageRate,
    # float_rate.jl
    AbstractRateIndex, RateIndex, FloatRateConfig, SimpleRateConfig, CompoundRateConfig, SimpleInstrumentRate, CompoundInstrumentRate,
    # margin.jl
    AdditiveMargin, MultiplicativeMargin, MarginOnCompoundedRate, MarginOnUnderlying, apply_margin