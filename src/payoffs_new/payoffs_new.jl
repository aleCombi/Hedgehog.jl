# --- Abstract interfaces ------------------------------------------------------
abstract type AbstractUnderlying end
abstract type AbstractDerivative <: AbstractUnderlying end
abstract type AbstractPayoff end
abstract type AbstractActionSet end

# Six traits (derivative-only)
horizon(d::AbstractDerivative)    = error("horizon not implemented")
notional(d::AbstractDerivative)   = error("notional not implemented")
underlying(d::AbstractDerivative) = error("underlying not implemented")
actions(d::AbstractDerivative)    = error("actions not implemented")
payoff(d::AbstractDerivative)     = error("payoff not implemented")
currencies(d::AbstractDerivative) = error("currencies not implemented")

# --- Defaults ----------------------------------------------------------------
struct NoActions <: AbstractActionSet end
const NO_ACTIONS = NoActions()

struct DummyUnderlying <: AbstractUnderlying end
struct DummyCurrency   end
const DUMMY_UNDERLYING = DummyUnderlying()
const DUMMY_CURRENCY   = DummyCurrency()

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

# Trait implementations
horizon(d::GenericContract)    = d.horizon
notional(d::GenericContract)   = d.notional
underlying(d::GenericContract) = d.underlying
payoff(d::GenericContract)     = d.payoff
currencies(d::GenericContract) = d.currencies
actions(d::GenericContract)    = d.actions

# --- Payoff(s) ---------------------------------------------------------------
struct CallPayoff{K} <: AbstractPayoff
    strike::K
end

# --- Explicit builders (with defaults) ---------------------------------------

# Single-leg, one currency, no actions
function SingleLegDerivative(horizon;
                             notional::Real = 1.0,
                             underlying::AbstractUnderlying = DUMMY_UNDERLYING,
                             payoff::AbstractPayoff = CallPayoff(0.0),
                             currency = DUMMY_CURRENCY)
    GenericContract(horizon, notional, underlying, payoff, currency, NO_ACTIONS)
end

# Multi-leg, tuple notionals and tuple currencies, no actions
function MultiLegDerivative(horizon;
                            notionals::NTuple{K,<:Real} = (1.0, 1.0),
                            underlying::AbstractUnderlying = DUMMY_UNDERLYING,
                            payoff::AbstractPayoff = CallPayoff(0.0),
                            currencies::NTuple{K,Any} = (DUMMY_CURRENCY, DUMMY_CURRENCY)) where {K}
    GenericContract(horizon, notionals, underlying, payoff, currencies, NO_ACTIONS)
end

# European Call builder (wraps SingleLegDerivative)
EuropeanCall(horizon, strike;
             notional::Real = 1.0,
             underlying::AbstractUnderlying = DUMMY_UNDERLYING,
             currency = DUMMY_CURRENCY) =
    SingleLegDerivative(horizon;
                        notional = notional,
                        underlying = underlying,
                        payoff = CallPayoff(strike),
                        currency = currency)
