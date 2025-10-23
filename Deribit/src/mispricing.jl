# mispricing.jl
# Mispricing detection and island finding

using DataFrames
using Dates
using Statistics
using Printf
using CSV
using Hedgehog

"""
    MispricingRecord

Single option with mispricing analysis.
"""
struct MispricingRecord
    expiry_date::Date
    expiry_ts::Int64
    strike::Float64
    option_type::String
    spot::Float64
    
    market_price::Float64
    model_price::Float64
    price_error::Float64
    rel_price_error::Float64
    
    market_vol::Float64      # percentage (0-100)
    model_vol::Float64       # percentage (0-100)
    vol_error_pp::Float64    # percentage points
    
    # Flags
    price_abs_flag::Bool
    price_rel_flag::Bool
    vol_pp_flag::Bool
    
    underpriced_price::Bool
    overpriced_price::Bool
    underpriced_vol::Bool
    overpriced_vol::Bool
    underpriced_any::Bool
    overpriced_any::Bool
end

"""
    detect_mispricings(market_surface, heston_inputs, pricing_method, rate, iv_config, thresholds)
    -> Vector{MispricingRecord}

Detect potential mispricings by comparing model vs market prices and vols.

# Arguments
- `market_surface`: MarketVolSurface with market data
- `heston_inputs`: HestonInputs with calibrated parameters
- `pricing_method`: Pricing method (e.g., CarrMadan)
- `rate`: Risk-free rate
- `iv_config`: Dict with IV solver settings
- `thresholds`: Named tuple with (price_abs_threshold, price_rel_threshold, vol_pp_threshold)

# Returns
Vector of MispricingRecord, one per option

# Thresholds
- `price_abs_threshold`: Absolute price error threshold (currency units)
- `price_rel_threshold`: Relative price error threshold (fraction, e.g., 0.02 = 2%)
- `vol_pp_threshold`: Vol error threshold (percentage points)

# Example
```julia
thresholds = (price_abs_threshold=50.0, price_rel_threshold=0.02, vol_pp_threshold=0.5)
records = detect_mispricings(mkt, heston, method, 0.03, iv_config, thresholds)
```
"""
function detect_mispricings(market_surface, heston_inputs, pricing_method, rate, iv_config, thresholds)
    reference_date = Dates.epochms2datetime(market_surface.reference_date)
    spot = market_surface.spot
    
    market_prices = [q.price for q in market_surface.quotes]
    market_vols = [q.implied_vol for q in market_surface.quotes]
    
    # Model prices
    model_prices = [
        solve(PricingProblem(q.payoff, heston_inputs), pricing_method).price
        for q in market_surface.quotes
    ]
    
    # Back out model vols
    model_vols = Float64[]
    for (i, q) in enumerate(market_surface.quotes)
        try
            bs_inputs = BlackScholesInputs(reference_date, rate, spot, iv_config["initial_guess"])
            basket = BasketPricingProblem([q.payoff], bs_inputs)
            calib = CalibrationProblem(
                basket, BlackScholesAnalytic(),
                [VolLens(1,1)],
                [model_prices[i]],
                [iv_config["initial_guess"]];
                lb=[iv_config["lower_bound"]],
                ub=[iv_config["upper_bound"]]
            )
            push!(model_vols, solve(calib, RootFinderAlgo()).u)
        catch
            push!(model_vols, market_vols[i])
        end
    end
    
    # Errors
    price_err = model_prices .- market_prices  # >0 => market underpriced vs model
    rel_price_err = price_err ./ market_prices
    vol_err_pp = (model_vols .- market_vols) .* 100.0
    
    # Threshold flags
    price_abs_flag = abs.(price_err) .>= thresholds.price_abs_threshold
    price_rel_flag = abs.(rel_price_err) .>= thresholds.price_rel_threshold
    vol_pp_flag = abs.(vol_err_pp) .>= thresholds.vol_pp_threshold
    
    # Polarity flags
    underpriced_price = (price_err .> 0) .& (price_abs_flag .| price_rel_flag)
    overpriced_price = (price_err .< 0) .& (price_abs_flag .| price_rel_flag)
    
    underpriced_vol = (vol_err_pp .> 0) .& vol_pp_flag
    overpriced_vol = (vol_err_pp .< 0) .& vol_pp_flag
    
    underpriced_any = underpriced_price .| underpriced_vol
    overpriced_any = overpriced_price .| overpriced_vol
    
    # Build records
    records = MispricingRecord[]
    for i in 1:length(market_surface.quotes)
        q = market_surface.quotes[i]
        push!(records, MispricingRecord(
            Date(Dates.epochms2datetime(q.payoff.expiry)),
            q.payoff.expiry,
            q.payoff.strike,
            isa(q.payoff.call_put, Call) ? "Call" : "Put",
            spot,
            market_prices[i],
            model_prices[i],
            price_err[i],
            rel_price_err[i],
            market_vols[i] * 100,
            model_vols[i] * 100,
            vol_err_pp[i],
            price_abs_flag[i],
            price_rel_flag[i],
            vol_pp_flag[i],
            underpriced_price[i],
            overpriced_price[i],
            underpriced_vol[i],
            overpriced_vol[i],
            underpriced_any[i],
            overpriced_any[i]
        ))
    end
    
    return records
end

"""
    find_islands(records::Vector{MispricingRecord}; cheap_field::Symbol, rich_field::Symbol)
    -> Vector{MispricingRecord}

Find "island" mispricings: options sandwiched by opposite mispricing polarity.

An island is a point where:
- Middle point is cheap/rich
- Left neighbor is rich/cheap
- Right neighbor is rich/cheap

Options are grouped by expiry and sorted by strike.

# Arguments
- `records`: Vector of MispricingRecord
- `cheap_field`: Symbol for "cheap" flag (e.g., :underpriced_price, :underpriced_vol, :underpriced_any)
- `rich_field`: Symbol for "rich" flag (e.g., :overpriced_price, :overpriced_vol, :overpriced_any)

# Returns
Vector of MispricingRecord containing only island points

# Example
```julia
islands_price = find_islands(records; cheap_field=:underpriced_price, rich_field=:overpriced_price)
islands_vol = find_islands(records; cheap_field=:underpriced_vol, rich_field=:overpriced_vol)
islands_any = find_islands(records; cheap_field=:underpriced_any, rich_field=:overpriced_any)
```
"""
function find_islands(records::Vector{MispricingRecord}; cheap_field::Symbol, rich_field::Symbol)
    # Convert to DataFrame for groupby
    df = DataFrame(records)
    
    islands = MispricingRecord[]
    
    for sub in groupby(df, :expiry_date)
        s = sort(sub, :strike)
        n = nrow(s)
        
        if n >= 3
            for i in 2:(n-1)
                left = s[i-1, :]
                mid = s[i, :]
                right = s[i+1, :]
                
                sign_left = getproperty(left, cheap_field) ? 1 : (getproperty(left, rich_field) ? -1 : 0)
                sign_mid = getproperty(mid, cheap_field) ? 1 : (getproperty(mid, rich_field) ? -1 : 0)
                sign_right = getproperty(right, cheap_field) ? 1 : (getproperty(right, rich_field) ? -1 : 0)
                
                if sign_mid != 0 && sign_left == -sign_mid && sign_right == -sign_mid
                    push!(islands, records[s[i, :].rowid])
                end
            end
        end
    end
    
    return islands
end

"""
    records_to_dataframe(records::Vector{MispricingRecord}) -> DataFrame

Convert vector of MispricingRecord to DataFrame.
"""
function records_to_dataframe(records::Vector{MispricingRecord})
    return DataFrame(records)
end

"""
    save_mispricing_csv(records::Vector{MispricingRecord}, filepath::String)

Save mispricing records to CSV.
"""
function save_mispricing_csv(records::Vector{MispricingRecord}, filepath::String)
    df = records_to_dataframe(records)
    CSV.write(filepath, df)
    println("✓ Mispricing CSV saved to: $filepath")
end

"""
    save_islands_csvs(records::Vector{MispricingRecord}, output_dir::String)

Save island detection results to CSV files.

Creates three files:
- islands_price.csv (price-based islands)
- islands_vol.csv (vol-based islands)
- islands_combined.csv (combined islands)

# Returns
Named tuple with (islands_price, islands_vol, islands_combined)
"""
function save_islands_csvs(records::Vector{MispricingRecord}, output_dir::String)
    islands_price = find_islands(records; cheap_field=:underpriced_price, rich_field=:overpriced_price)
    islands_vol = find_islands(records; cheap_field=:underpriced_vol, rich_field=:overpriced_vol)
    islands_combined = find_islands(records; cheap_field=:underpriced_any, rich_field=:overpriced_any)
    
    CSV.write(joinpath(output_dir, "islands_price.csv"), records_to_dataframe(islands_price))
    CSV.write(joinpath(output_dir, "islands_vol.csv"), records_to_dataframe(islands_vol))
    CSV.write(joinpath(output_dir, "islands_combined.csv"), records_to_dataframe(islands_combined))
    
    println("✓ Island CSVs saved to: $output_dir")
    
    return (
        islands_price = islands_price,
        islands_vol = islands_vol,
        islands_combined = islands_combined
    )
end

"""
    print_mispricing_summary(records::Vector{MispricingRecord})

Print summary statistics of mispricing detection.
"""
function print_mispricing_summary(records::Vector{MispricingRecord})
    cheap_p = count(r -> r.underpriced_price, records)
    rich_p = count(r -> r.overpriced_price, records)
    cheap_v = count(r -> r.underpriced_vol, records)
    rich_v = count(r -> r.overpriced_vol, records)
    
    println("\nMispricing Summary:")
    @printf("  Underpriced by price: %d\n", cheap_p)
    @printf("  Overpriced by price:  %d\n", rich_p)
    @printf("  Underpriced by vol:   %d\n", cheap_v)
    @printf("  Overpriced by vol:    %d\n", rich_v)
end

"""
    print_top_mispricings(records::Vector{MispricingRecord}; k=5, by=:price_error)

Print top k mispricings by absolute error.

# Arguments
- `records`: Vector of MispricingRecord
- `k`: Number of top mispricings to show
- `by`: Sort criterion (:price_error or :vol_error_pp)
"""
function print_top_mispricings(records::Vector{MispricingRecord}; k=5, by=:price_error)
    if by == :price_error
        sorted = sort(records, by = r -> abs(r.price_error), rev=true)
        println("\nTop $k by absolute price error:")
        for (i, r) in enumerate(sorted[1:min(k, length(sorted))])
            @printf("  %2d) %s K=%.2f T=%s price_err=%9.2f rel_err=%7.2f%% vol_err_pp=%7.2f\n",
                i, r.option_type, r.strike, r.expiry_date,
                r.price_error, r.rel_price_error * 100, r.vol_error_pp)
        end
    elseif by == :vol_error_pp
        sorted = sort(records, by = r -> abs(r.vol_error_pp), rev=true)
        println("\nTop $k by absolute vol error (pp):")
        for (i, r) in enumerate(sorted[1:min(k, length(sorted))])
            @printf("  %2d) %s K=%.2f T=%s vol_err_pp=%7.2f price_err=%9.2f rel_err=%7.2f%%\n",
                i, r.option_type, r.strike, r.expiry_date,
                r.vol_error_pp, r.price_error, r.rel_price_error * 100)
        end
    end
end