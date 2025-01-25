abstract type RateSchedule end

"""
    struct SimpleRateStreamSchedules{D <: TimeType, T <: Number}

Represents a schedule for simple rate streams, including payment dates, fixing dates, discount dates, and accrual information.

# Fields
- `fixing_dates::Vector{D}`: A vector of dates for fixing rates, typically set in advance of payment dates.
- `discount_start_dates::Vector{D}`: A vector of start dates for the discounting period.
- `discount_end_dates::Vector{D}`: A vector of end dates for the discounting period.
- `accrual_dates::Vector{D}`: A vector of accrual period start dates.
- `accrual_day_counts::Vector{T}`: A vector of day count fractions for each accrual period, representing the portion of the year.

This struct is meant to give all the pre-computable date-related data about a list of floating rates."""
struct SimpleRateSchedule{D <: TimeType, T <: Number} <: RateSchedule
    fixing_dates::Vector{D}
    observation_start::Vector{D}
    observation_end::Vector{D}
    accrual_dates::Vector{D}
    accrual_day_counts::Vector{T}
end

"""
    SimpleRateStreamSchedules(stream_config::FloatStreamConfig{P, SimpleInstrumentRate}) -> SimpleRateStreamSchedules

Creates a `SimpleRateStreamSchedules` object from a given `FloatStreamConfig`, setting up schedules for payments, fixings, discounts,
and accruals.

# Arguments
- `stream_config::FloatStreamConfig{P, SimpleInstrumentRate}`: Configuration for the floating rate stream, including payment schedules and rate conventions.

# Returns
- A `SimpleRateStreamSchedules` instance with generated payment, fixing, discount, and accrual dates.
"""
function SimpleRateSchedule(stream_config::FloatStreamConfig{P,SimpleInstrumentRate}) where P
    return SimpleRateSchedule(stream_config.schedule, stream_config.rate.rate_config,  stream_config.rate.rate_index)
end

"""
    SimpleRateStreamSchedules(instrument_schedule::S, rate_config::SimpleRateConfig) -> SimpleRateStreamSchedules

Generates a `SimpleRateStreamSchedules` object using an `AbstractInstrumentSchedule` and a `SimpleRateConfig`. The schedule includes payment dates,
fixing dates, discount dates, accrual dates, and accrual day counts.

# Arguments
- `instrument_schedule::S <: AbstractInstrumentSchedule`: The instrument schedule containing information on accrual and payment dates.
- `rate_config::SimpleRateConfig`: Rate configuration specifying day count conventions and fixing shifts.

# Returns
- A `SimpleRateStreamSchedules` instance containing payment dates, fixing dates, discount start and end dates, accrual dates, and day counts.
"""
function SimpleRateSchedule(start_date::D, end_date::D, schedule_config::S, rate_config::R, rate_index::I) where {D<:TimeType, S <: AbstractScheduleConfig, R <: AbstractRateConfig, I<:AbstractRateIndex}
    accrual_dates = generate_schedule(start_date, end_date, schedule_config)
    time_fractions = day_count_fraction(accrual_dates, rate_config.day_count_convention)
    fixing_dates = shifted_trimmed_schedule(accrual_dates, rate_config.fixing_shift)
    (observation_start, observation_end) = observation_dates(fixing_dates, rate_index)
    return SimpleRateSchedule(fixing_dates, observation_start, observation_end, accrual_dates, time_fractions)
end

function observation_dates(fixing_dates, rate_index::RateIndex{ForwardLooking,P,B,C}) where {P,B,C}
    observation_start = fixing_dates
    observation_end = generate_end_date(fixing_dates, rate_index)
    return observation_start, observation_end
end

function observation_dates(fixing_dates, rate_index::RateIndex{BackwardLooking,P,B,C}) where {P,B,C}
    observation_end = fixing_dates
    observation_start = generate_start_date(fixing_dates, rate_index)
    return observation_start, observation_end
end

function SimpleRateSchedule(instrument_schedule::I, rate_config::R, rate_index::In) where {I<:AbstractInstrumentSchedule,R <: AbstractRateConfig, In<:AbstractRateIndex}
    return SimpleRateSchedule(instrument_schedule.start_date, instrument_schedule.end_date, instrument_schedule.schedule_config, rate_config, rate_index)
end

"""
    SimpleRateStreamSchedules(fixing_dates::Vector{D}, discount_start_dates::Vector{D}, 
                              discount_end_dates::Vector{D}, accrual_dates::Vector{D}, day_count_convention::C) 
                              where {C<:DayCount, D<:TimeType}

Creates a schedule of rate streams, with associated time fractions, based on specified payment dates, fixing dates, 
discount start and end dates, and accrual dates.

# Arguments
- `fixing_dates::Vector{D}`: A vector of fixing dates, indicating when the rates are determined for each period.
- `discount_start_dates::Vector{D}`: A vector of start dates for discounting, marking the beginning of each discount period.
- `discount_end_dates::Vector{D}`: A vector of end dates for discounting, marking the end of each discount period.
- `accrual_dates::Vector{D}`: A vector of accrual dates, representing the periods over which accrual is calculated.
- `day_count_convention::C`: A day count convention of type `C<:DayCount`, which specifies how days are counted in the accrual periods.

# Returns
- A `SimpleRateStreamSchedules` object, containing the input schedule data along with computed time fractions for each accrual period, based on the provided day count convention.

# Details
The function calculates time fractions for each accrual period using the `day_count_fraction` function, which applies the specified day count convention to the provided accrual dates. These time fractions are then incorporated into the `SimpleRateStreamSchedules` object, providing a structured schedule with consistent rate periods and accruals.

"""
function SimpleRateSchedule(fixing_dates::Vector{D}, discount_start_dates::Vector{D}, discount_end_dates::Vector{D}, accrual_dates::Vector{D}, day_count_convention::C) where {C<:DayCount, D<:TimeType}
    time_fractions = day_count_fraction(accrual_dates, day_count_convention)
    return SimpleRateSchedule(fixing_dates, discount_start_dates, discount_end_dates, accrual_dates, time_fractions)
end

"""
    Base.getindex(obj::SimpleRateStreamSchedules, index::Int) -> NamedTuple

Allows indexing into a `SimpleRateStreamSchedules` object using square brackets (`[]`). Returns a named tuple containing the relevant schedule dates for the specified index.

# Arguments
- `obj::SimpleRateStreamSchedules`: The `SimpleRateStreamSchedules` instance to index into.
- `index::Int`: The position in the schedule to retrieve.

# Returns
- A named tuple with the following fields:
    - `accrual_start`: The start date of the accrual period.
    - `accrual_end`: The end date of the accrual period.
    - `fixing_date`: The fixing date for the interest rate.
    - `pay_date`: The payment date.
    - `discount_first_date`: The start date for the discounting period.
    - `discount_end_date`: The end date for the discounting period.
"""
function Base.getindex(obj::SimpleRateSchedule, index::Int)
    return (accrual_start = obj.accrual_dates[index],
            accrual_end = obj.accrual_dates[index + 1],
            fixing_date = obj.fixing_dates[index],
            observation_start = obj.observation_start[index],
            observation_end = obj.observation_end[index])
end

"""
    iterate(s::SimpleRateStreamSchedules, state=1)

Iterator function for `SimpleRateStreamSchedules` type. Returns the current schedule and the next state 
until the end of the list is reached.

# Arguments
- `s::SimpleRateStreamSchedules`: The object containing a list of rate stream schedules.
- `state`: The current state (position) within the list, defaults to `1`.

# Returns
- A tuple `(current_schedule, next_state)` where `current_schedule` is the item at the current position in `s`,
  and `next_state` is the next index to iterate. 
- Returns `nothing` if the state exceeds the length of `s`, signaling the end of the iteration.

"""
function Base.iterate(s::SimpleRateSchedule, state=1)
    state > length(s) && return nothing
    return s[state], state + 1
end

"""
    Base.length(obj::SimpleRateStreamSchedules) -> Int

Returns the number of periods in the `SimpleRateStreamSchedules` object by measuring the length of the `fixing_dates` vector.

# Arguments
- `obj::SimpleRateStreamSchedules`: The `SimpleRateStreamSchedules` instance whose length is to be determined.

# Returns
- The number of periods in the schedule, represented as an integer.
"""
function Base.length(obj::SimpleRateSchedule)
    return length(obj.fixing_dates)
end

"""
    struct FloatingRateStream{D, T} <: FlowStream

A type representing a stream of floating-rate cash flows with specified dates for payments, accrual, and rate fixings.

# Fields
- `config::FloatRateStreamConfig`: The configuration details for the floating-rate stream.
- `pay_dates::Vector{D}`: Vector of payment dates.
- `fixing_dates::Vector{D}`: Vector of fixing dates, determining when rates are set.
- `accrual_dates::Vector{D}`: Vector of start dates for each accrual period.
- `accrual_day_counts::Vector{T}`: Vector of day count fractions for each accrual period.

This struct is primarily used to calculate and manage floating-rate payment streams based on predefined schedules and rate conventions.
"""
struct SimpleFloatRateStream{P,D} <: FloatStream where {P, D<:TimeType}
    config::FloatStreamConfig{P, SimpleInstrumentRate}
    schedules::SimpleRateSchedule
    pay_dates::Vector{D}
end

"""
    SimpleFloatRateStream(config::FloatStreamConfig{P, SimpleInstrumentRate}) -> SimpleFloatRateStream

Creates a `SimpleFloatRateStream` using a given `FloatStreamConfig` configuration. The function initializes the schedules
for payment, fixing, and accrual based on the input configuration.

# Arguments
- `config::FloatStreamConfig{P, SimpleInstrumentRate}`: The configuration for the floating-rate stream, specifying schedules and rate conventions.

# Returns
- A `SimpleFloatRateStream` instance with the calculated schedules.
"""
function SimpleFloatRateStream(stream_config::FloatStreamConfig{P, SimpleInstrumentRate}) where P
    schedules = SimpleRateSchedule(stream_config)
    pay_dates = shifted_trimmed_schedule(schedules.accrual_dates, stream_config.schedule.pay_shift)
    return SimpleFloatRateStream(stream_config, schedules, pay_dates)
end
