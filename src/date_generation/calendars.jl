"""
    NoHolidays <: HolidayCalendar

A struct representing a holiday calendar with no holidays. All dates are treated as business days.
"""
struct NoHolidays <: HolidayCalendar end

"""
    isholiday(::NoHolidays, dt::Date) -> Bool

Determines if the given date `dt` is a holiday in the `NoHolidays` calendar. 
Always returns `false` as there are no holidays in this calendar.

# Arguments
- `dt::Date`: The date to check.

# Returns
- `false`, indicating that the date is not a holiday.
"""
BusinessDays.isholiday(::NoHolidays, dt::Date) = false

"""
    WeekendsOnly <: HolidayCalendar

A struct representing a holiday calendar where only weekends (Saturday and Sunday) are considered holidays.
"""
struct WeekendsOnly <: HolidayCalendar end

"""
    isholiday(::WeekendsOnly, dt::Date) -> Bool

Determines if the given date `dt` is a weekend (Saturday or Sunday) in the `WeekendsOnly` calendar.

# Arguments
- `dt::Date`: The date to check.

# Returns
- `true` if the date falls on a weekend, otherwise `false`.
"""
BusinessDays.isholiday(::WeekendsOnly, dt::Date) = dayofweek(dt) in [6, 7]