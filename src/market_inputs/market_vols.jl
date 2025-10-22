# ===== src/market_inputs/market_vols.jl =====

using DataFrames
using Parquet2

"""
    VolQuote{TPayoff <: AbstractPayoff, TV <: Real}

Represents a single observed implied volatility quote for a specific option.

# Fields
- `payoff::TPayoff`: The option contract (contains strike, expiry, call/put, etc.)
- `implied_vol::TV`: Observed implied volatility
- `price::TV`: Observed market price
"""
struct VolQuote{TPayoff <: AbstractPayoff, TV <: Real}
    payoff::TPayoff
    implied_vol::TV
    price::TV
end

"""
    VolQuote(payoff, reference_date, spot, rate, implied_vol)

Constructor for VolQuote from implied volatility - calculates price using Black-Scholes.
"""
function VolQuote(
    payoff::AbstractPayoff,
    reference_date::TimeType,
    spot::Real,
    rate,
    implied_vol::Real
)
    bs_inputs = BlackScholesInputs(reference_date, rate, spot, implied_vol)
    prob = PricingProblem(payoff, bs_inputs)
    price = solve(prob, BlackScholesAnalytic()).price
    return VolQuote(payoff, implied_vol, price)
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
    underlying=Spot(),
    exercise=European(),
    metadata=Dict{Symbol,Any}()
)
    n = length(strikes)
    @assert length(expiries) == n "Mismatched lengths"
    @assert length(call_puts) == n "Mismatched lengths"
    @assert length(implied_vols) == n "Mismatched lengths"
    
    payoffs = [
        VanillaOption(strikes[i], expiries[i], exercise, call_puts[i], underlying)
        for i in 1:n
    ]
    
    quotes = [
        VolQuote(payoffs[i], reference_date, spot, rate, implied_vols[i])
        for i in 1:n
    ]
    
    return MarketVolSurface(to_ticks(reference_date), spot, quotes, metadata)
end

"""
    MarketVolSurface(reference_date, spot, payoffs, implied_vols, prices; metadata=Dict())

Direct constructor when you already have matched vols and prices.
"""
function MarketVolSurface(
    reference_date::TimeType,
    spot::Real,
    payoffs::AbstractVector{<:AbstractPayoff},
    implied_vols::AbstractVector,
    prices::AbstractVector;
    metadata=Dict{Symbol,Any}()
)
    n = length(payoffs)
    @assert length(implied_vols) == n "Mismatched lengths"
    @assert length(prices) == n "Mismatched lengths"
    
    quotes = [
        VolQuote(payoffs[i], implied_vols[i], prices[i])
        for i in 1:n
    ]
    
    return MarketVolSurface(to_ticks(reference_date), spot, quotes, metadata)
end

# ===== Utility Functions =====

function filter_quotes(
    surf::MarketVolSurface;
    expiry=nothing,
    strike=nothing,
    call_put=nothing
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
    
    println("MarketVolSurface Summary:")
    println("  Reference date: $(Dates.epochms2datetime(surf.reference_date))")
    println("  Spot: $(surf.spot)")
    println("  Number of quotes: $n_quotes ($n_calls calls, $n_puts puts)")
    println("  Expiries: $(length(expiries)) ($(expiries[1]) to $(expiries[end]))")
    println("  Strikes: $(length(strikes)) ($(minimum(strikes)) to $(maximum(strikes)))")
    println("  Implied Vol range: $(round(minimum(vols), digits=4)) to $(round(maximum(vols), digits=4))")
    println("  Price range: $(round(minimum(prices), digits=2)) to $(round(maximum(prices), digits=2))")
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

# ===== Deribit Data Loading =====

function load_deribit_parquet(
    parquet_file::String;
    rate=0.05,
    filter_params=nothing
)
    df = DataFrame(Parquet2.Dataset(parquet_file))
    reference_date = Date(df.date[1])
    spot = df.underlying_price[1]
    
    df_filtered = filter(row -> 
        !ismissing(row.mark_price) && 
        row.mark_price > 0 && 
        !ismissing(row.mark_iv) && 
        row.mark_iv > 0,
        df
    )
    
    if filter_params !== nothing
        min_days = get(filter_params, :min_days, 7)
        max_years = get(filter_params, :max_years, 2.0)
        min_moneyness = get(filter_params, :min_moneyness, 0.5)
        max_moneyness = get(filter_params, :max_moneyness, 1.5)
        
        min_expiry = reference_date + Day(min_days)
        max_expiry = reference_date + Year(floor(Int, max_years)) + 
                     Day(round(Int, (max_years - floor(max_years)) * 365))
        
        df_filtered = filter(df_filtered) do row
            expiry_date = if row.expiry isa DateTime
                Date(row.expiry)
            elseif row.expiry isa Integer
                Date(Dates.unix2datetime(row.expiry / 1000))
            else
                Date(row.expiry)
            end
            
            moneyness = row.strike / spot
            
            expiry_date >= min_expiry &&
            expiry_date <= max_expiry &&
            moneyness >= min_moneyness &&
            moneyness <= max_moneyness
        end
    end
    
    strikes = Float64[]
    expiries = Date[]
    call_puts = AbstractCallPut[]
    implied_vols = Float64[]
    
    for row in eachrow(df_filtered)
        push!(strikes, Float64(row.strike))
        
        expiry_date = if row.expiry isa DateTime
            Date(row.expiry)
        elseif row.expiry isa Integer
            Date(Dates.unix2datetime(row.expiry / 1000))
        else
            Date(row.expiry)
        end
        push!(expiries, expiry_date)
        
        option_type = row.option_type == "C" ? Call() : Put()
        push!(call_puts, option_type)
        
        push!(implied_vols, row.mark_iv / 100.0)
    end
    
    metadata = Dict{Symbol, Any}(
        :source => "Deribit",
        :underlying => df.underlying[1],
        :data_file => basename(parquet_file),
        :timestamp => df.ts[1],
        :original_count => nrow(df),
        :filtered_count => length(strikes)
    )
    
    return MarketVolSurface(
        reference_date,
        spot,
        strikes,
        expiries,
        call_puts,
        implied_vols,
        rate,
        metadata=metadata
    )
end