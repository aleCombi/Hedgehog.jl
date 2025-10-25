# ===== src/market_inputs/market_vols.jl =====

using DataFrames
using Parquet2
using Statistics

"""
    VolQuote{TPayoff <: AbstractPayoff, TV <: Real}

Represents a single observed implied volatility quote for a specific option.

# Fields
- `payoff::TPayoff`: The option contract (contains strike, expiry, call/put, etc.)
- `forward::TV`: Forward (or future) price for *this* quote
- `implied_vol::TV`: Observed implied volatility
- `price::TV`: Observed market price (typically mark/mid)
- `bid::TV`: Bid price (use NaN if unavailable)
- `ask::TV`: Ask price (use NaN if unavailable)
"""
struct VolQuote{TPayoff <: AbstractPayoff, TV <: Real}
    payoff::TPayoff
    forward::TV
    implied_vol::TV
    price::TV
    bid::TV
    ask::TV
end

"""
    VolQuote(payoff, forward, implied_vol, price; bid=NaN, ask=NaN)

Constructor with explicit price (already observed) and per-quote forward.
"""
function VolQuote(
    payoff::AbstractPayoff,
    forward::Real,
    implied_vol::Real,
    price::Real;
    bid::Real=NaN,
    ask::Real=NaN
)
    return VolQuote(payoff, forward, implied_vol, price, bid, ask)
end

"""
    VolQuote(payoff, reference_date, forward, implied_vol; bid=NaN, ask=NaN)

Constructor for VolQuote from implied volatility — calculates price assuming zero rate.
Implements Black-76 equivalently by using Black-Scholes with `spot = forward` and `rate = 0.0`.
"""
function VolQuote(
    payoff::AbstractPayoff,
    reference_date::TimeType,
    forward::Real,
    implied_vol::Real;
    bid::Real=NaN,
    ask::Real=NaN
)
    # Zero-rate everywhere; price as BS with spot := forward.
    bs_inputs = BlackScholesInputs(reference_date, 0.0, forward, implied_vol)
    prob = PricingProblem(payoff, bs_inputs)
    price = solve(prob, BlackScholesAnalytic()).price
    return VolQuote(payoff, forward, implied_vol, price, bid, ask)
end

"""
    bid_ask_spread(q::VolQuote) -> Float64
"""
bid_ask_spread(q::VolQuote) = q.ask - q.bid

"""
    bid_ask_spread_pct(q::VolQuote) -> Float64
"""
function bid_ask_spread_pct(q::VolQuote)
    spread = bid_ask_spread(q)
    return isnan(spread) ? NaN : spread / q.price
end

"""
    has_bid_ask(q::VolQuote) -> Bool
"""
has_bid_ask(q::VolQuote) = !isnan(q.bid) && !isnan(q.ask)

"""
    MarketVolSurface{TRef <: Real, TQ <: VolQuote}

A collection of market-observed implied volatility quotes.
Note: no surface-level spot anymore; each quote carries its own forward.
"""
struct MarketVolSurface{TRef <: Real, TQ <: VolQuote}
    reference_date::TRef
    quotes::Vector{TQ}
    metadata::Dict{Symbol, Any}
end

"""
    MarketVolSurface(reference_date, quotes; metadata=Dict())

Constructor for MarketVolSurface from a vector of VolQuote objects.
"""
function MarketVolSurface(
    reference_date::TimeType,
    quotes::Vector{<:VolQuote};
    metadata=Dict{Symbol,Any}()
)
    return MarketVolSurface(to_ticks(reference_date), quotes, metadata)
end

"""
    MarketVolSurface(reference_date, strikes, expiries, call_puts, forwards, implied_vols; kwargs...)

Convenience constructor from parallel arrays with per-quote forwards.
Priced using zero rate (DF = 1) and spot := forward for analytic BS pricing.
"""
function MarketVolSurface(
    reference_date::TimeType,
    strikes::AbstractVector,
    expiries::AbstractVector{<:TimeType},
    call_puts::AbstractVector{<:AbstractCallPut},
    forwards::AbstractVector,
    implied_vols::AbstractVector;
    bids::Union{AbstractVector,Nothing}=nothing,
    asks::Union{AbstractVector,Nothing}=nothing,
    underlying=Spot(),      # we ignore spot vs future distinction in pricing (see above)
    exercise=European(),
    metadata=Dict{Symbol,Any}()
)
    n = length(strikes)
    @assert length(expiries) == n "Mismatched lengths (expiries)"
    @assert length(call_puts) == n "Mismatched lengths (call_puts)"
    @assert length(forwards) == n "Mismatched lengths (forwards)"
    @assert length(implied_vols) == n "Mismatched lengths (implied_vols)"

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
        VolQuote(payoffs[i], reference_date, forwards[i], implied_vols[i];
                 bid=bids[i], ask=asks[i])
        for i in 1:n
    ]

    return MarketVolSurface(to_ticks(reference_date), quotes, metadata)
end

"""
    MarketVolSurface(reference_date, payoffs, forwards, implied_vols, prices; ...)

Direct constructor when you already have matched (payoff, forward, vol, price).
"""
function MarketVolSurface(
    reference_date::TimeType,
    payoffs::AbstractVector{<:AbstractPayoff},
    forwards::AbstractVector,
    implied_vols::AbstractVector,
    prices::AbstractVector;
    bids::Union{AbstractVector,Nothing}=nothing,
    asks::Union{AbstractVector,Nothing}=nothing,
    metadata=Dict{Symbol,Any}()
)
    n = length(payoffs)
    @assert length(forwards) == n "Mismatched lengths (forwards)"
    @assert length(implied_vols) == n "Mismatched lengths (implied_vols)"
    @assert length(prices) == n "Mismatched lengths (prices)"

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
        VolQuote(payoffs[i], forwards[i], implied_vols[i], prices[i];
                 bid=bids[i], ask=asks[i])
        for i in 1:n
    ]

    return MarketVolSurface(to_ticks(reference_date), quotes, metadata)
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

get_strikes(surf::MarketVolSurface) = sort(unique(q.payoff.strike for q in surf.quotes))

function Base.summary(surf::MarketVolSurface)
    n_quotes = length(surf.quotes)
    expiries = get_expiries(surf)
    strikes = get_strikes(surf)
    vols = [q.implied_vol for q in surf.quotes]
    prices = [q.price for q in surf.quotes]
    fwd   = [q.forward for q in surf.quotes]

    n_calls = count(q -> isa(q.payoff.call_put, Call), surf.quotes)
    n_puts  = count(q -> isa(q.payoff.call_put, Put), surf.quotes)

    quotes_with_ba = filter(has_bid_ask, surf.quotes)
    n_with_ba = length(quotes_with_ba)

    println("MarketVolSurface Summary:")
    println("  Reference date: $(Dates.epochms2datetime(surf.reference_date))")
    println("  Number of quotes: $n_quotes ($n_calls calls, $n_puts puts)")
    println("  Expiries: $(length(expiries)) ($(expiries[1]) to $(expiries[end]))")
    println("  Strikes: $(length(strikes)) ($(minimum(strikes)) to $(maximum(strikes)))")
    println("  Forward range: $(round(minimum(fwd), digits=4)) to $(round(maximum(fwd), digits=4))")
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

"""
    calibrate_heston(market_surf, initial_params; spot=nothing, rate=0.0, ...)

Calibrate Heston to the market prices in `market_surf`.
Since the surface no longer stores a spot, either pass `spot=...` explicitly,
or it will be *approximated* using the median forward among the shortest-maturity bucket.
`rate` defaults to 0.0 to match the zero-rate convention elsewhere in this module.
"""
function calibrate_heston(
    market_surf::MarketVolSurface,
    initial_params;
    spot::Union{Nothing,Real}=nothing,
    rate=0.0,
    pricing_method=CarrMadan(1.0, 32.0, HestonDynamics()),
    optimizer=OptimizerAlgo(),
    lb=nothing,
    ub=nothing
)
    reference_date = Dates.epochms2datetime(market_surf.reference_date)

    payoffs = [q.payoff for q in market_surf.quotes]
    market_prices = [q.price for q in market_surf.quotes]

    # If no spot is provided, approximate it from the forwards of the shortest maturity.
    if spot === nothing
        # group by expiry, pick min T, then median forward in that bucket
        expiries = unique(q.payoff.expiry for q in market_surf.quotes)
        Tmin = minimum(expiries)
        fwd_bucket = [q.forward for q in market_surf.quotes if q.payoff.expiry == Tmin]
        if isempty(fwd_bucket)
            error("Cannot infer spot: no quotes found.")
        end
        spot = median(fwd_bucket)
    end

    heston_inputs = HestonInputs(
        reference_date,
        rate,
        spot,
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

    # Reasonable defaults (you can override)
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
