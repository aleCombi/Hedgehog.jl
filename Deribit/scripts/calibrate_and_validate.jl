# calibrate_and_validate.jl
# Main calibration and validation script
# Replaces: parquet_vol_surface.jl

using Revise, Hedgehog
using Deribit,Dates

println("="^70)
println("Deribit BTC Options: Multi-Period Heston Calibration & Validation")
println("="^70)

# ===========================
# [1] Load Configuration
# ===========================

config_path = joinpath(@__DIR__, "config.yaml")
config = load_config(config_path)

# Create run folder
run_folder = create_run_folder(joinpath(@__DIR__, ".."), "heston_calib")
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
plot_width, plot_height = get_plot_size(config)

# ===========================
# [2] Load Calibration Data
# ===========================

println("\n[1] Loading calibration data...")
calib_surface, calib_file = load_market_data(
    base_path, calib_date, underlying, calib_time, rate,filter_params;
    selection=selection_mode
)

println("\nCalibration Data Summary:")
summary(calib_surface)

# ===========================
# [3] Calibrate Heston
# ===========================

println("\n[2] Calibrating Heston model...")
calib_result = Deribit.calibrate_heston(
    calib_surface,
    rate,
    calib_cfg.initial_params;
    lb=calib_cfg.lower_bounds,
    ub=calib_cfg.upper_bounds,
    parquet_file=calib_file
)

print_calibration_summary(calib_result)

# Save parameters
save_calibration_params(
    calib_result,
    joinpath(run_folder, "calibrated_parameters.txt");
    calib_date=calib_date,
    calib_file=basename(calib_file)
)

# Create HestonInputs for validation
heston_inputs = to_heston_inputs(calib_result)

# ===========================
# [4] Validate on Calibration Period
# ===========================

println("\n[3] Evaluating fit on calibration data...")
calib_stats = compute_fit_statistics(
    calib_surface,
    heston_inputs,
    pricing_method,
    rate,
    iv_config;
    validation_name="Calibration"
)

print_fit_summary(calib_stats)

# Collect all stats (starting with calibration)
all_stats = [calib_stats]

# ===========================
# [5] Validate on Future Periods
# ===========================

val_config = extract_validation_config(config)

if val_config !== nothing
    println("\n[4] Validating on future time periods...")
    
    # Compute calibration anchor datetime
    base_date = Date(calib_date)
    base_time = calib_time === nothing ? Time("12:00:00") : Time(calib_time)
    calib_dt = DateTime(base_date, base_time)
    
    # Generate validation times
    validation_times = generate_validation_times(val_config, calib_dt)
    
    # Track processed files to avoid duplicates
    processed_files = Set{String}()
    
    for (idx, vdt) in enumerate(validation_times)
        println("\n  Validation target $(idx): $(vdt)")
        
        val_date_str = Dates.format(Date(vdt), dateformat"yyyy-mm-dd")
        val_time_str = Dates.format(Time(vdt), dateformat"HH:MM:SS")
        
        # Check for duplicate file
        chosen_file = find_parquet_file(
            base_path, val_date_str, underlying;
            time_filter=val_time_str, selection=selection_mode
        )
        
        if chosen_file in processed_files
            println("  ↪ Skipping (duplicate snapshot file): $(basename(chosen_file))")
            continue
        end
        
        try
            val_surface, val_file = load_market_data(
                base_path, val_date_str, underlying, val_time_str,
                rate, filter_params; selection=selection_mode
            )
            
            # Double-check for duplicates
            if val_file in processed_files
                println("  ↪ Skipping (duplicate after load): $(basename(val_file))")
                continue
            end
            push!(processed_files, val_file)
            
            # Format label
            val_name = format_delta_label(calib_dt, vdt)
            
            # Compute statistics
            val_stats = compute_fit_statistics(
                val_surface,
                heston_inputs,
                pricing_method,
                rate,
                iv_config;
                validation_name=val_name
            )
            
            push!(all_stats, val_stats)
            print_fit_summary(val_stats)
            
        catch e
            @warn "Failed to load validation data for $(vdt): $e"
        end
    end
else
    println("\n[4] Validation disabled in config")
end

# ===========================
# [6] Save Results
# ===========================

println("\n[5] Saving results...")

# Summary CSV
save_fit_summary_csv(all_stats, joinpath(run_folder, "validation_summary.csv"))

# Detailed CSVs
save_all_detailed_csvs(all_stats, run_folder)

# Plots
save_validation_plots(all_stats, joinpath(run_folder, "validation_results.png");
                     size=(plot_width, plot_height))

# ===========================
# [7] Final Summary
# ===========================

println("\n" * "="^70)
println("Multi-Period Validation Complete!")
println("="^70)
println("\nResults saved to: $run_folder")
println("\nValidation Summary:")
print_fit_summary(all_stats)
println("="^70)