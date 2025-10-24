# butterfly_analysis.jl
# Butterfly spread mispricing detection and reversion tracking
# IMPROVED VERSION: Uses bid/ask prices to account for transaction costs

using DataFrames
using Dates
using Statistics
using Printf
using CSV
using Hedgehog

"""
    ButterflySpread

Represents a butterfly spread with its component options.

A butterfly consists of:
- 1 long call at lower strike (K1)
- 2 short calls at middle strike (K2)
- 1 long call at upper strike (K3)

Where K1 < K2 < K3 and typically K2 = (K1 + K3) / 2
"""
struct ButterflySpread
    expiry_date::Date
    expiry_ts::Int64
    K1::Float64  # Lower strike (long)
    K2::Float64  # Middle strike (short 2x)
    K3::Float64  # Upper strike (long)
    option_type::String  # "Call" or "Put"
    
    # Market prices (execution prices with spread)
    market_price_K1::Float64
    market_price_K2::Float64
    market_price_K3::Float64
    market_butterfly_price::Float64  # Net cost including spread
    
    # Model prices
    model_price_K1::Float64
    model_price_K2::Float64
    model_price_K3::Float64
    model_butterfly_price::Float64
    
    # Analysis
    price_error::Float64  # model - market (positive = market underpriced)
    rel_price_error::Float64  # as fraction of market price
    
    # Flags
    underpriced::Bool  # Market cheaper than model (after paying spread)
    overpriced::Bool   # Market more expensive than model (after paying spread)
end

"""
    ButterflyReversion

Tracks whether a butterfly's price reverted toward model prediction.
"""
struct ButterflyReversion
    butterfly::ButterflySpread
    
    # Initial snapshot
    initial_time::DateTime
    initial_market_price::Float64
    initial_model_price::Float64
    initial_error::Float64
    
    # Reversion snapshots (up to 2 hours ahead)
    reversion_times::Vector{DateTime}
    reversion_market_prices::Vector{Float64}
    reversion_gains::Vector{Float64}  # Gain if position closed (as fraction of cost)
    
    # Reversion flags
    reverted::Bool  # Did it reach minimum gain threshold?
    time_to_reversion::Union{Nothing, Period}  # How long until reversion
    max_gain::Float64  # Maximum gain observed
    final_gain::Float64  # Gain at end of tracking period
end

"""
    get_execution_price(opt, direction::Symbol) -> Float64

Get execution price accounting for bid-ask spread.

# Arguments
- `opt`: VolQuote object
- `direction`: :buy (pay ask) or :sell (receive bid)

Returns mid price if bid/ask unavailable.
"""
function get_execution_price(opt, direction::Symbol)
    if direction == :buy
        # Buy: pay the ask (or mid if ask unavailable)
        return isnan(opt.ask) ? opt.price : opt.ask
    else  # :sell
        # Sell: receive the bid (or mid if bid unavailable)
        return isnan(opt.bid) ? opt.price : opt.bid
    end
end

"""
    detect_butterfly_mispricings(market_surface, heston_inputs, pricing_method, rate, 
                                 iv_config, thresholds)
    -> Vector{ButterflySpread}

Detect mispriced butterfly spreads using bid/ask prices for realistic execution.

For a butterfly (buy K1, sell 2×K2, buy K3):
- Pay ask for K1 and K3 (buying)
- Receive bid for K2 (selling 2×)

# Arguments
- `market_surface`: MarketVolSurface with market data
- `heston_inputs`: HestonInputs with calibrated parameters
- `pricing_method`: Pricing method (e.g., CarrMadan)
- `rate`: Risk-free rate
- `iv_config`: Dict with IV solver settings
- `thresholds`: Named tuple with (price_abs_threshold, price_rel_threshold)

# Returns
Vector of ButterflySpread objects flagged as mispriced
"""
function detect_butterfly_mispricings(market_surface, heston_inputs, pricing_method, 
                                     rate, iv_config, thresholds)
    reference_date = Dates.epochms2datetime(market_surface.reference_date)
    
    # Store quotes by key for bid/ask access
    quotes_dict = Dict()
    model_prices = Dict()
    
    for q in market_surface.quotes
        key = (q.payoff.expiry, q.payoff.strike, isa(q.payoff.call_put, Call) ? "Call" : "Put")
        quotes_dict[key] = q
        model_prices[key] = solve(PricingProblem(q.payoff, heston_inputs), pricing_method).price
    end
    
    # Group options by expiry and type
    grouped = Dict()
    for q in market_surface.quotes
        exp = q.payoff.expiry
        typ = isa(q.payoff.call_put, Call) ? "Call" : "Put"
        key = (exp, typ)
        if !haskey(grouped, key)
            grouped[key] = []
        end
        push!(grouped[key], q.payoff.strike)
    end
    
    # Find butterflies
    butterflies = ButterflySpread[]
    
    for ((exp, typ), strikes) in grouped
        strikes_sorted = sort(unique(strikes))
        n = length(strikes_sorted)
        
        # Need at least 3 strikes
        if n < 3
            continue
        end
        
        # Try all combinations of 3 strikes
        for i in 1:(n-2)
            for j in (i+1):(n-1)
                for k in (j+1):n
                    K1 = strikes_sorted[i]
                    K2 = strikes_sorted[j]
                    K3 = strikes_sorted[k]
                    
                    # Check if all options exist
                    key1 = (exp, K1, typ)
                    key2 = (exp, K2, typ)
                    key3 = (exp, K3, typ)
                    
                    if haskey(quotes_dict, key1) && 
                       haskey(quotes_dict, key2) && 
                       haskey(quotes_dict, key3)
                        
                        # Get quotes for bid/ask access
                        q1 = quotes_dict[key1]
                        q2 = quotes_dict[key2]
                        q3 = quotes_dict[key3]
                        
                        # Calculate butterfly with bid-ask spread
                        # Long butterfly: buy K1 (pay ask), sell 2×K2 (receive bid), buy K3 (pay ask)
                        price_K1_buy = get_execution_price(q1, :buy)    # Pay ask
                        price_K2_sell = get_execution_price(q2, :sell)  # Receive bid
                        price_K3_buy = get_execution_price(q3, :buy)    # Pay ask
                        
                        market_bf_long = price_K1_buy - 2*price_K2_sell + price_K3_buy
                        
                        # Short butterfly: sell K1 (receive bid), buy 2×K2 (pay ask), sell K3 (receive bid)
                        price_K1_sell = get_execution_price(q1, :sell)  # Receive bid
                        price_K2_buy = get_execution_price(q2, :buy)    # Pay ask
                        price_K3_sell = get_execution_price(q3, :sell)  # Receive bid
                        
                        # Short butterfly cost = -(bid_K1 - 2*ask_K2 + bid_K3)
                        # = -bid_K1 + 2*ask_K2 - bid_K3
                        market_bf_short = -price_K1_sell + 2*price_K2_buy - price_K3_sell
                        
                        # Model butterfly (no spread)
                        model_bf = model_prices[key1] - 2*model_prices[key2] + model_prices[key3]
                        
                        # Check if LONG butterfly is profitable
                        # Underpriced: model > market_long (buy opportunity)
                        if market_bf_long > 1.0  # Must be positive cost
                            price_error_long = model_bf - market_bf_long
                            rel_error_long = price_error_long / market_bf_long
                            
                            underpriced = (price_error_long > 0) && 
                                        (abs(price_error_long) >= thresholds.price_abs_threshold || 
                                         abs(rel_error_long) >= thresholds.price_rel_threshold)
                            
                            if underpriced
                                push!(butterflies, ButterflySpread(
                                    Date(Dates.epochms2datetime(exp)),
                                    exp,
                                    K1, K2, K3,
                                    typ,
                                    price_K1_buy, price_K2_sell, price_K3_buy,
                                    market_bf_long,
                                    model_prices[key1], model_prices[key2], model_prices[key3],
                                    model_bf,
                                    price_error_long,
                                    rel_error_long,
                                    true,   # underpriced
                                    false   # not overpriced
                                ))
                            end
                        end
                        
                        # Check if SHORT butterfly is profitable
                        # Overpriced: model < market_short (sell opportunity)
                        if market_bf_short > 1.0  # Cost to establish short position
                            price_error_short = model_bf - market_bf_short
                            rel_error_short = price_error_short / market_bf_short
                            
                            overpriced = (price_error_short < 0) && 
                                       (abs(price_error_short) >= thresholds.price_abs_threshold || 
                                        abs(rel_error_short) >= thresholds.price_rel_threshold)
                            
                            if overpriced
                                push!(butterflies, ButterflySpread(
                                    Date(Dates.epochms2datetime(exp)),
                                    exp,
                                    K1, K2, K3,
                                    typ,
                                    price_K1_sell, price_K2_buy, price_K3_sell,
                                    market_bf_short,
                                    model_prices[key1], model_prices[key2], model_prices[key3],
                                    model_bf,
                                    price_error_short,
                                    rel_error_short,
                                    false,  # not underpriced
                                    true    # overpriced
                                ))
                            end
                        end
                    end
                end
            end
        end
    end
    
    return butterflies
end

"""
    load_tracking_snapshots(initial_time, base_path, underlying, rate, 
                           filter_params, selection_mode)
    -> Vector{Tuple{DateTime, MarketVolSurface}}

Load market data snapshots for butterfly tracking (next 2 hours in 15-min intervals).
"""
function load_tracking_snapshots(initial_time, base_path, underlying, rate,
                                filter_params, selection_mode)
    snapshots = Tuple{DateTime, Any}[]
    
    # Track for 2 hours in 15-minute intervals
    tracking_times = [initial_time + Minute(15*i) for i in 1:8]
    
    println("\n  Loading $(length(tracking_times)) market snapshots for reversion tracking...")
    for (idx, target_time) in enumerate(tracking_times)
        try
            date_str = Dates.format(Date(target_time), dateformat"yyyy-mm-dd")
            time_str = Dates.format(Time(target_time), dateformat"HH:MM:SS")
            
            mkt_surface, _ = load_market_data(
                base_path, date_str, underlying, time_str, rate, filter_params;
                selection=selection_mode
            )
            
            push!(snapshots, (target_time, mkt_surface))
            print("\r    Loaded snapshot $idx/$(length(tracking_times)) @ $(time_str)...")
        catch e
            @warn "Failed to load data at $(target_time): $e"
        end
    end
    println("\r  ✓ Loaded $(length(snapshots))/$(length(tracking_times)) snapshots successfully")
    
    return snapshots
end

"""
    track_butterfly_reversion(butterfly, initial_time, market_snapshots, min_gain_threshold)
    -> ButterflyReversion

Track a butterfly spread using pre-loaded market snapshots to see if price reverts.
Uses bid/ask prices for realistic gain calculations.
"""
function track_butterfly_reversion(butterfly, initial_time, market_snapshots, min_gain_threshold)
    
    reversion_times = DateTime[]
    reversion_market_prices = Float64[]
    reversion_gains = Float64[]
    
    for (snapshot_time, mkt_surface) in market_snapshots
        # Find butterfly components in this snapshot
        opts = Dict()
        for q in mkt_surface.quotes
            if q.payoff.expiry == butterfly.expiry_ts
                key = (q.payoff.strike, isa(q.payoff.call_put, Call) ? "Call" : "Put")
                opts[key] = q
            end
        end
        
        # Check if all components still exist
        key1 = (butterfly.K1, butterfly.option_type)
        key2 = (butterfly.K2, butterfly.option_type)
        key3 = (butterfly.K3, butterfly.option_type)
        
        if haskey(opts, key1) && haskey(opts, key2) && haskey(opts, key3)
            
            # Calculate current butterfly price with bid-ask
            # To close position, we reverse the trades
            if butterfly.underpriced
                # Opened long: bought K1, sold 2×K2, bought K3
                # Close: sell K1 (bid), buy 2×K2 (ask), sell K3 (bid)
                close_K1 = get_execution_price(opts[key1], :sell)
                close_K2 = get_execution_price(opts[key2], :buy)
                close_K3 = get_execution_price(opts[key3], :sell)
                current_bf_value = close_K1 - 2*close_K2 + close_K3
                
                # Gain = (close value - open cost) / open cost
                gain = (current_bf_value - butterfly.market_butterfly_price) / 
                       butterfly.market_butterfly_price
            else  # overpriced (short position)
                # Opened short: sold K1, bought 2×K2, sold K3
                # Close: buy K1 (ask), sell 2×K2 (bid), buy K3 (ask)
                close_K1 = get_execution_price(opts[key1], :buy)
                close_K2 = get_execution_price(opts[key2], :sell)
                close_K3 = get_execution_price(opts[key3], :buy)
                current_bf_cost = close_K1 - 2*close_K2 + close_K3
                
                # Gain = (open proceeds - close cost) / open proceeds
                # Note: for short, butterfly.market_butterfly_price is the cost to open
                gain = (butterfly.market_butterfly_price - current_bf_cost) / 
                       butterfly.market_butterfly_price
            end
            
            push!(reversion_times, snapshot_time)
            push!(reversion_market_prices, current_bf_value)
            push!(reversion_gains, gain)
        end
    end
    
    # Analyze reversion
    reverted = false
    time_to_reversion = nothing
    max_gain = isempty(reversion_gains) ? 0.0 : maximum(reversion_gains)
    final_gain = isempty(reversion_gains) ? 0.0 : reversion_gains[end]
    
    for (i, gain) in enumerate(reversion_gains)
        if gain >= min_gain_threshold
            reverted = true
            time_to_reversion = reversion_times[i] - initial_time
            break
        end
    end
    
    return ButterflyReversion(
        butterfly,
        initial_time,
        butterfly.market_butterfly_price,
        butterfly.model_butterfly_price,
        butterfly.price_error,
        reversion_times,
        reversion_market_prices,
        reversion_gains,
        reverted,
        time_to_reversion,
        max_gain,
        final_gain
    )
end

"""
    butterflies_to_dataframe(butterflies::Vector{ButterflySpread}) -> DataFrame
"""
function butterflies_to_dataframe(butterflies::Vector{ButterflySpread})
    return DataFrame(
        expiry_date = [b.expiry_date for b in butterflies],
        K1 = [b.K1 for b in butterflies],
        K2 = [b.K2 for b in butterflies],
        K3 = [b.K3 for b in butterflies],
        option_type = [b.option_type for b in butterflies],
        market_price = [b.market_butterfly_price for b in butterflies],
        model_price = [b.model_butterfly_price for b in butterflies],
        price_error = [b.price_error for b in butterflies],
        rel_price_error = [b.rel_price_error for b in butterflies],
        underpriced = [b.underpriced for b in butterflies],
        overpriced = [b.overpriced for b in butterflies]
    )
end

"""
    reversions_to_dataframe(reversions::Vector{ButterflyReversion}) -> DataFrame
"""
function reversions_to_dataframe(reversions::Vector{ButterflyReversion})
    return DataFrame(
        expiry_date = [r.butterfly.expiry_date for r in reversions],
        K1 = [r.butterfly.K1 for r in reversions],
        K2 = [r.butterfly.K2 for r in reversions],
        K3 = [r.butterfly.K3 for r in reversions],
        option_type = [r.butterfly.option_type for r in reversions],
        direction = [r.butterfly.underpriced ? "Long" : "Short" for r in reversions],
        initial_market = [r.initial_market_price for r in reversions],
        initial_model = [r.initial_model_price for r in reversions],
        initial_error = [r.initial_error for r in reversions],
        reverted = [r.reverted for r in reversions],
        time_to_reversion = [r.time_to_reversion === nothing ? missing : 
                            Dates.value(r.time_to_reversion) ÷ 60000 for r in reversions],  # minutes
        max_gain_pct = [r.max_gain * 100 for r in reversions],
        final_gain_pct = [r.final_gain * 100 for r in reversions]
    )
end

"""
    save_butterfly_analysis(butterflies, reversions, output_dir)

Save butterfly analysis results to CSV files.
"""
function save_butterfly_analysis(butterflies, reversions, output_dir)
    # Save detected butterflies
    bf_df = butterflies_to_dataframe(butterflies)
    CSV.write(joinpath(output_dir, "mispriced_butterflies.csv"), bf_df)
    println("✓ Mispriced butterflies saved to: $(joinpath(output_dir, "mispriced_butterflies.csv"))")
    
    # Save reversion tracking
    if !isempty(reversions)
        rev_df = reversions_to_dataframe(reversions)
        CSV.write(joinpath(output_dir, "butterfly_reversions.csv"), rev_df)
        println("✓ Reversion tracking saved to: $(joinpath(output_dir, "butterfly_reversions.csv"))")
    end
end

"""
    print_butterfly_summary(butterflies, reversions, min_gain_threshold)

Print summary statistics of butterfly analysis.
"""
function print_butterfly_summary(butterflies, reversions, min_gain_threshold)
    println("\nButterfly Analysis Summary:")
    println("="^70)
    println("Total butterflies detected: $(length(butterflies))")
    println("  Underpriced (long): $(count(b -> b.underpriced, butterflies))")
    println("  Overpriced (short): $(count(b -> b.overpriced, butterflies))")
    
    if !isempty(reversions)
        reverted = count(r -> r.reverted, reversions)
        println("\nReversion Analysis (threshold: $(min_gain_threshold*100)%):")
        println("  Tracked: $(length(reversions))")
        println("  Reverted: $reverted ($(round(reverted/length(reversions)*100, digits=1))%)")
        println("  Did not revert: $(length(reversions) - reverted)")
        
        if reverted > 0
            rev_times = [Dates.value(r.time_to_reversion) ÷ 60000 
                        for r in reversions if r.reverted]
            println("  Avg time to reversion: $(round(mean(rev_times), digits=1)) minutes")
        end
        
        println("\nGain Statistics:")
        println("  Max gains: $(round(maximum(r.max_gain for r in reversions) * 100, digits=2))%")
        println("  Avg max gain: $(round(mean(r.max_gain for r in reversions) * 100, digits=2))%")
        println("  Avg final gain: $(round(mean(r.final_gain for r in reversions) * 100, digits=2))%")
    end
    println("="^70)
end