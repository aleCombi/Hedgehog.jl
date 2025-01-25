"""
    abstract type RollConvention

An abstract type for defining various roll date conventions. Roll conventions are used to adjust dates to specific rules, 
such as end-of-month (EOM) or no adjustment. Specific implementations of this type define the behavior for each convention.
"""
abstract type RollConvention end

"""
    struct NoRollConvention <: RollConvention

A roll convention where no adjustment is made to the date. When this convention is applied, 
the date remains unchanged regardless of its day.
"""
struct NoRollConvention <: RollConvention end

"""
    struct EOMRollConvention <: RollConvention

An end-of-month (EOM) roll convention, which adjusts dates to the last day of the month. 
Useful in financial contexts where certain payments or rollovers are aligned with month-end dates.
"""
struct EOMRollConvention <: RollConvention end

"""
    roll_date(date, ::NoRollConvention) -> Date

Applies the `NoRollConvention` roll convention, meaning the input date remains unchanged.

# Arguments
- `date`: The date to be returned as is.
- `::NoRollConvention`: An instance of `NoRollConvention`, indicating no roll adjustment is needed.

# Returns
- The input `date` without any adjustment.
"""
function roll_date(date, ::NoRollConvention)
    return date
end

"""
    roll_date(date, ::EOMRollConvention) -> Date

Applies the `EOMRollConvention` roll convention, adjusting the date to the last day of its month.

# Arguments
- `date`: The date to be adjusted.
- `::EOMRollConvention`: An instance of `EOMRollConvention`, indicating end-of-month roll adjustment.

# Returns
- A date corresponding to the last day of the month in which `date` falls.
"""
function roll_date(date, ::EOMRollConvention)
    return lastdayofmonth(date)
end