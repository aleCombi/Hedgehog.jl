"""
    BusinessDayConvention

Abstract type representing a convention for adjusting dates to business days.
"""
abstract type BusinessDayConvention end

"""
    PrecedingBusinessDay <: BusinessDayConvention

Business day convention that adjusts a date to the previous business day.
"""
struct PrecedingBusinessDay <: BusinessDayConvention end

"""
    FollowingBusinessDay <: BusinessDayConvention

Business day convention that adjusts a date to the next business day.
"""
struct FollowingBusinessDay <: BusinessDayConvention end

"""
    ModifiedFollowing <: BusinessDayConvention

Business day convention that adjusts a date to the next business day, unless it falls in the next month, in which case it adjusts to the previous business day.
"""
struct ModifiedFollowing <: BusinessDayConvention end

"""
    NoneBusinessDayConvention <: BusinessDayConvention

Business day convention that does not adjust the date.
"""
struct NoneBusinessDayConvention <: BusinessDayConvention end

"""
    ModifiedPreceding <: BusinessDayConvention

Business day convention that adjusts a date to the previous business day, unless it falls in the previous month, in which case it adjusts to the next business day.
"""
struct ModifiedPreceding <: BusinessDayConvention end

"""
    adjust_date(date, calendar, ::PreviousBusinessDay) -> Date

Adjusts the given date to the previous business day according to the specified calendar.

# Arguments
- `date`: The date to be adjusted.
- `calendar`: The business days calendar to use for adjustment.
- `::PrecedingBusinessDay`: Preceding Business day convention.

# Returns
- The previous business day.
"""
function adjust_date(date, calendar, ::PrecedingBusinessDay)
    return tobday(calendar, date; forward=false)
end

"""
    adjust_date(date, calendar, ::FollowingBusinessDay) -> Date

Adjusts the given date to the next business day according to the specified calendar.

# Arguments
- `date`: The date to be adjusted.
- `calendar`: The business days calendar to use for adjustment.
- `::FollowingBusinessDay`: Following Business day convention.

# Returns
- The following business day.
"""
function adjust_date(date, calendar, ::FollowingBusinessDay)
    return tobday(calendar, date; forward=true)
end

"""
    adjust_date(date, calendar, ::NoneBusinessDayConvention) -> Date

Returns the given date without any adjustment.

# Arguments
- `date`: The date to be returned.
- `calendar`: The business days calendar (not used in this function).
- `NoneBusinessDayConvention`: None business day convention.

# Returns
- The original date.
"""
function adjust_date(date, calendar, ::NoneBusinessDayConvention)
    return date
end

"""
    adjust_date(date, calendar, ::ModifiedFollowing) -> Date

Adjusts the given date to the next business day according to the specified calendar, unless it falls in the next month, in which case it adjusts to the previous business day.

# Arguments
- `date`: The date to be adjusted.
- `calendar`: The business days calendar to use for adjustment.
- `::ModifiedFollowing`: Modified Following business day convention.

# Returns
- The adjusted date.
"""
function adjust_date(date, calendar, ::ModifiedFollowing)
    next_business_day = tobday(calendar, date; forward=true)
    if month(next_business_day) != month(date)
        return tobday(calendar, date; forward=false)
    else
        return next_business_day
    end
end

"""
    adjust_date(date, calendar, ::ModifiedPreceding) -> Date

Adjusts the given date to the previous business day according to the specified calendar, unless it falls in the previous month, in which case it adjusts to the following business day.

# Arguments
- `date`: The date to be adjusted.
- `calendar`: The business days calendar to use for adjustment.
- `::ModifiedPreceding`: Modified Preceding business day convention.

# Returns
- The adjusted date as a `Date`.
"""
function adjust_date(date, calendar, ::ModifiedPreceding)
    previous_business_day = tobday(calendar, date; forward=false)
    if month(previous_business_day) != month(date)
        return tobday(calendar, date; forward=true)
    else
        return previous_business_day
    end
end