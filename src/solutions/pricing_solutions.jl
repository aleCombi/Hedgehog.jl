"""
    AbstractPricingSolution

Abstract base type for all financial instrument pricing solutions.

Subtypes should encapsulate the results of a specific pricing method applied
to a defined pricing problem.
"""
abstract type AbstractPricingSolution end

"""
    MonteCarloSolution{T<:Number, S, P<:PricingProblem, M <: AbstractPricingMethod} <: AbstractPricingSolution

Represents a pricing solution obtained using a Monte Carlo simulation method.

# Fields
- `problem::P`: The pricing problem definition (`<: PricingProblem`).
- `method::M`: The specific Monte Carlo method used (`<: AbstractPricingMethod`).
- `price::T`: The calculated numerical price (`<: Number`).
- `ensemble::S`: The results of the Monte Carlo simulation (e.g., simulated paths or final values). The type `S` depends on the specific ensemble data stored.
"""
struct MonteCarloSolution{T<:Number, S, P<:PricingProblem, M <: AbstractPricingMethod} <: AbstractPricingSolution
    problem::P
    method::M
    price::T
    ensemble::S
end

"""
    AnalyticSolution{T <: Number, P<:PricingProblem, M <: AbstractPricingMethod} <: AbstractPricingSolution

Represents a pricing solution obtained using an analytical (closed-form) formula.

# Fields
- `problem::P`: The pricing problem definition (`<: PricingProblem`).
- `method::M`: The specific analytical method used (`<: AbstractPricingMethod`).
- `price::T`: The calculated numerical price (`<: Number`).
"""
struct AnalyticSolution{T <: Number, P<:PricingProblem, M <: AbstractPricingMethod} <: AbstractPricingSolution
    problem::P
    method::M
    price::T
end

"""
    CarrMadanSolution{T <: Number, P<:PricingProblem, M <: AbstractPricingMethod} <: AbstractPricingSolution

Represents a pricing solution obtained using the Carr-Madan FFT-based method.

This method typically involves Fourier transforms and numerical integration for pricing options.

# Fields
- `problem::P`: The pricing problem definition (`<: PricingProblem`).
- `method::M`: The specific Carr-Madan method configuration (`<: AbstractPricingMethod`).
- `price::T`: The calculated numerical price (`<: Number`).
- `integral_solution::SciMLBase.IntegralSolution`: The solution object resulting from the numerical integration step (often FFT-based) involved in the Carr-Madan approach.
"""
struct CarrMadanSolution{T <: Number, P<:PricingProblem, M <: AbstractPricingMethod} <: AbstractPricingSolution
    problem::P
    method::M
    price::T
    integral_solution::SciMLBase.IntegralSolution
end

"""
    LSMSolution{T <: Number,S,TEl, P<:PricingProblem, M <: AbstractPricingMethod} <: AbstractPricingSolution

Represents a pricing solution obtained using the Longstaff-Schwartz Method (LSM),
typically applied to American-style options via Monte Carlo simulation.

# Fields
- `problem::P`: The pricing problem definition (`<: PricingProblem`), usually involving early exercise features.
- `method::M`: The specific LSM configuration (`<: AbstractPricingMethod`).
- `price::T`: The calculated numerical price (`<: Number`).
- `stopping_info::Vector{Tuple{Int,S}}`: Information related to the derived optimal stopping (exercise) rule at different time steps. Often contains time indices and associated data `S` (e.g., regression coefficients, exercise boundaries).
- `spot_paths::Matrix{TEl}`: The matrix of simulated underlying asset price paths used in the LSM algorithm. `TEl` is the element type of the path values.
"""
struct LSMSolution{T <: Number,S,TEl, P<:PricingProblem, M <: AbstractPricingMethod} <: AbstractPricingSolution
    problem::P
    method::M
    price::T
    stopping_info::Vector{Tuple{Int,S}}
    spot_paths::Matrix{TEl}
end

"""
    CRRSolution{T <: Number, P<:PricingProblem, M <: AbstractPricingMethod} <: AbstractPricingSolution

Represents a pricing solution obtained using the Cox-Ross-Rubinstein (CRR)
binomial tree model.

# Fields
- `problem::P`: The pricing problem definition (`<: PricingProblem`).
- `method::M`: The specific CRR method configuration (`<: AbstractPricingMethod`).
- `price::T`: The calculated numerical price (`<: Number`).
"""
struct CRRSolution{T <: Number, P<:PricingProblem, M <: AbstractPricingMethod} <: AbstractPricingSolution
    problem::P
    method::M
    price::T
end

"""
    COSSolution{T <: Number, P<:PricingProblem, M <: AbstractPricingMethod} <: AbstractPricingSolution

Represents a pricing solution obtained using the COS (Fourier-cosine expansion) method.

# Fields
- `problem::P`: The pricing problem definition (`<: PricingProblem`).
- `method::M`: The specific COS method configuration (`<: AbstractPricingMethod`).
- `price::T`: The calculated numerical price (`<: Number`).
"""
struct COSSolution{T <: Number, P<:PricingProblem, M <: AbstractPricingMethod} <: AbstractPricingSolution
    problem::P
    method::M
    price::T
end