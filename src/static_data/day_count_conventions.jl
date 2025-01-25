"""
    DayCount

Abstract type representing a day count convention. 
Concrete day count conventions should derive from this type.
"""
abstract type DayCount end

"""
    ACT360 <: DayCount

Concrete type representing the ACT/360 day count convention, where the actual number of days between two dates is divided by 360.
"""
struct ACT360 <: DayCount end

"""
    day_count_fraction(start_dates, end_dates, ::ACT360)

Calculate the day count fraction between two dates using the ACT/360 convention.

# Arguments
- `start_dates`: An array of start dates.
- `end_dates`: An array of end dates corresponding to each start date.
- `::ACT360`: Specifies the day count convention (ACT/360) for calculating the fraction.

# Returns
An array of day count fractions, each representing the fraction of a year between a start 
and end date based on the ACT/360 convention, where the actual days between dates are divided by 360.
"""
function day_count_fraction(start_dates, end_dates, ::ACT360)
    return Dates.value.(end_dates .- start_dates) ./ 360
end

"""
    day_count_fraction(dates, ::ACT360)

Calculate the day count fraction between consecutive dates in an array using the ACT/360 convention.

# Arguments
- `dates`: An array of dates.
- `::ACT360`: Specifies the day count convention (ACT/360) for calculating the fraction.

# Returns
An array of day count fractions, each representing the fraction of a year between each pair 
of consecutive dates in `dates`, calculated by dividing the actual days between dates by 360.
"""
function day_count_fraction(dates, ::ACT360)
    return Dates.value.(diff(dates)) ./ 360
end

"""
    ACT365 <: DayCount

Concrete type representing the ACT/365 day count convention, where the actual number of days between two dates is divided by 365.
"""
struct ACT365 <: DayCount end

"""
    day_count_fraction(start_date, end_date, ::ACT365)

Calculate the day count fraction between two dates using the ACT/365 convention.

# Arguments
- `start_date`: The start date.
- `end_date`: The end date.
- `::ACT365`: Specifies the day count convention (ACT/365) for calculating the fraction.

# Returns
The day count fraction representing the fraction of a year between `start_date` and `end_date`, calculated by dividing the actual days between dates by 365.
"""
function day_count_fraction(start_date, end_date, ::ACT365)
    return Dates.value.(end_date .- start_date) ./ 365
end

"""
    day_count_fraction(dates, ::ACT365)

Calculate the day count fraction between consecutive dates in an array using the ACT/365 convention.

# Arguments
- `dates`: An array of dates.
- `::ACT365`: Specifies the day count convention (ACT/365) for calculating the fraction.

# Returns
An array of day count fractions, each representing the fraction of a year between each pair 
of consecutive dates in `dates`, calculated by dividing the actual days between dates by 365.
"""
function day_count_fraction(dates, ::ACT365)
    return Dates.value.(diff(dates)) ./ 365
end

"""
    Thirty360 <: DayCount

Concrete type representing the 30/360 day count convention, where the number of days between two dates is calculated as the difference in days, months, and years, and then divided by 360.

The day count is calculated as follows:
- The number of days is the difference in days between the two dates.
- The number of months is the difference in months between the two dates.
- The number of years is the difference in years between the two dates.
- The day count is then calculated as `(years * 360 + months * 30 + days) / 360`.

European convention: starting dates or ending dates that occur on the 31st of a month become equal to the 30th of the same month. Also known as "30E/360", or "Eurobond Basis".
"""
struct Thirty360 <: DayCount end

"""
    day_count_fraction(start_date::Date, end_date::Date, ::Thirty360)

Calculates the day count fraction between two dates according to the 30/360 convention. The day count is calculated as the difference in days, months, and years between the two dates, divided by 360.

# Arguments
- `start_date`: The start date.
- `end_date`: The end date.
- `::Thirty360`: The 30/360 convention type.

# Returns
- The day count fraction calculated according to the 30/360 convention.
"""
function day_count_fraction(start_date, end_date, ::Thirty360) 
    year_diff = Dates.year.(end_date) .- Dates.year.(start_date)
    month_diff = Dates.month.(end_date) .- Dates.month.(start_date)
    adjusted_end_day = min.(Dates.day.(end_date), 30)
    adjusted_start_day = min.(Dates.day.(start_date), 30)
    day_diff = adjusted_end_day .- adjusted_start_day
    return (year_diff .* 360 .+ month_diff .* 30 .+ day_diff) ./ 360
end

"""
    day_count_fraction(dates, ::Thirty360)

Calculates the day count fractions between consecutive dates in a vector according to the 30/360 convention.

# Arguments
- `dates`: A vector of dates.
- `::Thirty360`: The 30/360 convention type.

# Returns
- A vector of day count fractions for each consecutive pair of dates, calculated according to the 30/360 convention.
"""
function day_count_fraction(dates, ::Thirty360)
    return [day_count_fraction(dates[i], dates[i+1], Thirty360()) for i in 1:length(dates)-1]
end