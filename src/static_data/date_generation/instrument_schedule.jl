"""
    AbstractInstrumentSchedule

An abstract type representing the schedule of an instrument.
"""
abstract type AbstractInstrumentSchedule end

"""
    InstrumentSchedule{D <: TimeType, C <: AbstractScheduleConfig, S <: AbstractShift} <: AbstractInstrumentSchedule

A concrete type representing the schedule of an instrument. This includes the start date, end date, schedule configuration, and pay shift.
"""
struct InstrumentSchedule{D <: TimeType, C <: AbstractScheduleConfig, S <: AbstractShift} <: AbstractInstrumentSchedule
    start_date::D
    end_date::D
    schedule_config::C
    pay_shift::S
end

"""
    InstrumentSchedule(start_date, end_date, schedule_config)

Creates an `InstrumentSchedule` with the given start date, end date, and schedule configuration, using a default pay shift of `NoShift`.

# Arguments

- `start_date`: The start date of the instrument schedule.
- `end_date`: The end date of the instrument schedule.
- `schedule_config`: The schedule configuration for the instrument.

# Returns

- An `InstrumentSchedule` object.
"""
function InstrumentSchedule(start_date, end_date, schedule_config::S) where S<:AbstractScheduleConfig
    return InstrumentSchedule(start_date, end_date, schedule_config, NoShift())
end

"""
    InstrumentSchedule(start_date, end_date, period)

Creates an `InstrumentSchedule` with the given start date, end date, and period, using a default schedule configuration with no roll convention and business days adjustments.

# Arguments

- `start_date`: The start date of the instrument schedule.
- `end_date`: The end date of the instrument schedule.
- `period`: The frequency of the schedule.

# Returns

- An `InstrumentSchedule` object.
"""
function InstrumentSchedule(start_date, end_date, period::P) where P<:Period
    return InstrumentSchedule(start_date, end_date, ScheduleConfig(period))
end

"""
    generate_schedule(instrument_schedule::InstrumentSchedule)

Generates a schedule of adjusted dates according to the given instrument schedule.

# Arguments
- `instrument_schedule::InstrumentSchedule`: The instrument schedule.

# Returns
- A schedule of adjusted dates.
"""
function generate_schedule(instrument_schedule::InstrumentSchedule)
    return generate_schedule(instrument_schedule.start_date, instrument_schedule.end_date, instrument_schedule.schedule_config)
end