"""
    RateType

Abstract type representing a rate type. This serves as the base type for all specific interest rate types such as linear (simple) interest and compound interest.
"""
abstract type RateType end

"""
    LinearRate <: RateType

Concrete type representing linear (simple) interest, where the interest is calculated as a fixed percentage of the principal over time.
"""
struct LinearRate <: RateType end

"""
    Compounded <: RateType

Concrete type representing compound interest, where interest is calculated and added to the principal after each period, and the interest is calculated on the new balance.

# Fields
- `frequency::Int`: The number of compounding periods per year (e.g., 12 for monthly compounding).
"""
struct Compounded <: RateType
    frequency::Int
end

"""
    Exponential <: RateType

Concrete type representing exponential interest, where the interest is calculated as the principal multiplied by the exponential of the interest rate times the time fraction.
"""
struct Exponential <: RateType end

"""
    compounding_factor(rate, time_fraction, ::LinearRate)

Calculates the compounding factor for linear (simple) interest.

# Arguments
- `rate`: Interest rate as a decimal (e.g., 0.05 for 5%).
- `time_fraction`: The time fraction over which interest is calculated (e.g., 1 for one year).

# Returns
- The compounding factor based on the linear interest formula.
"""
function compounding_factor(rate, time_fraction, ::LinearRate)
    return 1 .+ rate .* time_fraction
end

"""
    implied_rate(accrual_ratio, time_fraction, ::LinearRate)

Calculates the implied interest rate for linear (simple) interest given an accrual ratio.

# Arguments
- `accrual_ratio`: The ratio of the final to the initial principal (e.g., 1.05 for a 5% increase).
- `time_fraction`: The time fraction over which the rate is applied (e.g., 1 for one year).

# Returns
- The implied rate as a decimal, derived based on simple interest.
"""
function implied_rate(accrual_ratio, time_fraction, ::LinearRate)
    return (accrual_ratio .- 1) ./ time_fraction
end

"""
    compounding_factor(rate, time_fraction, rate_type::Compounded)

Calculates the compounding factor for compound interest based on compounding periods per year.

# Arguments
- `rate`: Interest rate as a decimal.
- `time_fraction`: The time fraction over which interest is calculated.
- `rate_type::Compounded`: An instance of `Compounded`, which includes the frequency of compounding.

# Returns
- The compounding factor calculated using compound interest.
"""
function compounding_factor(rate, time_fraction, rate_type::Compounded)
    return (1 .+ rate ./ rate_type.frequency) .^ (rate_type.frequency .* time_fraction)
end

"""
    implied_rate(accrual_ratio, time_fraction, rate_type::Compounded)

Calculates the implied interest rate for compound interest given an accrual ratio and compounding frequency.

# Arguments
- `accrual_ratio`: The ratio of the final to the initial principal.
- `time_fraction`: The time fraction over which the rate is applied.
- `rate_type::Compounded`: An instance of `Compounded`, which specifies the compounding frequency.

# Returns
- The implied rate as a decimal, adjusted for the compounding frequency.
"""
function implied_rate(accrual_ratio, time_fraction, rate_type::Compounded)
    return (accrual_ratio .^ (1 ./ rate_type.frequency ./ time_fraction) .- 1) * rate_type.frequency
end

"""
    compounding_factor(rate, time_fraction, ::Exponential)

Calculates the compounding factor for exponential interest.

# Arguments
- `rate`: Interest rate as a decimal.
- `time_fraction`: The time fraction over which interest is calculated.

# Returns
- The compounding factor based on the exponential interest formula.
"""
function compounding_factor(rate, time_fraction, ::Exponential)
    return exp.(rate .* time_fraction)
end

"""
    implied_rate(accrual_ratio, time_fraction, ::Exponential)

Calculates the implied interest rate for exponential interest given an accrual ratio.

# Arguments
- `accrual_ratio`: The ratio of the final to the initial principal.
- `time_fraction`: The time fraction over which the rate is applied.

# Returns
- The implied rate as a decimal based on continuous compounding.
"""
function implied_rate(accrual_ratio, time_fraction, ::Exponential)
    return log.(accrual_ratio) ./ time_fraction
end

"""
    discount_interest(rate, time_fraction, rate_type::R) where {R<:RateType}

Calculates the discount factor for a given interest rate type, which represents the present value of a future cash flow.

# Arguments
- `rate`: Interest rate as a decimal.
- `time_fraction`: The time fraction over which interest is discounted.
- `rate_type::R`: A rate type that inherits from `RateType` (e.g., `LinearRate`, `Compounded`, or `Exponential`).

# Returns
- The discount factor as the inverse of the compounding factor for the specified rate type.
"""
function discount_interest(rate, time_fraction, rate_type::R) where {R<:RateType}
    return 1 ./ compounding_factor(rate, time_fraction, rate_type)
end

"""
    calculate_interest(principal, rate, time_fraction, rate_type::R) where {R<:RateType}

Calculates the interest accrued over a period for a specified interest rate type.

# Arguments
- `principal`: Initial amount on which interest is calculated.
- `rate`: Interest rate as a decimal.
- `time_fraction`: The time fraction over which interest is calculated.
- `rate_type::R`: A rate type that inherits from `RateType` (e.g., `LinearRate`, `Compounded`, or `Exponential`).

# Returns
- The interest amount calculated based on the principal, rate, time, and rate type.
"""
function calculate_interest(principal, rate, time_fraction, rate_type::R) where {R<:RateType}
    return principal .* (compounding_factor(rate, time_fraction, rate_type) .- 1)
end

"""
    calculate_interest(principal, rate, time_fraction, ::LinearRate)

Calculates the interest accrued over a period for linear (simple) interest.

# Arguments
- `principal`: Initial amount on which interest is calculated.
- `rate`: Interest rate as a decimal.
- `time_fraction`: The time fraction over which interest is calculated.

# Returns
- The interest amount calculated based on simple interest.
"""
function calculate_interest(principal, rate, time_fraction, ::LinearRate)
    return principal .* rate .* time_fraction
end
