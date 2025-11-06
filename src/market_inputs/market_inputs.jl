"""
    AbstractMarketInputs

An abstract type representing market data inputs required for pricers.
"""
abstract type AbstractMarketInputs end

"""
    BlackScholesInputs <: AbstractMarketInputs

Market data inputs for the Black-Scholes model.

# Fields
- `referenceDate`: The date from which maturity is measured.
- `rate`: The risk-free interest rate (annualized).
- `spot`: The current spot price of the underlying asset.
- `sigma`: The volatility of the underlying asset (annualized).

This struct encapsulates the necessary inputs for pricing derivatives under the Black-Scholes model.
"""
struct BlackScholesInputs{R <: AbstractRateCurve, TSpot <: Real, TSigma <: AbstractVolSurface} <: AbstractMarketInputs
    referenceDate::Int64
    rate::R
    spot::TSpot
    sigma::TSigma
end

BlackScholesInputs(reference_date::Union{Int64,TimeType}, rate::AbstractRateCurve, spot, sigma::Real) =
    BlackScholesInputs(to_ticks(reference_date), rate, spot, FlatVolSurface(sigma; reference_date=to_ticks(reference_date)))

BlackScholesInputs(reference_date::Union{Int64,TimeType}, rate::Real, spot, sigma) = BlackScholesInputs(
    to_ticks(reference_date),
    FlatRateCurve(to_ticks(reference_date), rate),
    spot,
    sigma,
)

"""
    HestonInputs <: AbstractMarketInputs

Market data inputs for the Heston stochastic volatility model.

# Fields
- `referenceDate`: The base date for maturity calculation (in ticks).
- `rate`: The risk-free interest rate (annualized).
- `spot`: The current spot price of the underlying.
- `V0`: The initial variance of the underlying.
- `κ`: The rate at which variance reverts to its long-term mean.
- `θ`: The long-term mean of the variance.
- `σ`: The volatility of variance (vol-of-vol).
- `ρ`: The correlation between the asset and variance processes.

Used for pricing under the Heston model and simulation of stochastic volatility paths.
"""
struct HestonInputs{
    C <: AbstractRateCurve,
    Tref <: Number,
    Tspot <: Number,
    TV0 <: Number,
    Tκ <: Number,
    Tθ <: Number,
    Tσ <: Number,
    Tρ <: Number
} <: AbstractMarketInputs
    referenceDate::Tref
    rate::C
    spot::Tspot
    V0::TV0
    κ::Tκ
    θ::Tθ
    σ::Tσ
    ρ::Tρ
end


HestonInputs(reference_date::TimeType, rate::C, spot, V0, κ, θ, σ, ρ) where C <: AbstractRateCurve =
    HestonInputs(to_ticks(reference_date), rate, spot, V0, κ, θ, σ, ρ)

HestonInputs(reference_date::TimeType, rate::Real, spot, V0, κ, θ, σ, ρ) = HestonInputs(
    reference_date,
    FlatRateCurve(rate; reference_date = reference_date),
    spot,
    V0,
    κ,
    θ,
    σ,
    ρ,
)
