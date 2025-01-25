"""
    struct CompoundedRateStreamSchedules{D, A, B, N}

Defines a schedule of compounded rate streams. This structure holds information about payment dates, compounding schedules, and day counts for accrual periods in the context of financial instruments that apply compound interest rates.

# Fields
- `compounding_schedules::Vector{SimpleRateStreamSchedules{A,B}}`: A vector of simple rate stream schedules that determine the compounding intervals.
- `accrual_day_counts::Vector{N}`: A vector of total day counts for each compounding period, calculated from the `compounding_schedules`.

*Note*: The `pay_dates` field here only signifies scheduling purposes, without intrinsic meaning in the context of this struct.
"""
struct CompoundedRateSchedules{N<:Number, A, B, D<:TimeType} <: RateSchedule
    accrual_dates::Vector{D}
    compounding_schedules::Vector{SimpleRateSchedule{A,B}}
    accrual_day_counts::Vector{N}
end

"""
    CompoundedRateStreamSchedules(pay_dates::Vector{D}, compounding_schedules::Vector{SimpleRateStreamSchedules{A,B}}) where {D,A,B}

Constructor for `CompoundedRateStreamSchedules`, which initializes an instance with specified `pay_dates` and `compounding_schedules`. The constructor computes `accrual_day_counts` by summing up day counts from each schedule in `compounding_schedules`.

# Arguments
- `compounding_schedules::Vector{SimpleRateStreamSchedules{A,B}}`: Vector of schedules representing compounding intervals for the rate stream.

# Returns
- An instance of `CompoundedRateStreamSchedules` with computed `accrual_day_counts`.
"""
function CompoundedRateSchedules(accrual_dates, compounding_schedules::Vector{SimpleRateSchedule{A,B}}) where {A,B}
    accrual_day_counts = [sum(schedule.accrual_day_counts) for schedule in compounding_schedules]
    return CompoundedRateSchedules(accrual_dates, compounding_schedules, accrual_day_counts)
end

"""
    CompoundedRateStreamSchedules(stream_config::FloatStreamConfig{P,CompoundInstrumentRate}) where P

Constructs a `CompoundedRateStreamSchedules` instance based on a `FloatStreamConfig` structure. The method generates schedules of accrual and payment dates, then constructs compounding schedules for each period in the rate stream.

# Arguments
- `stream_config::FloatStreamConfig{P,CompoundInstrumentRate}`: Configuration data for a floating rate stream with a compounded interest instrument.

# Returns
- An instance of `CompoundedRateStreamSchedules` derived from the provided stream configuration.
"""
function CompoundedRateSchedules(stream_config::FloatStreamConfig{P,CompoundInstrumentRate}) where P
    accrual_dates = generate_schedule(stream_config.schedule)
    rate_config = stream_config.rate.rate_config
    compounding_schedules = [SimpleRateSchedule(accrual_dates[i], accrual_dates[i+1], rate_config.compound_schedule, rate_config, stream_config.rate.rate_index) for i in 1:length(accrual_dates)-1]
    return CompoundedRateSchedules(accrual_dates, compounding_schedules)
end

"""
    struct CompoundFloatRateStream{P,S} <: FlowStream where P

Represents a compound floating rate stream configuration within a `FlowStream` context. It includes a configuration for a floating rate stream and schedules for calculating compounded rates.

# Fields
- `config::FloatStreamConfig{P,CompoundInstrumentRate}`: Configuration data for the compound rate stream, including details of the rate and scheduling.
- `schedules::CompoundedRateStreamSchedules`: Pre-computed schedules for payment and compounding dates, derived from the `config`.
"""
struct CompoundFloatRateStream{P,S,D} <: FloatStream where {P,S,D<:TimeType}
    config::FloatStreamConfig{P,CompoundInstrumentRate, S}
    schedules::CompoundedRateSchedules
    pay_dates::Vector{D}
end

"""
    CompoundFloatRateStream(stream_config::FloatStreamConfig{P,CompoundInstrumentRate}) where P

Creates a `CompoundFloatRateStream` instance using the provided `FloatStreamConfig` for a compounded rate. The schedules for the stream are automatically generated based on the configuration.

# Arguments
- `stream_config::FloatStreamConfig{P,CompoundInstrumentRate}`: Configuration for the floating rate stream with compound interest details.

# Returns
- An instance of `CompoundFloatRateStream` initialized with the provided configuration and generated schedules.
"""
function CompoundFloatRateStream(stream_config::FloatStreamConfig{P,CompoundInstrumentRate, S}) where {P,S}
    schedules = CompoundedRateSchedules(stream_config)
    pay_dates = shifted_trimmed_schedule(schedules.accrual_dates, stream_config.schedule.pay_shift)
    return CompoundFloatRateStream(stream_config, schedules, pay_dates)
end
