"""
    MarginConfig

An abstract type representing the configuration for margin. Concrete types for margin configurations, 
such as `AdditiveMargin` and `MultiplicativeMargin`, should subtype this.
"""
abstract type MarginConfig end

"""
    AdditiveMargin{N<:Number}

A concrete type representing an additive margin, where a fixed amount is added to the base rate.

# Fields
- `margin::N`: The margin value to be added, of type `N` (typically a `Float64` or `Int`).
"""
struct AdditiveMargin{N<:Number} <: MarginConfig
    margin::N
end

"""
    AdditiveMargin()

Constructs an `AdditiveMargin` with a default margin of `0`.

# Returns
An instance of `AdditiveMargin` initialized with a default value of `0`, representing a zero margin or spread.
"""
function AdditiveMargin()
    return AdditiveMargin(0)
end

"""
    MultiplicativeMargin{N<:Number}

A concrete type representing a multiplicative margin, where the base rate is multiplied by a factor.

# Fields
- `margin::N`: The margin value used as a multiplier, of type `N` (typically a `Float64` or `Int`).
"""
struct MultiplicativeMargin{N<:Number} <: MarginConfig
    margin::N
end

"""
    CompoundMargin

An abstract type representing a margin configuration for compounded rates. 
Concrete types like `MarginOnUnderlying` and `MarginOnCompoundedRate` should subtype this.
"""
abstract type CompoundMargin end

"""
    MarginOnUnderlying{M<:MarginConfig} <: CompoundMargin

A concrete type representing a margin applied on the underlying rate (before compounding), 
parameterized by the margin configuration `M`.

# Fields
- `marginConfig::M`: The margin configuration applied to the underlying rate, 
  typically of type `AdditiveMargin` or `MultiplicativeMargin`.
"""
struct MarginOnUnderlying{M<:MarginConfig} <: CompoundMargin
    margin_config::M
end

"""
    MarginOnCompoundedRate{M<:MarginConfig} <: CompoundMargin

A concrete type representing a margin applied on the compounded rate (after compounding), 
parameterized by the margin configuration `M`.

# Fields
- `marginConfig::M`: The margin configuration applied to the compounded rate, 
  typically of type `AdditiveMargin` or `MultiplicativeMargin`.
"""
struct MarginOnCompoundedRate{M<:MarginConfig} <: CompoundMargin
    margin_config::M
end

"""
    apply_margin(rate, margin::AdditiveMargin)

Applies an additive margin to a given rate. This function takes a base rate and 
adds a specified additive margin to it.

# Arguments
- `rate`: The base rate to which the margin will be applied.
- `margin::AdditiveMargin`: An instance of `AdditiveMargin` containing the margin value to add.

# Returns
- The rate after applying the additive margin (i.e., `rate + margin.margin`).
"""
function apply_margin(rate, margin::AdditiveMargin)
    return rate .+ margin.margin
end

"""
    apply_margin(rate, margin::MultiplicativeMargin)

Applies a multiplicative margin to a given rate. This function takes a base rate 
and multiplies it by `(1 + margin)`.

# Arguments
- `rate`: The base rate to which the margin will be applied.
- `margin::MultiplicativeMargin`: An instance of `MultiplicativeMargin` containing the margin value to multiply by.

# Returns
- The rate after applying the multiplicative margin (i.e., `rate * (1 + margin.margin)`).
"""
function apply_margin(rate, margin::MultiplicativeMargin)
    return rate .* (1 .+ margin.margin)
end

"""
    margined_rate(accrual_ratio, time_fraction, rate_type::R, margin::M) where {R<:RateType, M<:MarginConfig}

Calculates a margined rate based on the given accrual ratio, time fraction, rate type, and margin configuration.

# Arguments
- `accrual_ratio`: A numeric value representing the ratio of accrual over a period, typically related to interest or financial growth.
- `time_fraction`: A numeric value representing the fraction of time over which the rate applies (e.g., a fraction of a year).
- `rate_type::R`: The rate type, a subtype of `RateType`, specifying how the interest or growth rate is calculated.
- `margin::M`: The margin configuration, a subtype of `MarginConfig`, defining any adjustments or margins applied to the calculated rate.

# Returns
- A numeric value representing the margined rate, calculated by determining the implied rate based on the accrual ratio and time fraction, and then applying the specified margin.

# Details
The function first calculates an implied rate using the `implied_rate` function, based on the accrual ratio and time fraction parameters and the specified rate type. It then adjusts this rate by applying the margin using the `apply_margin` function and returns the margined rate.

"""
function margined_rate(accrual_ratio, time_fraction, rate_type::R, margin::M) where {R<:RateType, M<:MarginConfig}
    rate = implied_rate(accrual_ratio, time_fraction, rate_type)
    return apply_margin(rate, margin)
end