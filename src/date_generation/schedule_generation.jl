"""
	AbstractScheduleConfig

Abstract type representing the configuration for generating an accrual schedule in a stream of cash flows.
"""
abstract type AbstractScheduleConfig end

"""
	ScheduleConfig{P <: Period, R <: RollConvention, B <: BusinessDayConvention, D <: BusinessDayConvention, C <: HolidayCalendar} <: AbstractScheduleConfig

Represents the configuration for generating a schedule. It includes the period, roll convention, business day convention, 
termination business day convention, holiday calendar, and the stub period.

# Fields
- `period::P`: The period for generating dates.
- `roll_convention::R`: The roll convention to adjust dates.
- `business_days_convention::B`: The business day convention for adjusting non-business days.
- `termination_bd_convention::D`: The convention for adjusting the termination date.
- `calendar::C`: The holiday calendar.
- `stub_period::StubPeriod`: The configuration of the stub period.
"""
struct ScheduleConfig{P<:Period,R<:RollConvention,B<:BusinessDayConvention,D<:BusinessDayConvention,C<:HolidayCalendar} <: AbstractScheduleConfig
    period::P
    roll_convention::R
    business_days_convention::B
    termination_bd_convention::D
    calendar::C
    stub_period::StubPeriod
end

"""
	ScheduleConfig(period::P; roll_convention, business_days_convention, calendar, stub_period, termination_bd_convention) -> ScheduleConfig

Constructor for `ScheduleConfig`, allowing default values for optional fields.

# Arguments
- `period::P`: The period for generating dates.
- `roll_convention::R`: The roll convention to adjust dates (default `NoRollConvention()`).
- `business_days_convention::B`: The business day convention (default `NoneBusinessDayConvention()`).
- `calendar::C`: The holiday calendar (default `NoHolidays()`).
- `stub_period::StubPeriod`: Configuration of the stub period (default `StubPeriod()`).
- `termination_bd_convention::D`: Convention for adjusting termination date (default `NoneBusinessDayConvention()`).

# Returns
- A new `ScheduleConfig` instance.
"""
function ScheduleConfig(period::P;
    roll_convention::R=NoRollConvention(),
    business_days_convention::B=NoneBusinessDayConvention(),
    calendar::C=NoHolidays(),
    stub_period::StubPeriod=StubPeriod(),
    termination_bd_convention::D=NoneBusinessDayConvention()) where {P<:Period,R<:RollConvention,B<:BusinessDayConvention,D<:BusinessDayConvention,C<:HolidayCalendar}
    return ScheduleConfig(period, roll_convention, business_days_convention, termination_bd_convention, calendar, stub_period)
end

"""
	generate_unadjusted_dates(start_date, end_date, stub_period::StubPeriod, period::P) where P <: Period

Generates a stream of unadjusted dates according to the given period and stub period, going forward.

# Arguments
- `start_date`: The start date of the schedule.
- `end_date`: The end date of the schedule.
- `stub_period::StubPeriod`: The stub period configuration.
- `period::P`: The period.

# Returns
- A stream of unadjusted dates.
"""
function generate_unadjusted_dates(start_date, end_date, ::StubPeriod{InArrearsStubPosition,ShortStubLength}, period::P) where {P<:Period}
    dates = start_date:period:(end_date-Day(1)) |> collect
    push!(dates, end_date)
    return dates
end

"""
	generate_unadjusted_dates(start_date, end_date, stub_period::StubPeriod, period::P) where P <: Period

Generates a stream of unadjusted dates according to the given period and stub period with a long stub, going forward.

# Arguments
- `start_date`: The start date of the schedule.
- `end_date`: The end date of the schedule.
- `stub_period::StubPeriod`: The stub period configuration.
- `period::P`: The period.

# Returns
- A stream of unadjusted dates.
"""
function generate_unadjusted_dates(start_date, end_date, ::StubPeriod{InArrearsStubPosition,LongStubLength}, period::P) where {P<:Period}
    dates = start_date:period:(end_date-period-Day(1)) |> collect
    push!(dates, end_date)
    return dates
end

"""
	generate_unadjusted_dates(start_date, end_date, stub_period::StubPeriod, period::P) where P <: Period

Generates a stream of unadjusted dates according to the given period and stub period, going backward.

# Arguments
- `start_date`: The start date of the schedule.
- `end_date`: The end date of the schedule.
- `stub_period::StubPeriod`: The stub period configuration.
- `period::P`: The period.

# Returns
- A stream of unadjusted dates.
"""
function generate_unadjusted_dates(start_date, end_date, ::StubPeriod{UpfrontStubPosition,ShortStubLength}, period::P) where {P<:Period}
    dates = end_date:-period:(start_date+Day(1)) |> collect
    push!(dates, start_date)
    return reverse(dates)
end

"""
	generate_unadjusted_dates(start_date, end_date, stub_period::StubPeriod, period::P) where P <: Period

Generates a stream of unadjusted dates according to the given period and stub period with a long stub, going backward.

# Arguments
- `start_date`: The start date of the schedule.
- `end_date`: The end date of the schedule.
- `stub_period::StubPeriod`: The stub period configuration.
- `period::P`: The period.

# Returns
- A stream of unadjusted dates.
"""
function generate_unadjusted_dates(start_date, end_date, ::StubPeriod{UpfrontStubPosition,LongStubLength}, period::P) where {P<:Period}
    dates = end_date:-period:(start_date+period+Day(1)) |> collect
    push!(dates, start_date) 
    return reverse(dates) 
end

"""
	generate_unadjusted_dates(start_date, end_date, schedule_config::ScheduleConfig)

Generates a stream of unadjusted dates according to the given schedule configuration.

# Arguments
- `start_date`: The start date of the schedule.
- `end_date`: The end date of the schedule.
- `schedule_config::ScheduleConfig`: The schedule configuration.

# Returns
- A stream of unadjusted dates.
"""
function generate_unadjusted_dates(start_date, end_date, schedule_config::ScheduleConfig)
    return generate_unadjusted_dates(start_date, end_date, schedule_config.stub_period, schedule_config.period)
end

"""
	date_corrector(schedule_config::ScheduleConfig)

Returns a function that adjusts a date according to the given schedule configuration, applying first adjustment conventions like EOM and then business day adjustment.

# Arguments
- `schedule_config::ScheduleConfig`: The schedule configuration.

# Returns
- A function that adjusts a date according to the given schedule configuration.
"""
function date_corrector(schedule_config::ScheduleConfig)
    return date -> adjust_date(roll_date(date, schedule_config.roll_convention), schedule_config.calendar, schedule_config.business_days_convention)
end

"""
	termination_date_corrector(schedule_config::ScheduleConfig)

Returns a function that adjusts a date according to the given schedule configuration, applying first adjustment conventions like EOM and then the termination date business day adjustment.

# Arguments
- `schedule_config::ScheduleConfig`: The schedule configuration.

# Returns
- A function that adjusts the termination date according to the given schedule configuration.
"""
function termination_date_corrector(schedule_config::ScheduleConfig)
    return date -> adjust_date(roll_date(date, schedule_config.roll_convention), schedule_config.calendar, schedule_config.termination_bd_convention)
end

"""
	generate_schedule(unadjusted_dates, schedule_config::S) where S <: AbstractScheduleConfig

Generates a schedule of adjusted dates according to the given schedule configuration.

# Arguments
- `unadjusted_dates`: A stream of unadjusted dates.
- `schedule_config::S`: The schedule configuration.

# Returns
- A schedule of adjusted dates.
"""
function generate_schedule(unadjusted_dates, schedule_config::S) where {S<:AbstractScheduleConfig}
    corrector = date_corrector(schedule_config)
    adjusted_dates = map(corrector, unadjusted_dates[1:end-1])
    adjusted_termination_date = termination_date_corrector(schedule_config)(unadjusted_dates[end])
    push!(adjusted_dates, adjusted_termination_date)
    return adjusted_dates
end

"""
	generate_schedule(start_date, end_date, schedule_config::S) where S <: AbstractScheduleConfig

Generates a schedule of adjusted dates according to the given schedule configuration.

# Arguments
- `start_date`: The start date of the schedule.
- `end_date`: The end date of the schedule.
- `schedule_config::S`: The schedule configuration.

# Returns
- A schedule of adjusted dates.
"""
function generate_schedule(start_date, end_date, schedule_config::S) where {S<:AbstractScheduleConfig}
    return generate_schedule(generate_unadjusted_dates(start_date, end_date, schedule_config), schedule_config)
end

"""
	generate_end_date(start_date::D, schedule_config::S) where {D<:TimeType, S<:AbstractScheduleConfig}

Generate the end date of a rate period given the schedule configuration and the start date.

# Arguments
- `start_date`: The start date of the schedule.
- `schedule_config::S`: The schedule configuration.

# Returns
- Shifted, adjusted, and rolled date.
"""
function generate_end_date(start_date, period::P, calendar::C, business_day_convention::B) where {P<:Period,B<:BusinessDayConvention,C<:HolidayCalendar}
    adjustor = t -> adjust_date(t, calendar, business_day_convention)
    return adjustor.(start_date .+ period)
end

"""
	generate_start_date(start_date::D, schedule_config::S) where {D<:TimeType, S<:AbstractScheduleConfig}

Generate the start date of a rate period given the schedule configuration and the end date.

# Arguments
- `end_date`: The end date of the schedule.
- `schedule_config::S`: The schedule configuration.

# Returns
- Shifted, adjusted, and rolled date.
"""
function generate_start_date(end_date, period::P, calendar::C, business_day_convention::B) where {P<:Period,B<:BusinessDayConvention,C<:HolidayCalendar}
    adjustor = t -> adjust_date(t, calendar, business_day_convention)
    return adjustor.(end_date .- period)
end