# analyze_mispricings.jl
# Mispricing and island detection script
# Replaces: vol_arb_probe.jl

using Revise, Hedgehog
using Deribit, Printf

println("="^70)
println("Deribit BTC Options: Mispricing & Island Probe (Calibration Snapshot)")
println("="^70)

# ===========================
# [1] Load Configuration
# ===========================

config_path = joinpath(@__DIR__, "config.yaml")
config = load_config(config_path)

# Create run folder
run_folder = create_run_folder(@__DIR__, "arb_probe")
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
mispricing_thresholds = extract_mispricing_config(config)

println("\nMispricing Thresholds:")
println("  Price absolute: $(mispricing_thresholds.price_abs_threshold)")
println("  Price relative: $(mispricing_thresholds.price_rel_threshold * 100)%")
println("  Vol (pp):       $(mispricing_thresholds.vol_pp_threshold)")

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
# [4] Detect Mispricings
# ===========================

println("\n[3] Detecting mispricings...")
mispricing_records = detect_mispricings(
    mkt_surface,
    heston_inputs,
    pricing_method,
    rate,
    iv_config,
    mispricing_thresholds
)

print_mispricing_summary(mispricing_records)

# ===========================
# [5] Find Islands
# ===========================

println("\n[4] Finding island mispricings...")
islands_result = save_islands_csvs(mispricing_records, run_folder)

println("\nIsland Summary:")
@printf("  Price-based islands:    %d\n", length(islands_result.islands_price))
@printf("  Vol-based islands:      %d\n", length(islands_result.islands_vol))
@printf("  Combined islands:       %d\n", length(islands_result.islands_combined))

# ===========================
# [6] Save Results
# ===========================

println("\n[5] Saving results...")

# Mispricing CSV
save_mispricing_csv(mispricing_records, joinpath(run_folder, "mispricing_calibration.csv"))

# Top mispricings
println("\n" * "="^70)
print_top_mispricings(mispricing_records; k=5, by=:price_error)
println()
print_top_mispricings(mispricing_records; k=5, by=:vol_error_pp)
println("="^70)

# Heatmaps
println("\n[6] Creating heatmaps...")
save_mispricing_heatmaps(mispricing_records, run_folder)

# ===========================
# [7] Final Summary
# ===========================

println("\n" * "="^70)
println("Mispricing Analysis Complete!")
println("="^70)
println("\nResults saved to: $run_folder")
println("\nSummary:")
print_mispricing_summary(mispricing_records)
println("\nIslands:")
@printf("  Price-islands:    %d\n", length(islands_result.islands_price))
@printf("  Vol-islands:      %d\n", length(islands_result.islands_vol))
@printf("  Combined islands: %d\n", length(islands_result.islands_combined))
println("="^70)