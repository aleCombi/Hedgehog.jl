using Dates

# --- Core nouns ---
abstract type PayoffFunction end
abstract type Control end
abstract type Underlying end

struct Derivative{U<:Underlying,P<:PayoffFunction,C<:Control}
    underlying::U
    payoff::P
    control::C
end

# --- Underlying ---
struct Equity <: Underlying
    symbol::Symbol
end

# --- Payoff ---
struct CallPayoff{R<:Real} <: PayoffFunction
    K::R
end

# --- Exercise controls (special cases of Control) ---
"European: exercise only at maturity."
struct EuropeanExercise{T<:TimeType} <: Control
    maturity::T
end

"Bermudan: exercise only on specified dates."
struct BermudanExercise{T<:TimeType} <: Control
    dates::Vector{T}
end

"American: exercise at any time in [start, maturity]."
struct AmericanExercise{T<:TimeType} <: Control
    start::T
    maturity::T
end

# --- Type aliases for common combos ---
const EuropeanCall{U<:Underlying,R<:Real,T<:TimeType} =
    Derivative{U,CallPayoff{R},EuropeanExercise{T}}

const BermudanCall{U<:Underlying,R<:Real,T<:TimeType} =
    Derivative{U,CallPayoff{R},BermudanExercise{T}}

const AmericanCall{U<:Underlying,R<:Real,T<:TimeType} =
    Derivative{U,CallPayoff{R},AmericanExercise{T}}


# --- Optional type aliases for common combos ---
const EuropeanCall{U<:Underlying,R<:Real,Tt<:TimeType} = Derivative{U,CallPayoff{R},European{Tt}}
const BermudanCall{U<:Underlying,R<:Real,Tt<:TimeType} = Derivative{U,CallPayoff{R},Bermudan{Tt}}
const AmericanCall{U<:Underlying,R<:Real,Tt<:TimeType} = Derivative{U,CallPayoff{R},American{Tt}}

using Dates

# --- 1) Abstract path kind ---
abstract type AbstractPath1D end

# --- 2) Canonical wrapper you can subtype later or use directly ---
struct Path1D{R<:Real,T<:TimeType,V<:AbstractVector{R},W<:AbstractVector{T}} <: AbstractPath1D
    values::V
    times::W
    function Path1D(values::V, times::W) where {R<:Real,T<:TimeType,V<:AbstractVector{R},W<:AbstractVector{T}}
        @assert length(values) == length(times)
        new{R,T,V,W}(values, times)
    end
end

# --- 3) Fast interface impl for the canonical type ---
@inline value_at(p::Path1D, i::Int) = @inbounds p.values[i]
@inline  time_at(p::Path1D, i::Int) = @inbounds p.times[i]
@inline   npoints(p::Path1D)        = length(p.values)
