using Dates

# --- Core nouns ---
abstract type PayoffFunction end
abstract type ExercisePolicy end
abstract type Underlying end

struct Derivative{U<:Underlying,P<:PayoffFunction,E<:ExercisePolicy}
    underlying::U
    payoff::P
    exercise::E
end

# --- Underlying ---
struct Equity <: Underlying
    symbol::Symbol
end

# --- Payoff: Call(K) ---
struct CallPayoff{T<:Real} <: PayoffFunction
    K::T
end

# --- Exercise policies (time-based) ---
"European: single maturity date."
struct European{T<:TimeType} <: ExercisePolicy
    maturity::T
end

"Bermudan: finite set of admissible exercise dates."
struct Bermudan{T<:TimeType} <: ExercisePolicy
    dates::Vector{T}
end

"American: continuous-time right within a window [start, maturity]."
struct American{T<:TimeType} <: ExercisePolicy
    start::T
    maturity::T
end

# --- Optional type aliases for common combos ---
const EuropeanCall{U<:Underlying,R<:Real,Tt<:TimeType} = Derivative{U,CallPayoff{R},European{Tt}}
const BermudanCall{U<:Underlying,R<:Real,Tt<:TimeType} = Derivative{U,CallPayoff{R},Bermudan{Tt}}
const AmericanCall{U<:Underlying,R<:Real,Tt<:TimeType} = Derivative{U,CallPayoff{R},American{Tt}}
