using Revise, Hedgehog
using DataFrames
using Parquet2
using Plots
using Statistics
using Printf
using Dates
using Glob

println("="^80)
println("Deribit BTC Options: Heston Fit Quality Check Across Snapshots")
println("="^80)

# =====================================================================
# CONFIGURATION
# =====================================================================

DATA_DIR = joinpath(@__DIR__, "..", "data")
RATE = 0.03

# Heston parameters to test (calibrated values)
HESTON_PARAMS = (
    v0 = 0.223997,   # Initial variance (47.33% vol)
    κ  = 73.546046,  # Mean reversion speed
    θ  = 0.238486,   # Long-term variance (48.84% vol)
    σ  = 10.901266,  # Vol of vol
    ρ  = -0.244233   # Correlation
)

FILTER_PARAMS = (
    min_days=100,
    max_years=2.0,
    min_moneyness=0.8,
    max_moneyness=1.2
)

# =====================================================================
# HELPER FUNCTIONS
# =====================================================================

"""Extract timestamp from filename like 'batch_20251019-152024271068.parquet'"""
function extract_timestamp(filename::String)
    m = match(r"batch_(\d{8})-(\d{15})", basename(filename))
    if m === nothing
        return nothing
    end
    datestr, timestr = m.captures
    year = parse(Int, datestr[1:4])
    month = parse(Int, datestr[5:6])
    day = parse(Int, datestr[7:8])
    hour = parse(Int, timestr[1:2])
    minute = parse(Int, timestr[3:4])
    second = parse(Int, timestr[5:6])
    
    return DateTime(year, month, day, hour, minute, second)
end

"""Calculate comprehensive fit metrics"""
function calculate_fit_metrics(market_surface, heston_inputs, pricing_method)
    reference_date = Dates.epochms2datetime(market_surface.reference_date)
    spot = market_surface.spot
    
    # Market data
    market_vols = [q.implied_vol for q in market_surface.quotes]
    market_prices = [q.price for q in market_surface.quotes]
    
    # Heston prices
    println("    Pricing $(length(market_surface.quotes)) options with Heston...")
    heston_prices = [
        solve(PricingProblem(q.payoff, heston_inputs), pricing_method).price
        for q in market_surface.quotes
    ]
    
    # Price errors
    price_errors = heston_prices .- market_prices
    abs_price_errors = abs.(price_errors)
    rel_price_errors = abs_price_errors ./ market_prices .* 100
    
    # Back out implied vols from Heston prices
    println("    Computing implied vols from Heston prices...")
    heston_vols = Float64[]
    for (i, quoten) in enumerate(market_surface.quotes)
        dummy_inputs = BlackScholesInputs(reference_date, RATE, spot, 0.5)
        basket = BasketPricingProblem([quoten.payoff], dummy_inputs)
        
        calib = CalibrationProblem(
            basket,
            BlackScholesAnalytic(),
            [VolLens(1,1)],
            [heston_prices[i]],
            [0.5]
        )
        
        try
            heston_vol = solve(calib, RootFinderAlgo()).u
            push!(heston_vols, heston_vol)
        catch e
            push!(heston_vols, NaN)
        end
    end
    
    # Vol errors (in percentage points)
    vol_errors = (heston_vols .- market_vols) .* 100
    abs_vol_errors = abs.(vol_errors)
    
    # Filter out NaN values for statistics
    valid_idx = .!isnan.(heston_vols)
    n_valid = sum(valid_idx)
    
    return (
        n_options = length(market_surface.quotes),
        n_valid = n_valid,
        spot = spot,
        price_mae = mean(abs_price_errors),
        price_rmse = sqrt(mean(price_errors.^2)),
        price_max_abs = maximum(abs_price_errors),
        price_mean_rel = mean(rel_price_errors),
        price_max_rel = maximum(rel_price_errors),
        vol_mae = n_valid > 0 ? mean(abs_vol_errors[valid_idx]) : NaN,
        vol_rmse = n_valid > 0 ? sqrt(mean(vol_errors[valid_idx].^2)) : NaN,
        vol_max_abs = n_valid > 0 ? maximum(abs_vol_errors[valid_idx]) : NaN,
        market_vols = market_vols,
        heston_vols = heston_vols,
        vol_errors = vol_errors,
        market_prices = market_prices,
        heston_prices = heston_prices,
        quotes = market_surface.quotes,
        reference_date = reference_date
    )
end

"""Print worst fits"""
function print_worst_fits(metrics, n=5)
    valid_idx = .!isnan.(metrics.heston_vols)
    if sum(valid_idx) == 0
        println("  No valid fits to display")
        return
    end
    
    abs_vol_errors = abs.(metrics.vol_errors)
    sorted_indices = sortperm(abs_vol_errors, rev=true)
    
    # Filter to valid only
    valid_sorted = [i for i in sorted_indices if valid_idx[i]]
    n_show = min(n, length(valid_sorted))
    
    println("\nWorst $n_show fits by volatility error:")
    println("Strike | Expiry(Y) | Type | Market Vol | Heston Vol | Error")
    println("-------|-----------|------|------------|------------|-------")
    
    for idx in valid_sorted[1:n_show]
        quoten = metrics.quotes[idx]
        expiry_date = Date(Dates.epochms2datetime(quoten.payoff.expiry))
        years = yearfrac(Date(metrics.reference_date), expiry_date)
        cp_str = isa(quoten.payoff.call_put, Call) ? "Call" : "Put "
        
        @printf("%7.0f | %9.2f | %s | %9.2f%% | %9.2f%% | %+6.2f%%\n",
                quoten.payoff.strike, years, cp_str,
                metrics.market_vols[idx] * 100, 
                metrics.heston_vols[idx] * 100, 
                metrics.vol_errors[idx])
    end
end

# =====================================================================
# MAIN WORKFLOW
# =====================================================================

# Find all parquet files
parquet_files = sort(glob("batch_*.parquet", DATA_DIR))

if isempty(parquet_files)
    error("No parquet files found in $DATA_DIR with pattern 'batch_*.parquet'")
end

println("\n[INFO] Found $(length(parquet_files)) snapshot files")
println("\n[INFO] Testing Heston parameters:")
@printf("  v₀ = %.6f (%.2f%% vol)\n", HESTON_PARAMS.v0, sqrt(HESTON_PARAMS.v0)*100)
@printf("  κ  = %.6f\n", HESTON_PARAMS.κ)
@printf("  θ  = %.6f (%.2f%% vol)\n", HESTON_PARAMS.θ, sqrt(HESTON_PARAMS.θ)*100)
@printf("  σ  = %.6f\n", HESTON_PARAMS.σ)
@printf("  ρ  = %.6f\n", HESTON_PARAMS.ρ)

# Pricing method
pricing_method = CarrMadan(1.0, 32.0, HestonDynamics())

# =====================================================================
# PROCESS ALL SNAPSHOTS
# =====================================================================

println("\n" * "="^80)
println("PROCESSING SNAPSHOTS")
println("="^80)

all_results = []

for (idx, filepath) in enumerate(parquet_files)
    timestamp = extract_timestamp(filepath)
    println("\n[$idx/$(length(parquet_files))] $(basename(filepath))")
    println("  Timestamp: $timestamp")
    
    # Load surface
    println("  Loading market data...")
    surface = load_deribit_parquet(
        filepath,
        rate=RATE,
        filter_params=FILTER_PARAMS
    )
    println("    Spot: $(surface.spot)")
    println("    Options: $(length(surface.quotes))")
    
    # Build Heston inputs for this snapshot
    reference_date = Dates.epochms2datetime(surface.reference_date)
    heston_inputs = HestonInputs(
        reference_date,
        RATE,
        surface.spot,
        HESTON_PARAMS.v0,
        HESTON_PARAMS.κ,
        HESTON_PARAMS.θ,
        HESTON_PARAMS.σ,
        HESTON_PARAMS.ρ
    )
    
    # Calculate fit metrics
    metrics = calculate_fit_metrics(surface, heston_inputs, pricing_method)
    
    # Print summary
    println("\n  Fit Quality:")
    @printf("    Price MAE:     \$%.4f\n", metrics.price_mae)
    @printf("    Price RMSE:    \$%.4f\n", metrics.price_rmse)
    @printf("    Price Max Err: \$%.4f\n", metrics.price_max_abs)
    @printf("    Vol MAE:       %.2f%% pts\n", metrics.vol_mae)
    @printf("    Vol RMSE:      %.2f%% pts\n", metrics.vol_rmse)
    @printf("    Vol Max Err:   %.2f%% pts\n", metrics.vol_max_abs)
    
    # Store results
    push!(all_results, (
        filename = basename(filepath),
        timestamp = timestamp,
        spot = metrics.spot,
        n_options = metrics.n_options,
        n_valid = metrics.n_valid,
        price_mae = metrics.price_mae,
        price_rmse = metrics.price_rmse,
        price_max_abs = metrics.price_max_abs,
        price_mean_rel = metrics.price_mean_rel,
        vol_mae = metrics.vol_mae,
        vol_rmse = metrics.vol_rmse,
        vol_max_abs = metrics.vol_max_abs,
        metrics = metrics
    ))
end

# =====================================================================
# SUMMARY REPORT
# =====================================================================

println("\n" * "="^80)
println("SUMMARY ACROSS ALL SNAPSHOTS")
println("="^80)

# Create summary table
println("\n" * "-"^120)
println(@sprintf("%-25s | %10s | %8s | %12s | %12s | %12s | %10s | %10s | %10s",
    "Timestamp", "Spot", "Options", "Price MAE", "Price RMSE", "Price MaxE", 
    "Vol MAE", "Vol RMSE", "Vol MaxE"))
println("-"^120)

for result in all_results
    println(@sprintf("%-25s | %10.2f | %8d | \$%10.4f | \$%10.4f | \$%10.4f | %9.2f%% | %9.2f%% | %9.2f%%",
        result.timestamp,
        result.spot,
        result.n_options,
        result.price_mae,
        result.price_rmse,
        result.price_max_abs,
        result.vol_mae,
        result.vol_rmse,
        result.vol_max_abs
    ))
end
println("-"^120)

# Aggregate statistics
valid_results = [r for r in all_results if !isnan(r.vol_mae)]

if !isempty(valid_results)
    println("\nAGGREGATE STATISTICS:")
    println("  Average Price MAE:     \$$(round(mean([r.price_mae for r in valid_results]), digits=4))")
    println("  Average Price RMSE:    \$$(round(mean([r.price_rmse for r in valid_results]), digits=4))")
    println("  Average Vol MAE:       $(round(mean([r.vol_mae for r in valid_results]), digits=2))% pts")
    println("  Average Vol RMSE:      $(round(mean([r.vol_rmse for r in valid_results]), digits=2))% pts")
    println("  Worst Price MAE:       \$$(round(maximum([r.price_mae for r in valid_results]), digits=4))")
    println("  Worst Vol MAE:         $(round(maximum([r.vol_mae for r in valid_results]), digits=2))% pts")
    println("  Best Price MAE:        \$$(round(minimum([r.price_mae for r in valid_results]), digits=4))")
    println("  Best Vol MAE:          $(round(minimum([r.vol_mae for r in valid_results]), digits=2))% pts")
end

# =====================================================================
# DETAILED ANALYSIS OF WORST SNAPSHOT
# =====================================================================

if !isempty(valid_results)
    worst_idx = argmax([r.vol_rmse for r in valid_results])
    worst_result = valid_results[worst_idx]
    
    println("\n" * "="^80)
    println("DETAILED ANALYSIS: WORST SNAPSHOT")
    println("="^80)
    println("File: $(worst_result.filename)")
    println("Timestamp: $(worst_result.timestamp)")
    println("Spot: $(worst_result.spot)")
    println("Vol RMSE: $(round(worst_result.vol_rmse, digits=2))% pts")
    
    print_worst_fits(worst_result.metrics, 10)
end

# =====================================================================
# TIME SERIES PLOTS
# =====================================================================

println("\n" * "="^80)
println("CREATING PLOTS")
println("="^80)

timestamps = [r.timestamp for r in all_results]
vol_maes = [r.vol_mae for r in all_results]
vol_rmses = [r.vol_rmse for r in all_results]
price_maes = [r.price_mae for r in all_results]
spots = [r.spot for r in all_results]

p1 = plot(
    timestamps, vol_maes,
    xlabel="Time",
    ylabel="Vol MAE (% points)",
    title="Volatility Fit Quality Over Time",
    marker=:circle,
    legend=false,
    size=(800, 400)
)

p2 = plot(
    timestamps, price_maes,
    xlabel="Time",
    ylabel="Price MAE (\$)",
    title="Price Fit Quality Over Time",
    marker=:circle,
    legend=false,
    size=(800, 400),
    color=:red
)

p3 = plot(
    timestamps, spots,
    xlabel="Time",
    ylabel="BTC Spot Price",
    title="BTC Spot Price Over Time",
    marker=:circle,
    legend=false,
    size=(800, 400),
    color=:green
)

p4 = scatter(
    spots, vol_maes,
    xlabel="Spot Price",
    ylabel="Vol MAE (% points)",
    title="Fit Quality vs Spot Price",
    marker=:circle,
    legend=false,
    size=(800, 400),
    color=:purple
)

combined_plot = plot(p1, p2, p3, p4, layout=(2,2), size=(1600, 800))

output_path = joinpath(@__DIR__, "heston_fit_quality_report.png")
savefig(combined_plot, output_path)
println("\n✓ Plots saved to: $output_path")

println("\n" * "="^80)
println("ANALYSIS COMPLETE!")
println("="^80)