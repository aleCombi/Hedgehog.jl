"""
    AbstractFlowStreamConfig

An abstract type that serves as the base for configurations related to flow streams of financial instruments.
Concrete types like `FixedStreamConfig` and `FloatStreamConfig` will inherit from this type.
"""
abstract type AbstractFlowStreamConfig end

"""
    struct FixedStreamConfig{P<:Number}

A parametric composite type that represents a fixed-rate flow stream with specified principal, rate, and schedule.
It is used for financial modeling, particularly in cases where a fixed interest rate is applied over a defined period.

# Type Parameters
- `P<:Number`: Represents the principal amount in the flow stream, typically a numeric type.

# Fields
- `principal::P`: The principal value of the flow stream.
- `rate::FixedRate`: A fixed interest or discount rate associated with the financial instrument.
- `schedule::InstrumentSchedule`: The schedule or timetable over which the cash flows occur.
"""
struct FixedStreamConfig{P<:Number} <: AbstractFlowStreamConfig
    principal::P
    rate::FixedRate
    schedule::InstrumentSchedule
end

"""
    struct FloatStreamConfig{P <: Number, F <: AbstractInstrumentRate}

A parametric composite type representing a floating-rate flow stream with a principal, a floating rate, and a schedule.
It is used for financial modeling, especially when the rate may vary based on market conditions.

# Type Parameters
- `P<:Number`: Represents the principal amount in the flow stream.
- `F<:AbstractInstrumentRate`: Represents a floating rate type that inherits from `AbstractInstrumentRate`.

# Fields
- `principal::P`: The principal value of the flow stream.
- `rate::F`: A floating rate associated with the financial instrument.
- `schedule::InstrumentSchedule`: The schedule or timetable for the flow stream.
"""
struct FloatStreamConfig{P <: Number, F <: AbstractInstrumentRate, S <: AbstractInstrumentSchedule} <: AbstractFlowStreamConfig
    principal::P
    rate::F
    schedule::S
end

"""
    FlowStream

An abstract type representing a stream of cash flows for financial instruments. 
Concrete stream types, such as `FixedRateStream` or `FloatRateStream`, should inherit from this type.
"""
abstract type FlowStream end

"""
    FloatStream

An abstract type representing a stream of float cash flows for financial instruments. 
Concrete stream types, such as `SimpleFloatRateStream` or `CompoundFloatRateStream`, should inherit from this type.
"""
abstract type FloatStream <: FlowStream end