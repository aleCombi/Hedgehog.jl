# analyze_butterfly_mispricings.jl
# Butterfly spread mispricing detection and reversion tracking
# Replaces: vol_arb_probe.jl (now focuses on butterflies)

using Revise, Hedgehog
using Dates: @dateformat_str
using Deribit, Dates, Printf

println("="^70)
println("Deribit BTC Options: Butterfly Mispricing & Reversion Analysis")
println("="^70)

# ===========================
# [1] Load Configuration
# ===========================

config_path = joinpath(@__DIR__, "config.yaml")
config = load_config(config_path)

# Create run folder
run_folder = create_run_folder(joinpath(@__DIR__, ".."), "butterfly_analysis")
save_config_copy(config_path, run_folder)

# Extract config sections
base_path = config["data"]["base_path"]
underlying = config["data"]["underlying"]
calib_date = config["calibration"]["date"]
calib_time = get(config["calibration"], "time_filter", nothing)
rate = config["market"]["risk_free_rate"]

filter_params = extract_filter_params(config)
iv_config = extract_iv_config(config)
calib_cfg = extract_calibration_config(config)
selection_mode = get_selection_mode(config)
pricing_method = get_pricing_method(config)

# Butterfly-specific thresholds
butterfly_thresholds = (
    price_abs_threshold = Float64(get(get(config, "butterfly", Dict()), 
                                      "price_abs_threshold", 20.0)),
    price_rel_threshold = Float64(get(get(config, "butterfly", Dict()), 
                                      "price_rel_threshold", 0.05))
)

min_gain_threshold = Float64(get(get(config, "butterfly", Dict()), 
                                 "min_gain_threshold", 0.10))

println("\nButterfly Thresholds:")
println("  Price absolute: $(butterfly_thresholds.price_abs_threshold)")
println("  Price relative: $(butterfly_thresholds.price_rel_threshold * 100)%")
println("  Min gain for reversion: $(min_gain_threshold * 100)%")

# ===========================
# [2] Load Calibration Snapshot
# ===========================

println("\n[1] Loading calibration snapshot...")
mkt_surface, parquet_file = load_market_data(
    base_path, calib_date, underlying, calib_time, rate, filter_params;
    selection=selection_mode
)

println("\nCalibration Data Summary:")
summary(mkt_surface)

initial_time = Dates.epochms2datetime(mkt_surface.reference_date)

# ===========================
# [3] Calibrate Heston
# ===========================

println("\n[2] Calibrating Heston model...")
calib_result = Deribit.calibrate_heston(
    mkt_surface,
    rate,
    calib_cfg.initial_params;
    lb=calib_cfg.lower_bounds,
    ub=calib_cfg.upper_bounds,
    parquet_file=parquet_file
)

print_calibration_summary(calib_result)

# Save parameters
save_calibration_params(
    calib_result,
    joinpath(run_folder, "calibrated_parameters.txt");
    calib_date=calib_date,
    calib_file=basename(parquet_file)
)

# Create HestonInputs for pricing
heston_inputs = to_heston_inputs(calib_result)

# ===========================
# [4] Detect Mispriced Butterflies
# ===========================

println("\n[3] Detecting mispriced butterfly spreads...")
butterflies = Deribit.detect_butterfly_mispricings(
    mkt_surface,
    heston_inputs,
    pricing_method,
    rate,
    iv_config,
    butterfly_thresholds
)

println("Found $(length(butterflies)) mispriced butterflies")
println("  Underpriced (long): $(count(b -> b.underpriced, butterflies))")
println("  Overpriced (short): $(count(b -> b.overpriced, butterflies))")

if isempty(butterflies)
    println("\nNo mispriced butterflies found with current thresholds.")
    println("Consider adjusting thresholds in config.yaml")
    exit(0)
end

# ===========================
# [5] Track Reversion
# ===========================

println("\n[4] Tracking butterfly reversion over next 2 hours...")
println("This will take some time as it loads multiple market snapshots...")

reversions = ButterflyReversion[]

for (i, butterfly) in enumerate(butterflies)
    print("\r  Processing butterfly $i/$(length(butterflies))...")
        reversion = Deribit.track_butterfly_reversion(
        butterfly,
        initial_time,
        base_path,
        underlying,
        rate,
        filter_params,
        selection_mode,
        pricing_method,
        heston_inputs,
        min_gain_threshold
    )
    push!(reversions, reversion)
end
println("\r  Completed tracking $(length(reversions)) butterflies")

# ===========================
# [6] Save Results
# ===========================

println("\n[5] Saving results...")

save_butterfly_analysis(butterflies, reversions, run_folder)

# ===========================
# [7] Display Summary
# ===========================

print_butterfly_summary(butterflies, reversions, min_gain_threshold)

# Show top opportunities
println("\nTop 10 Butterflies by Absolute Price Error:")
sorted_bf = sort(butterflies, by = b -> abs(b.price_error), rev=true)
for (i, bf) in enumerate(sorted_bf[1:min(10, length(sorted_bf))])
    direction = bf.underpriced ? "LONG" : "SHORT"
    @printf("  %2d) %s %s [%.0f/%.0f/%.0f] exp=%s  error=\$%.2f (%.1f%%)\n",
        i, direction, bf.option_type, bf.K1, bf.K2, bf.K3, bf.expiry_date,
        bf.price_error, bf.rel_price_error * 100)
end

# Show best performing reversions
if !isempty(reversions)
    println("\nTop 10 Reversions by Max Gain:")
    sorted_rev = sort(reversions, by = r -> r.max_gain, rev=true)
    for (i, rev) in enumerate(sorted_rev[1:min(10, length(sorted_rev))])
        bf = rev.butterfly
        direction = bf.underpriced ? "LONG" : "SHORT"
        status = rev.reverted ? "✓" : "✗"
        @printf("  %2d) %s %s %s [%.0f/%.0f/%.0f]  max_gain=%.2f%%  final=%.2f%%\n",
            i, status, direction, bf.option_type, bf.K1, bf.K2, bf.K3,
            rev.max_gain * 100, rev.final_gain * 100)
    end
end

println("\n" * "="^70)
println("Butterfly Analysis Complete!")
println("="^70)
println("\nResults saved to: $run_folder")
println("="^70)