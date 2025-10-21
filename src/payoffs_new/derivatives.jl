# payoffs_new.jl - Complete implementation

# --- Abstract interfaces ------------------------------------------------------
abstract type AbstractUnderlying end
abstract type AbstractPayoffNew end
abstract type AbstractDerivative <: AbstractPayoffNew end
abstract type AbstractActionSet end

# --- Exercise styles (for dispatch/traits only) -------------------------------
abstract type ExerciseStyle end
struct EuropeanStyle <: ExerciseStyle end
struct AmericanStyle <: ExerciseStyle end

# --- Placeholders -------------------------------------------------------------
struct NoAction <: AbstractActionSet end
struct StoppingRule <: AbstractActionSet end

struct GenericUnderlying <: AbstractUnderlying
    identifier::Symbol
end
GenericUnderlying() = GenericUnderlying(:UNDERLYING)

struct Currency
    code::Symbol
end

# --- Trait: Extract exercise style from action type --------------------------
exercise_style(::Type{NoAction}) = EuropeanStyle()
exercise_style(::Type{StoppingRule}) = AmericanStyle()
exercise_style(action::AbstractActionSet) = exercise_style(typeof(action))

# --- Canonical contract -------------------------------------------------------
struct GenericContract{TType,NType,UType<:AbstractUnderlying,
                       PType<:AbstractPayoffNew,CType,
                       AType<:AbstractActionSet} <: AbstractPayoff
    horizon::TType
    notional::NType
    underlying::UType
    payoff::PType
    currencies::CType
    actions::AType
end

# --- Type Aliases for Dispatch ------------------------------------------------
const EuropeanContract{P<:AbstractPayoffNew} = 
    GenericContract{<:Any,<:Any,<:Any,P,<:Any,NoAction}

const AmericanContract{P<:AbstractPayoffNew} = 
    GenericContract{<:Any,<:Any,<:Any,P,<:Any,StoppingRule}

const EuropeanProblem{P<:AbstractPayoffNew, M<:AbstractMarketInputs} = 
    PricingProblem{EuropeanContract{P}, M}

const AmericanProblem{P<:AbstractPayoffNew, M<:AbstractMarketInputs} = 
    PricingProblem{AmericanContract{P}, M}

# -------------------------------------------------------- 
# Payoffs design
# -------------------------------------------------------- 

# What we extract from a simulated path
abstract type PathStatistic end

struct TerminalValue{T<:Real} <: PathStatistic
    S_T::T
end

# Vanilla option payoff
struct VanillaPayoff{K<:Real, CP<:AbstractCallPut} <: AbstractPayoffNew
    strike::K
    call_put::CP
end

function evaluate(p::VanillaPayoff, stat::TerminalValue)::Float64
    return max(p.call_put() * (stat.S_T - p.strike), 0.0)
end

# -------------------------------------------------------- 
# Constructors
# -------------------------------------------------------- 

"""
    VanillaOption(strike, expiry, call_put, exercise_style; kwargs...)

Constructs a vanilla option with specified exercise style.
"""
function VanillaOption(
    strike,
    expiry,
    call_put,
    exercise_style::ExerciseStyle;
    underlying = GenericUnderlying(),
    notional = 1.0,
    currency = Currency(:USD)
)
    payoff = VanillaPayoff(strike, call_put)
    
    # Choose action type based on exercise style
    actions = if exercise_style isa EuropeanStyle
        NoAction()
    elseif exercise_style isa AmericanStyle
        StoppingRule()
    else
        error("Unknown exercise style: $exercise_style")
    end
    
    return GenericContract(
        expiry,
        notional,
        underlying,
        payoff,
        currency,
        actions
    )
end

# Convenience: default to European
function VanillaOption(
    strike,
    expiry,
    call_put;
    underlying = GenericUnderlying(),
    notional = 1.0,
    currency = Currency(:USD)
)
    return VanillaOption(strike, expiry, call_put, EuropeanStyle(); 
                         underlying=underlying, notional=notional, currency=currency)
end

"""
    AmericanVanillaOption(strike, expiry, call_put; kwargs...)

Constructs an American-style vanilla option.
"""
function AmericanVanillaOption(
    strike,
    expiry,
    call_put;
    underlying = GenericUnderlying(),
    notional = 1.0,
    currency = Currency(:USD)
)
    return VanillaOption(strike, expiry, call_put, AmericanStyle(); 
                         underlying=underlying, notional=notional, currency=currency)
end

# -------------------------------------------------------- 
# Pricing - European with Black-Scholes
# -------------------------------------------------------- 

function solve(
    prob::PricingProblem{<:EuropeanContract},
    method::BlackScholesAnalytic
)
    return _solve_european_bs(prob.payoff.payoff, prob, method)
end

function _solve_european_bs(
    payoff::VanillaPayoff,
    prob::PricingProblem,
    method::BlackScholesAnalytic
)
    contract = prob.payoff
    market = prob.market_inputs

    K = payoff.strike
    σ = get_vol(market.sigma, contract.horizon, K)
    cp = payoff.call_put()
    T = yearfrac(market.referenceDate, contract.horizon)
    D = df(market.rate, contract.horizon)
    F = market.spot / D

    price = if σ == 0
        D * evaluate(payoff, TerminalValue(F))
    else
        sqrtT = sqrt(T)
        d1 = (log(F / K) + 0.5 * σ^2 * T) / (σ * sqrtT)
        d2 = d1 - σ * sqrtT
        N = Normal()
        D * cp * (F * cdf(N, cp * d1) - K * cdf(N, cp * d2))
    end

    return AnalyticSolution(prob, method, price * contract.notional)
end

# -------------------------------------------------------- 
# Pricing - European with CRR (for comparison)
# -------------------------------------------------------- 

function solve(
    prob::PricingProblem{<:EuropeanContract},
    method::CoxRossRubinsteinMethod
)
    return _solve_european_crr(prob.payoff.payoff, prob, method)
end

function _solve_european_crr(
    payoff::VanillaPayoff,
    prob::PricingProblem,
    method::CoxRossRubinsteinMethod
)
    contract = prob.payoff
    market = prob.market_inputs
    
    K = payoff.strike
    σ = get_vol(market.sigma, contract.horizon, K)
    
    steps = method.steps
    T = yearfrac(market.referenceDate, contract.horizon)
    forward = market.spot / df(market.rate, contract.horizon)
    ΔT = T / steps
    u = exp(σ * sqrt(ΔT))
    
    forward_at_i(i) = forward * u .^ (-i:2:i)
    
    # European: only need terminal value
    p = 1 / (1 + u)
    
    terminal_values = forward_at_i(steps)
    value = [evaluate(payoff, TerminalValue(S)) for S in terminal_values]
    
    # Backward induction (no early exercise)
    for step in reverse(0:(steps - 1))
        continuation = p * value[2:end] + (1 - p) * value[1:end-1]
        discount_factor = exp(-zero_rate(market.rate, contract.horizon) * ΔT)
        value = discount_factor * continuation
    end
    
    return CRRSolution(prob, method, value[1] * contract.notional)
end

# -------------------------------------------------------- 
# Pricing - American with CRR
# -------------------------------------------------------- 

function solve(
    prob::PricingProblem{<:AmericanContract},
    method::CoxRossRubinsteinMethod
)
    return _solve_american_crr(prob.payoff.payoff, prob, method)
end

function _solve_american_crr(
    payoff::VanillaPayoff,
    prob::PricingProblem,
    method::CoxRossRubinsteinMethod
)
    contract = prob.payoff
    market = prob.market_inputs
    
    K = payoff.strike
    σ = get_vol(market.sigma, contract.horizon, K)
    
    steps = method.steps
    T = yearfrac(market.referenceDate, contract.horizon)
    forward = market.spot / df(market.rate, contract.horizon)
    ΔT = T / steps
    u = exp(σ * sqrt(ΔT))
    
    forward_at_i(i) = forward * u .^ (-i:2:i)
    
    # American on spot: need to discount spot from forward
    underlying_at_i(i) = exp(
        -zero_rate(market.rate, add_yearfrac(market.referenceDate, i * ΔT)) *
        (steps - i) * ΔT
    ) * forward_at_i(i)
    
    p = 1 / (1 + u)
    
    # Terminal payoff
    terminal_values = forward_at_i(steps)
    value = [evaluate(payoff, TerminalValue(S)) for S in terminal_values]
    
    # Backward induction with early exercise
    for step in reverse(0:(steps - 1))
        continuation = p * value[2:end] + (1 - p) * value[1:end-1]
        discount_factor = exp(-zero_rate(market.rate, contract.horizon) * ΔT)
        discounted = discount_factor * continuation
        
        # American: compare with intrinsic value
        S_at_step = underlying_at_i(step)
        intrinsic = [evaluate(payoff, TerminalValue(S)) for S in S_at_step]
        value = max.(discounted, intrinsic)
    end
    
    return CRRSolution(prob, method, value[1] * contract.notional)
end