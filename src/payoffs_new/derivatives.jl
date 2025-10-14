# --- Abstract interfaces ------------------------------------------------------
abstract type AbstractUnderlying end
abstract type AbstractDerivative <: AbstractUnderlying end
abstract type AbstractPayoff end
abstract type AbstractActionSet end

# --- Canonical contract -------------------------------------------------------
struct GenericContract{TType,NType,UType<:AbstractUnderlying,
                       PType<:AbstractPayoff,CType,
                       AType<:AbstractActionSet} <: AbstractDerivative
    horizon::TType
    notional::NType
    underlying::UType
    payoff::PType
    currencies::CType
    actions::AType
end

# --- Payoff(s) ---------------------------------------------------------------
struct CallPayoff{K} <: AbstractPayoff
    strike::K
end
