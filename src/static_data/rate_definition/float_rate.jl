abstract type ObservationPeriod end
struct ForwardLooking <: ObservationPeriod end
struct BackwardLooking <: ObservationPeriod end

abstract type CompoundingStyle end
struct CompoundedRate <: CompoundingStyle end
struct AverageRate <: CompoundingStyle end

"""
    AbstractRateIndex

An abstract type representing a rate index. This type serves as a base for defining the rate index 
in a floating-rate stream, encapsulating the general concept of a rate index.
"""
abstract type AbstractRateIndex end

"""
    RateIndex

A structure representing a rate index. This object typically maps to data sources for different rate indices.

# Fields
- `name::String`: The name of the rate index (e.g., LIBOR, EURIBOR, SOFR).
"""
struct RateIndex{O<:ObservationPeriod, P <: Period, B <: BusinessDayConvention, C<:HolidayCalendar, R<:RateType, D<:DayCount} <: AbstractRateIndex
    name::String
    observation_period::O
    tenor::P
    calendar::C
    business_day_convention::B
    rate_type::R
    day_count_convention::D
end

function RateIndex(name)
    return RateIndex(name, ForwardLooking(), Day(1), NoHolidays(), NoneBusinessDayConvention(), LinearRate(), ACT360())
end

function generate_start_date(end_date, rate_index::RateIndex)
    return generate_start_date(end_date, rate_index.tenor, rate_index.calendar, rate_index.business_day_convention)
end

function generate_end_date(start_date, rate_index::RateIndex)
    return generate_end_date(start_date, rate_index.tenor, rate_index.calendar, rate_index.business_day_convention)
end

"""
    FloatRateConfig <: AbstractRateConfig

An abstract type representing the configuration for floating rates. Subtypes of this define specific configurations 
for floating-rate instruments (e.g., `SimpleRateConfig`, `CompoundRateConfig`).
"""
abstract type FloatRateConfig <: AbstractRateConfig end

"""
    SimpleRateConfig{D<:DayCount, L<:RateType, C<:AbstractShift, N<:MarginConfig} <: FloatRateConfig

A concrete configuration for simple floating rates, parameterized by a day count convention `D`, 
a rate type `L`, a shift `C` for rate fixing, and a margin configuration `N`.

# Fields
- `day_count_convention::D`: The day count convention used to calculate time fractions (e.g., Actual/360).
- `rate_type::L`: The type of floating rate (e.g., overnight rates, term rates).
- `fixing_shift::C`: A fixing shift to adjust for market conventions (e.g., a 2-day shift).
- `margin::N`: The margin or spread added to the floating rate.
"""
struct SimpleRateConfig{D<:DayCount, L<:RateType, C<:AbstractShift, N<:MarginConfig} <: FloatRateConfig
    day_count_convention::D
    rate_type::L
    fixing_shift::C
    margin::N
end

"""
    SimpleRateConfig(day_count_convention::D, rate_type::L) where {D<:DayCount, L<:RateType}

Constructs a `SimpleRateConfig` with default values for `fixing_shift` (set to `NoShift()`) and `margin` 
(set to `AdditiveMargin()`) given the specified day count convention and rate type.

# Arguments
- `day_count_convention::D`: The day count convention for calculating time fractions (e.g., Actual/360).
- `rate_type::L`: The floating rate type.
"""
function SimpleRateConfig(day_count_convention::D, rate_type::L) where {D<:DayCount, L<:RateType}
    return SimpleRateConfig(day_count_convention, rate_type, NoShift(), AdditiveMargin())
end

"""
    CompoundRateConfig{D<:DayCount, L<:RateType, C<:AbstractShift, S<:AbstractScheduleConfig, M<:CompoundMargin} <: FloatRateConfig

A concrete configuration for compounded floating rates, parameterized by a day count convention `D`, 
a rate type `L`, a fixing shift `C`, a compounding schedule `S`, and a margin configuration `M`.

# Fields
- `day_count_convention::D`: The day count convention for calculating time fractions (e.g., Actual/360).
- `rate_type::L`: Specifies the rate type, indicating that rates are compounded.
- `fixing_shift::C`: A fixing shift for rate determination adjustments, based on market practices.
- `compound_schedule::S`: A schedule configuration defining the intervals for compounding.
- `margin::M`: The margin or spread added over the compounded floating rate.
"""
struct CompoundRateConfig{D<:DayCount, L<:RateType, C<:AbstractShift, S<:AbstractScheduleConfig, M<:CompoundMargin, CS<:CompoundingStyle} <: FloatRateConfig
    day_count_convention::D
    rate_type::L
    fixing_shift::C
    compound_schedule::S
    margin::M
    compounding_style::CS
end

"""
    CompoundRateConfig(day_count_convention::D, rate_type::L, compound_schedule::S; 
                       fixing_shift::C=NoShift(), 
                       margin::M=AdditiveMargin(0))

Creates a `CompoundRateConfig` object that defines the configuration for calculating compounded rates over multiple periods, including day count conventions, rate type, and margin adjustments.

# Arguments
- `day_count_convention::D`: Specifies the day count convention to calculate time fractions (e.g., 30/360, ACT/365).
- `rate_type::L`: The type of rate used in calculations (e.g., compounded or simple).
- `compound_schedule::S`: The schedule that defines compounding intervals for rate calculations.
- `fixing_shift::C`: Optional fixing shift to apply to dates in the schedule, typically for adjusting rate fixing dates. Defaults to `NoShift()`.
- `margin::M`: Optional margin configuration applied to adjust the final compounded rate. Defaults to `AdditiveMargin(0)`.

# Returns
- A `CompoundRateConfig` object initialized with the provided configurations for compounded rate calculations.
"""
function CompoundRateConfig(day_count_convention::D, rate_type::L, compound_schedule::S;
    fixing_shift::C=NoShift(false),
    margin::M=AdditiveMargin(0),
    compounding_style=CompoundedRate()) where {D<:DayCount, L<:RateType, C<:AbstractShift, S<:AbstractScheduleConfig, M<:CompoundMargin}
    return CompoundRateConfig(day_count_convention, rate_type, fixing_shift, compound_schedule, margin, compounding_style)
end

"""
    SimpleInstrumentRate

A structure representing a simple floating-rate instrument, defined by a rate index and a simple rate configuration.

# Fields
- `rate_index::RateIndex`: The rate index associated with this instrument (e.g., LIBOR).
- `rate_config::SimpleRateConfig`: The configuration parameters for calculating the simple floating rate.
"""
struct SimpleInstrumentRate <: AbstractInstrumentRate
    rate_index::RateIndex
    rate_config::SimpleRateConfig
end

"""
    CompoundInstrumentRate

A structure representing a compounded floating-rate instrument, defined by a rate index and a compounded rate configuration.

# Fields
- `rate_index::RateIndex`: The rate index associated with this instrument (e.g., SOFR).
- `rate_config::CompoundRateConfig`: The configuration parameters for calculating the compounded floating rate.
"""
struct CompoundInstrumentRate <: AbstractInstrumentRate
    rate_index::RateIndex
    rate_config::CompoundRateConfig
end