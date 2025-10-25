# ===== src/market_inputs/market_vols.jl =====

using DataFrames
using Parquet2

"""
    VolQuote{TPayoff <: AbstractPayoff, TV <: Real}

Represents a single observed implied volatility quote for a specific option.

# Fields
- `payoff::TPayoff`: The option contract (contains strike, expiry, call/put, etc.)
- `implied_vol::TV`: Observed implied volatility
- `price::TV`: Observed market price (typically mark/mid)
- `bid::TV`: Bid price (use NaN if unavailable)
- `ask::TV`: Ask price (use NaN if unavailable)
"""
struct VolQuote{TPayoff <: AbstractPayoff, TV <: Real}
    payoff::TPayoff
    implied_vol::TV
    price::TV
    bid::TV
    ask::TV
end

"""
    VolQuote(payoff, implied_vol, price; bid=NaN, ask=NaN)

Constructor with optional bid/ask prices.
"""
function VolQuote(
    payoff::AbstractPayoff,
    implied_vol::Real,
    price::Real;
    bid::Real=NaN,
    ask::Real=NaN
)
    return VolQuote(payoff, implied_vol, price, bid, ask)
end

"""
    VolQuote(payoff, reference_date, spot, rate, implied_vol; bid=NaN, ask=NaN)

Constructor for VolQuote from implied volatility - calculates price using Black-Scholes.
"""
function VolQuote(
    payoff::AbstractPayoff,
    reference_date::TimeType,
    spot::Real,
    rate,
    implied_vol::Real;
    bid::Real=NaN,
    ask::Real=NaN
)
    bs_inputs = BlackScholesInputs(reference_date, rate, spot, implied_vol)
    prob = PricingProblem(payoff, bs_inputs)
    price = solve(prob, BlackScholesAnalytic()).price
    return VolQuote(payoff, implied_vol, price, bid, ask)
end

"""
    bid_ask_spread(q::VolQuote) -> Float64

Calculate bid-ask spread in currency units. Returns NaN if bid/ask unavailable.
"""
function bid_ask_spread(q::VolQuote)
    return q.ask - q.bid
end

"""
    bid_ask_spread_pct(q::VolQuote) -> Float64

Calculate bid-ask spread as percentage of mid price. Returns NaN if unavailable.
"""
function bid_ask_spread_pct(q::VolQuote)
    spread = bid_ask_spread(q)
    return isnan(spread) ? NaN : spread / q.price
end

"""
    has_bid_ask(q::VolQuote) -> Bool

Check if quote has valid bid/ask data.
"""
function has_bid_ask(q::VolQuote)
    return !isnan(q.bid) && !isnan(q.ask)
end

"""
    MarketVolSurface{TRef <: Real, TQ <: VolQuote}

A collection of market-observed implied volatility quotes.
"""
struct MarketVolSurface{TRef <: Real, TQ <: VolQuote}
    reference_date::TRef
    spot::Real
    quotes::Vector{TQ}
    metadata::Dict{Symbol, Any}
end

"""
    MarketVolSurface(reference_date, spot, quotes; metadata=Dict())

Constructor for MarketVolSurface from a vector of VolQuote objects.
"""
function MarketVolSurface(
    reference_date::TimeType,
    spot::Real,
    quotes::Vector{<:VolQuote};
    metadata=Dict{Symbol,Any}()
)
    return MarketVolSurface(to_ticks(reference_date), spot, quotes, metadata)
end

"""
    MarketVolSurface(reference_date, spot, strikes, expiries, call_puts, implied_vols, rate; kwargs...)

Convenience constructor from parallel arrays of implied volatilities.
"""
function MarketVolSurface(
    reference_date::TimeType,
    spot::Real,
    strikes::AbstractVector,
    expiries::AbstractVector{<:TimeType},
    call_puts::AbstractVector{<:AbstractCallPut},
    implied_vols::AbstractVector,
    rate;
    bids::Union{AbstractVector,Nothing}=nothing,
    asks::Union{AbstractVector,Nothing}=nothing,
    underlying=Spot(),
    exercise=European(),
    metadata=Dict{Symbol,Any}()
)
    n = length(strikes)
    @assert length(expiries) == n "Mismatched lengths"
    @assert length(call_puts) == n "Mismatched lengths"
    @assert length(implied_vols) == n "Mismatched lengths"
    
    if bids !== nothing
        @assert length(bids) == n "Mismatched bids length"
    else
        bids = fill(NaN, n)
    end
    
    if asks !== nothing
        @assert length(asks) == n "Mismatched asks length"
    else
        asks = fill(NaN, n)
    end
    
    payoffs = [
        VanillaOption(strikes[i], expiries[i], exercise, call_puts[i], underlying)
        for i in 1:n
    ]
    
    quotes = [
        VolQuote(payoffs[i], reference_date, spot, rate, implied_vols[i]; 
                bid=bids[i], ask=asks[i])
        for i in 1:n
    ]
    
    return MarketVolSurface(to_ticks(reference_date), spot, quotes, metadata)
end

"""
    MarketVolSurface(reference_date, spot, payoffs, implied_vols, prices; bids=nothing, asks=nothing, metadata=Dict())

Direct constructor when you already have matched vols and prices.
"""
function MarketVolSurface(
    reference_date::TimeType,
    spot::Real,
    payoffs::AbstractVector{<:AbstractPayoff},
    implied_vols::AbstractVector,
    prices::AbstractVector;
    bids::Union{AbstractVector,Nothing}=nothing,
    asks::Union{AbstractVector,Nothing}=nothing,
    metadata=Dict{Symbol,Any}()
)
    n = length(payoffs)
    @assert length(implied_vols) == n "Mismatched lengths"
    @assert length(prices) == n "Mismatched lengths"
    
    if bids !== nothing
        @assert length(bids) == n "Mismatched bids length"
    else
        bids = fill(NaN, n)
    end
    
    if asks !== nothing
        @assert length(asks) == n "Mismatched asks length"
    else
        asks = fill(NaN, n)
    end
    
    quotes = [
        VolQuote(payoffs[i], implied_vols[i], prices[i], bids[i], asks[i])
        for i in 1:n
    ]
    
    return MarketVolSurface(to_ticks(reference_date), spot, quotes, metadata)
end

# ===== Utility Functions =====

function filter_quotes(
    surf::MarketVolSurface;
    expiry=nothing,
    strike=nothing,
    call_put=nothing,
    max_spread_pct=nothing
)
    filtered = surf.quotes
    
    if expiry !== nothing
        expiry_ticks = to_ticks(expiry)
        filtered = filter(q -> q.payoff.expiry == expiry_ticks, filtered)
    end
    
    if strike !== nothing
        filtered = filter(q -> q.payoff.strike ≈ strike, filtered)
    end
    
    if call_put !== nothing
        filtered = filter(q -> typeof(q.payoff.call_put) == typeof(call_put), filtered)
    end
    
    # Filter by bid-ask spread
    if max_spread_pct !== nothing
        filtered = filter(filtered) do q
            has_bid_ask(q) && bid_ask_spread_pct(q) <= max_spread_pct
        end
    end
    
    return filtered
end

function get_expiries(surf::MarketVolSurface)
    unique_ticks = unique(q.payoff.expiry for q in surf.quotes)
    return sort([Dates.epochms2datetime(t) for t in unique_ticks])
end

function get_strikes(surf::MarketVolSurface)
    return sort(unique(q.payoff.strike for q in surf.quotes))
end

function Base.summary(surf::MarketVolSurface)
    n_quotes = length(surf.quotes)
    expiries = get_expiries(surf)
    strikes = get_strikes(surf)
    vols = [q.implied_vol for q in surf.quotes]
    prices = [q.price for q in surf.quotes]
    
    n_calls = count(q -> isa(q.payoff.call_put, Call), surf.quotes)
    n_puts = count(q -> isa(q.payoff.call_put, Put), surf.quotes)
    
    # Bid-ask statistics
    quotes_with_ba = filter(has_bid_ask, surf.quotes)
    n_with_ba = length(quotes_with_ba)
    
    println("MarketVolSurface Summary:")
    println("  Reference date: $(Dates.epochms2datetime(surf.reference_date))")
    println("  Spot: $(surf.spot)")
    println("  Number of quotes: $n_quotes ($n_calls calls, $n_puts puts)")
    println("  Expiries: $(length(expiries)) ($(expiries[1]) to $(expiries[end]))")
    println("  Strikes: $(length(strikes)) ($(minimum(strikes)) to $(maximum(strikes)))")
    println("  Implied Vol range: $(round(minimum(vols), digits=4)) to $(round(maximum(vols), digits=4))")
    println("  Price range: $(round(minimum(prices), digits=2)) to $(round(maximum(prices), digits=2))")
    
    if n_with_ba > 0
        spreads_pct = [bid_ask_spread_pct(q) * 100 for q in quotes_with_ba]
        println("  Bid-Ask data: $n_with_ba quotes")
        println("    Spread range: $(round(minimum(spreads_pct), digits=2))% to $(round(maximum(spreads_pct), digits=2))%")
        println("    Avg spread: $(round(mean(spreads_pct), digits=2))%")
    else
        println("  Bid-Ask data: Not available")
    end
    
    println("  Metadata: $(surf.metadata)")
end

function get_quote(
    surf::MarketVolSurface,
    strike::Real,
    expiry::TimeType,
    call_put::AbstractCallPut
)
    expiry_ticks = to_ticks(expiry)
    
    idx = findfirst(surf.quotes) do q
        q.payoff.strike ≈ strike &&
        q.payoff.expiry == expiry_ticks &&
        typeof(q.payoff.call_put) == typeof(call_put)
    end
    
    if idx === nothing
        error("Quote not found: K=$strike, T=$expiry, type=$(typeof(call_put))")
    end
    
    return surf.quotes[idx]
end

# ===== Calibration Interface =====

function calibrate_heston(
    market_surf::MarketVolSurface,
    rate,
    initial_params;
    pricing_method=CarrMadan(1.0, 32.0, HestonDynamics()),
    optimizer=OptimizerAlgo(),
    lb=nothing,
    ub=nothing
)
    reference_date = Dates.epochms2datetime(market_surf.reference_date)
    
    payoffs = [q.payoff for q in market_surf.quotes]
    market_prices = [q.price for q in market_surf.quotes]
    
    heston_inputs = HestonInputs(
        reference_date,
        rate,
        market_surf.spot,
        initial_params.v0,
        initial_params.κ,
        initial_params.θ,
        initial_params.σ,
        initial_params.ρ
    )
    
    initial_guess = [
        initial_params.v0,
        initial_params.κ,
        initial_params.θ,
        initial_params.σ,
        initial_params.ρ
    ]
    
    # Set reasonable default bounds for BTC if not provided
    if lb === nothing
        lb = [0.04, 0.5, 0.04, 0.1, -0.99]
    end
    if ub === nothing
        ub = [1.0, 100.0, 1.0, 20.0, -0.01]
    end
    
    accessors = [
        @optic(_.market_inputs.V0),
        @optic(_.market_inputs.κ),
        @optic(_.market_inputs.θ),
        @optic(_.market_inputs.σ),
        @optic(_.market_inputs.ρ)
    ]
    
    basket = BasketPricingProblem(payoffs, heston_inputs)
    
    calib_problem = CalibrationProblem(
        basket,
        pricing_method,
        accessors,
        market_prices,
        initial_guess,
        lb=lb,
        ub=ub
    )
    
    return solve(calib_problem, optimizer)
end