"""
    AbstractRateConfig

An abstract type that serves as the base type for different rate configurations.
Any concrete rate configuration (e.g., `FixedRateConfig`) should subtype this.
"""
abstract type AbstractRateConfig end

"""
    FixedRateConfig{D<:DayCount, R<:RateType} <: AbstractRateConfig

A concrete type representing a fixed rate configuration, parameterized by the day count convention `D` 
and the rate convention `R`.

# Fields
- `day_count_convention::D`: The day count convention used to calculate time fractions (e.g., 30/360, Actual/360).
- `rate_convention::R`: The rate convention, which defines whether rates are linear, continuously compounded, etc.
"""
struct FixedRateConfig{D<:DayCount, R<:RateType} <: AbstractRateConfig
    day_count_convention::D
    rate_convention::R
end

"""
    AbstractInstrumentRate

An abstract type that serves as the base type for different instrument rates.
Any concrete instrument rate (e.g., `FixedRate`) should subtype this.
"""
abstract type AbstractInstrumentRate end

"""
    FixedRate{V<:Number, R<:AbstractRateConfig} <: AbstractInstrumentRate

A concrete type representing a fixed rate instrument, parameterized by the rate value `V` 
and the rate configuration `R`.

# Fields
- `rate::V`: The fixed interest rate applied to the instrument.
- `rate_config::R`: The rate configuration, which includes details such as the day count convention and rate convention.
"""
struct FixedRate{V<:Number, R<:AbstractRateConfig} <: AbstractInstrumentRate
    rate::V
    rate_config::R
end
