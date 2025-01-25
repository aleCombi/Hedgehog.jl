include("flow_stream.jl")
include("fixed_rate_stream.jl")
include("simple_rate_float_stream.jl")
include("compound_rate_float_stream.jl")

export
    # flow_stream.jl
    AbstractFlowStreamConfig, FloatStreamConfig, FixedStreamConfig, FlowStream, 
    # fixed_rate_stream.jl
    FixedRateStream,
    # simple_rate_float_stream.jl
    SimpleRateSchedule, SimpleFloatRateStream,
    # compound_rate_float_stream.jl
    CompoundedRateSchedules, CompoundFloatRateStream