# single_calibration.jl
using Revise
using Dates
using Printf
using Statistics
using Hedgehog
using Deribit
using DataFrames
using CSV
using Plots

function save_iv_surface_heston_vs_market_scatter(calib_stats::FitStatistics, out_path; 
                                                   camera=(30,30))
    # Extract data directly from FitStatistics
    quotes = calib_stats.quotes
    market_vols = calib_stats.market_vols .* 100  # Convert to percentage
    heston_vols = calib_stats.heston_vols .* 100  # Convert to percentage
    
    # Extract strikes, expiries (in years), and option types
    strikes = [q.payoff.strike for q in quotes]
    expiries_ticks = [q.payoff.expiry for q in quotes]
    ref_ticks = Dates.datetime2epochms(calib_stats.reference_date)
                
    expiries_yf = [yearfrac(ref_ticks, t) for t in expiries_ticks]
    
    # Create 3D scatter plot
    plt = plot(
        title = "Implied Vol: Heston vs Market",
        xlabel = "Strike", 
        ylabel = "Maturity (years)", 
        zlabel = "IV (%)",
        legend = :topright,
        camera = camera
    )
    
    # Plot market quotes
    scatter3d!(plt, strikes, expiries_yf, market_vols; 
              ms=4, label="Market", color=:blue, alpha=0.7)
    
    # Plot Heston quotes at same points
    scatter3d!(plt, strikes, expiries_yf, heston_vols; 
              ms=4, label="Heston", color=:red, alpha=0.7)
    
    savefig(plt, out_path)
    println("✓ 3D IV scatter saved to: $out_path")
end

# ----------------------------
# Script
# ----------------------------
println("="^70)
println("Deribit $(uppercase(get(ENV, "ASSET", "BTC"))) Options: Heston Calibration & Validation")
println("="^70)

# 1) Load config
config_path = joinpath(@__DIR__, "config.yaml")
config = load_config(config_path)

run_folder = create_run_folder(@__DIR__, "heston_calib")
save_config_copy(config_path, run_folder)

base_path     = config["data"]["base_path"]
underlying    = config["data"]["underlying"]
calib_date    = config["calibration"]["date"]
calib_time    = get(config["calibration"], "time_filter", nothing)
rate          = config["market"]["risk_free_rate"]

filter_params = extract_filter_params(config)
iv_config     = extract_iv_config(config)
calib_cfg     = extract_calibration_config(config)
selection_mode = get_selection_mode(config)
pricing_method = get_pricing_method(config)

# 2) Load calibration data (single period)
println("\n[1] Loading calibration data...")
calib_surface, calib_file = load_market_data(
    base_path, calib_date, underlying, calib_time, rate, filter_params; selection=selection_mode
)

# Filter out puts - keep only calls
println("\n[1b] Filtering out puts, keeping only calls...")
call_quotes = filter(q -> isa(q.payoff.call_put, Call), calib_surface.quotes)
calib_surface = MarketVolSurface(
    Dates.epochms2datetime(calib_surface.reference_date),
    call_quotes;
    metadata=calib_surface.metadata
)
println("After filtering: $(length(calib_surface.quotes)) calls remaining")

println("\nCalibration Data Summary:")
summary(calib_surface)

# 3) Calibrate Heston
println("\n[2] Calibrating Heston model...")

# Infer spot from shortest maturity forwards
expiries = unique(q.payoff.expiry for q in calib_surface.quotes)
Tmin = minimum(expiries)
fwd_bucket = [q.forward for q in calib_surface.quotes if q.payoff.expiry == Tmin]
spot = median(fwd_bucket)

calib_result = Deribit.calibrate_heston(
    calib_surface, 
    0.0, 
    calib_cfg.initial_params;
    spot_override=spot,
    lb=calib_cfg.lower_bounds,
    ub=calib_cfg.upper_bounds
)

print_calibration_summary(calib_result)

# Save parameters
save_calibration_params(
    calib_result,
    joinpath(run_folder, "calibrated_parameters.txt");
    calib_date=calib_date,
    calib_file=basename(calib_file)
)

# 4) Compute goodness-of-fit on calibration data
println("\n[3] Evaluating fit on calibration data...")
heston_inputs = to_heston_inputs(calib_result)

calib_stats = compute_fit_statistics(
    calib_surface,
    heston_inputs,
    pricing_method,
    rate,
    iv_config;
    validation_name="Calibration"
)

print_fit_summary(calib_stats)

# Save CSVs
save_fit_summary_csv([calib_stats], joinpath(run_folder, "validation_summary.csv"))
save_fit_detailed_csv(calib_stats, joinpath(run_folder, "detailed_calibration.csv"))

# 5) Plot & save
png_path = joinpath(run_folder, "iv_surfaces_3d.png")
save_iv_surface_heston_vs_market_scatter(calib_stats, png_path)

println("\n" * "="^70)
println("Single Calibration Complete!")
println("="^70)
println("Results saved to: $run_folder")

function save_iv_slices_by_maturity(calib_stats::FitStatistics, out_path)
    quotes = calib_stats.quotes
    market_vols = calib_stats.market_vols .* 100
    heston_vols = calib_stats.heston_vols .* 100
    
    # Group by expiry
    expiry_groups = Dict()
    for (i, q) in enumerate(quotes)
        exp = q.payoff.expiry
        if !haskey(expiry_groups, exp)
            expiry_groups[exp] = (strikes=Float64[], market=Float64[], heston=Float64[], forward=Float64[])
        end
        push!(expiry_groups[exp].strikes, q.payoff.strike)
        push!(expiry_groups[exp].market, market_vols[i])
        push!(expiry_groups[exp].heston, heston_vols[i])
        push!(expiry_groups[exp].forward, q.forward)
    end
    
    # Sort expiries
    sorted_expiries = sort(collect(keys(expiry_groups)))
    n_expiries = length(sorted_expiries)
    
    # Determine grid layout
    ncols = 3
    nrows = ceil(Int, n_expiries / ncols)
    
    # Create subplots
    ref_ticks = Dates.datetime2epochms(calib_stats.reference_date)
    plots = []
    
    for exp in sorted_expiries
        data = expiry_groups[exp]
        
        # Sort by strike for line plots
        sort_idx = sortperm(data.strikes)
        K = data.strikes[sort_idx]
        mkt = data.market[sort_idx]
        hst = data.heston[sort_idx]
        fwd = median(data.forward[sort_idx])  # Use median forward for this maturity
        
        # Convert to log-moneyness for better visualization
        log_moneyness = log.(K ./ fwd)
        
        # Format expiry label
        exp_dt = Dates.epochms2datetime(exp)
        ttm = yearfrac(ref_ticks, exp)
        label = "T=$(round(ttm, digits=2))y\n$(Dates.format(exp_dt, "dd-mmm"))"
        
        # Calculate RMSE for this maturity
        rmse = sqrt(mean((mkt .- hst).^2))
        
        # Create subplot with log-moneyness
        p = plot(log_moneyness, mkt, 
                 label="Market", 
                 marker=:circle, 
                 markersize=4,
                 linewidth=2,
                 color=:blue,
                 xlabel="Log-moneyness",
                 ylabel="IV (%)",
                 title="$label\nRMSE=$(round(rmse, digits=2))pp",
                 legend=:best,
                 titlefontsize=9)
        
        plot!(p, log_moneyness, hst,
              label="Heston",
              marker=:circle,
              markersize=4, 
              linewidth=2,
              color=:red,
              linestyle=:dash)
        
        # Add vertical line at ATM
        vline!(p, [0.0], color=:gray, linestyle=:dot, label="ATM", alpha=0.5)
        
        push!(plots, p)
    end
    
    # Combine into grid
    combined = plot(plots..., 
                    layout=(nrows, ncols),
                    size=(400*ncols, 300*nrows),
                    plot_title="IV Fit by Maturity (Log-Moneyness)")
    
    savefig(combined, out_path)
    println("✓ IV slices saved to: $out_path")
end

# 5) Plot & save
png_path = joinpath(run_folder, "iv_surfaces_3d.png")
save_iv_surface_heston_vs_market_scatter(calib_stats, png_path)

# 6) Plot maturity slices
slices_path = joinpath(run_folder, "iv_slices_by_maturity.png")
save_iv_slices_by_maturity(calib_stats, slices_path)