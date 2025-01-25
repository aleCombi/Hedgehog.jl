"""
    AbstractShift

An abstract type representing a shift in time applied to an accrual period. This serves as a base type
for different kinds of time shifts, such as `TimeShift` or `BusinessDayShift`.
"""
abstract type AbstractShift end

"""
    struct TimeShift{T<:Period}

Represents a shift in time by a specified period, applicable from either the start or end of an accrual period.

# Type Parameters
- `T<:Period`: The type of period to shift by (e.g., `Day`, `Month`, `Year`).

# Fields
- `shift::T`: The period over which the shift is applied.
- `from_end::Bool`: Indicates if the shift is applied from the end of the accrual period (`true`) or the start (`false`).
"""
struct TimeShift{T<:Period} <: AbstractShift
    shift::T
    from_end::Bool
end

"""
    TimeShift(period::P) where {P <: Period}

Creates a `TimeShift` with the specified period, with the default behavior of applying the shift from the end of each period.

# Arguments
- `period::P`: The period over which the shift is applied (e.g., `Day`, `Month`, `Year`).

# Returns
- A `TimeShift` object representing the shift with the specified period applied from the end by default.
"""
function TimeShift(period::P) where {P<:Period}
    return TimeShift(period, true)
end

"""
    struct NoShift

A type that represents no time shift, allowing selection of either the start or end date of an accrual period without adjustment.

# Fields
- `from_end::Bool`: Specifies if the end date (`true`) or start date (`false`) of each period is used.
"""
struct NoShift <: AbstractShift
    from_end::Bool
end

"""
    NoShift()

Creates a `NoShift` object with a default behavior to use the end date of each period.

# Returns
- An instance of `NoShift` using the end date by default.
"""
function NoShift()
    return NoShift(true)
end

"""
    struct BusinessDayShift{C <: HolidayCalendar}

A type representing a time shift by a specified number of business days, using a holiday calendar, 
from either the start or end of an accrual period.

# Type Parameters
- `C <: HolidayCalendar`: The holiday calendar type used to determine business days.

# Fields
- `shift::Int`: The number of business days to shift.
- `calendar::C`: The holiday calendar that defines business days.
- `from_end::Bool`: Indicates if the shift is applied from the end (`true`) or the start (`false`) of the accrual period.
"""
struct BusinessDayShift{C <: HolidayCalendar} <: AbstractShift
    shift::Int
    calendar::C
    from_end::Bool
end

"""
    shifted_schedule(schedule, shift_rule::NoShift)

Generates a schedule identical to the input schedule without any shift. Uses either the start or end date based on `shift_rule.from_end`.

# Arguments
- `schedule`: The original schedule of dates.
- `shift_rule`: A `NoShift` instance indicating if the start or end date should be used.

# Returns
- The unshifted schedule of dates.
"""
function shifted_schedule(schedule, ::NoShift)
    return schedule
end

"""
    shifted_schedule(schedule, shift_rule::TimeShift)

Applies a specified period shift to create a shifted schedule. The shift may apply from either the start or end date of each accrual period.

# Arguments
- `schedule`: The original schedule of dates.
- `shift_rule`: A `TimeShift` instance specifying the shift period and direction.

# Returns
- The shifted schedule of dates.
"""
function shifted_schedule(schedule, shift_rule::TimeShift)
    return schedule .+ shift_rule.shift
end

"""
    shifted_schedule(schedule, shift_rule::BusinessDayShift)

Shifts the input schedule by a specified number of business days according to a holiday calendar.

# Arguments
- `schedule`: The original schedule of dates.
- `shift_rule`: A `BusinessDayShift` instance specifying the number of business days to shift and the holiday calendar.

# Returns
- The business day-shifted schedule of dates.
"""
function shifted_schedule(schedule, shift_rule::BusinessDayShift)
    if shift_rule.shift == 0 #advancebdays would keep the same day even if it is a festivity
        return tobday.(shift_rule.calendar, schedule; forward=true)
    end
    return advancebdays.(shift_rule.calendar, schedule, shift_rule.shift)
end

"""
    shifted_trimmed_schedule(accrual_schedule, shift_rule::AbstractShift)

Creates a shifted schedule by adjusting each date in the accrual schedule and optionally trims the first or last date based on `shift_rule.from_end`.

# Arguments
- `accrual_schedule`: The original schedule of dates.
- `shift_rule`: An instance of `AbstractShift` (e.g., `BusinessDayShift`, `TimeShift`) defining the shift type and direction.

# Returns
- The shifted and trimmed schedule of dates.
"""
function shifted_trimmed_schedule(accrual_schedule, shift_rule::S) where S <: AbstractShift
    unshifted_schedule = shift_rule.from_end ? accrual_schedule[2:end] : accrual_schedule[1:end-1]
    return shifted_schedule(unshifted_schedule, shift_rule)
end
