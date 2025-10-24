# butterfly_analysis.jl
# Butterfly spread mispricing detection and reversion tracking

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
    
    # Market prices
    market_price_K1::Float64
    market_price_K2::Float64
    market_price_K3::Float64
    market_butterfly_price::Float64  # Net cost: P(K1) - 2*P(K2) + P(K3)
    
    # Model prices
    model_price_K1::Float64
    model_price_K2::Float64
    model_price_K3::Float64
    model_butterfly_price::Float64
    
    # Analysis
    price_error::Float64  # model - market (positive = market underpriced)
    rel_price_error::Float64  # as fraction of market price
    
    # Flags
    underpriced::Bool  # Market cheaper than model
    overpriced::Bool   # Market more expensive than model
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
    detect_butterfly_mispricings(market_surface, heston_inputs, pricing_method, rate, 
                                 iv_config, thresholds)
    -> Vector{ButterflySpread}

Detect mispriced butterfly spreads by comparing model vs market prices.

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
    
    # Get market and model prices for all options
    market_prices = Dict()
    model_prices = Dict()
    
    for q in market_surface.quotes
        key = (q.payoff.expiry, q.payoff.strike, isa(q.payoff.call_put, Call) ? "Call" : "Put")
        market_prices[key] = q.price
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
                    
                    if haskey(market_prices, key1) && 
                       haskey(market_prices, key2) && 
                       haskey(market_prices, key3)
                        
                        # Calculate butterfly prices
                        market_bf = market_prices[key1] - 2*market_prices[key2] + market_prices[key3]
                        model_bf = model_prices[key1] - 2*model_prices[key2] + model_prices[key3]
                        
                        # Skip if butterfly price is negative or too small
                        if market_bf < 1.0
                            continue
                        end
                        
                        price_error = model_bf - market_bf
                        rel_error = price_error / market_bf
                        
                        # Check thresholds
                        underpriced = (price_error > 0) && 
                                    (abs(price_error) >= thresholds.price_abs_threshold || 
                                     abs(rel_error) >= thresholds.price_rel_threshold)
                        overpriced = (price_error < 0) && 
                                   (abs(price_error) >= thresholds.price_abs_threshold || 
                                    abs(rel_error) >= thresholds.price_rel_threshold)
                        
                        if underpriced || overpriced
                            push!(butterflies, ButterflySpread(
                                Date(Dates.epochms2datetime(exp)),
                                exp,
                                K1, K2, K3,
                                typ,
                                market_prices[key1], market_prices[key2], market_prices[key3],
                                market_bf,
                                model_prices[key1], model_prices[key2], model_prices[key3],
                                model_bf,
                                price_error,
                                rel_error,
                                underpriced,
                                overpriced
                            ))
                        end
                    end
                end
            end
        end
    end
    
    return butterflies
end

"""
    track_butterfly_reversion(butterfly, initial_time, base_path, underlying, rate, 
                              filter_params, selection_mode, pricing_method, 
                              heston_inputs, min_gain_threshold)
    -> ButterflyReversion

Track a butterfly spread over the next 2 hours to see if price reverts.

# Arguments
- `butterfly`: ButterflySpread to track
- `initial_time`: DateTime of initial detection
- `base_path`: Data directory
- `underlying`: Asset symbol
- `rate`: Risk-free rate
- `filter_params`: Market data filters
- `selection_mode`: File selection mode
- `pricing_method`: Pricing method
- `heston_inputs`: Heston model inputs
- `min_gain_threshold`: Minimum gain to consider "reverted" (fraction, e.g., 0.10 = 10%)

# Returns
ButterflyReversion with tracking results
"""
function track_butterfly_reversion(butterfly, initial_time, base_path, underlying, rate,
                                   filter_params, selection_mode, pricing_method, 
                                   heston_inputs, min_gain_threshold)
    
    reversion_times = DateTime[]
    reversion_market_prices = Float64[]
    reversion_gains = Float64[]
    
    # Track for 2 hours in 15-minute intervals
    tracking_times = [initial_time + Minute(15*i) for i in 1:8]  # 15min to 2hrs
    
    for target_time in tracking_times
        try
            # Load market data at target time
            date_str = Dates.format(Date(target_time), dateformat"yyyy-mm-dd")
            time_str = Dates.format(Time(target_time), dateformat"HH:MM:SS")
            
            mkt_surface, _ = load_market_data(
                base_path, date_str, underlying, time_str, rate, filter_params;
                selection=selection_mode
            )
            
            # Find butterfly components in new snapshot
            market_prices = Dict()
            for q in mkt_surface.quotes
                if q.payoff.expiry == butterfly.expiry_ts
                    key = (q.payoff.strike, isa(q.payoff.call_put, Call) ? "Call" : "Put")
                    market_prices[key] = q.price
                end
            end
            
            # Check if all components still exist
            key1 = (butterfly.K1, butterfly.option_type)
            key2 = (butterfly.K2, butterfly.option_type)
            key3 = (butterfly.K3, butterfly.option_type)
            
            if haskey(market_prices, key1) && 
               haskey(market_prices, key2) && 
               haskey(market_prices, key3)
                
                # Calculate current butterfly price
                current_bf_price = market_prices[key1] - 2*market_prices[key2] + market_prices[key3]
                
                # Calculate gain depending on position direction
                if butterfly.underpriced
                    # We bought cheap, gain if price goes up
                    gain = (current_bf_price - butterfly.market_butterfly_price) / 
                           butterfly.market_butterfly_price
                else  # overpriced
                    # We sold expensive, gain if price goes down
                    gain = (butterfly.market_butterfly_price - current_bf_price) / 
                           butterfly.market_butterfly_price
                end
                
                push!(reversion_times, target_time)
                push!(reversion_market_prices, current_bf_price)
                push!(reversion_gains, gain)
            end
            
        catch e
            @warn "Failed to load data at $(target_time): $e"
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