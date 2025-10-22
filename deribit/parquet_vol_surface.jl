using Revise, Hedgehog
using DataFrames
using Parquet2
using Plots
using Statistics
using Printf
using Dates
using CSV
using YAML

println("="^70)
println("Deribit BTC Options: Multi-Period Heston Calibration & Validation")
println("="^70)

# Load configuration
config_path = joinpath(@__DIR__, "config.yaml")
if !isfile(config_path)
    error("Configuration file not found: $config_path")
end
config = YAML.load_file(config_path)
println("\n[0a] Loaded configuration from: $config_path")

# Create timestamped run folder in the same directory as this script
timestamp = Dates.format(now(), "yyyymmdd_HHMMSS")
run_folder = joinpath(@__DIR__, "runs", "heston_calib_$timestamp")
mkpath(run_folder)
println("[0b] Created run folder: $run_folder")

# Copy config to run folder for reproducibility
cp(config_path, joinpath(run_folder, "config.yaml"))

# ===== Helper Functions =====

"""
Find parquet file for a given date/time combination
"""
function find_parquet_file(base_path, date_str, underlying, time_filter=nothing)
    date_obj = Date(date_str)
    date_folder = Dates.format(date_obj, "yyyy-mm-dd")
    
    # Construct path pattern
    pattern_path = joinpath(base_path, "*", "data_parquet", "deribit_chain", 
                           "date=$date_folder", "underlying=$underlying")
    
    # Find all matching directories
    matching_dirs = String[]
    for root_dir in readdir(base_path, join=true)
        if !isdir(root_dir)
            continue
        end
        test_path = joinpath(root_dir, "data_parquet", "deribit_chain", 
                           "date=$date_folder", "underlying=$underlying")
        if isdir(test_path)
            push!(matching_dirs, test_path)
        end
    end
    
    if isempty(matching_dirs)
        error("No data found for date=$date_folder, underlying=$underlying")
    end
    
    # Get all parquet files
    parquet_files = []
    for dir in matching_dirs
        for file in readdir(dir)
            if endswith(file, ".parquet")
                filepath = joinpath(dir, file)
                push!(parquet_files, filepath)
            end
        end
    end
    
    if isempty(parquet_files)
        error("No parquet files found in $matching_dirs")
    end
    
    # If time filter specified, find closest file
    if time_filter !== nothing
        target_time = Time(time_filter)
        
        # Extract timestamps from filenames
        file_times = []
        for file in parquet_files
            # Parse timestamp from filename like "batch_20251019-151521012335.parquet"
            m = match(r"batch_(\d{8})-(\d{6})", file)
            if m !== nothing
                file_date = Date(m.captures[1], "yyyymmdd")
                file_time = Time(m.captures[2], "HHMMSS")
                if file_date == date_obj
                    push!(file_times, (file=file, time=file_time))
                end
            end
        end
        
        if isempty(file_times)
            @warn "No files found matching time filter, using first available file"
            return parquet_files[1]
        end
        
        # Find closest time
        time_diffs = [abs(Dates.value(ft.time - target_time)) for ft in file_times]
        closest_idx = argmin(time_diffs)
        selected_file = file_times[closest_idx].file
        
        println("Selected file closest to $time_filter: $(basename(selected_file))")
        return selected_file
    end
    
    # Otherwise return first file
    return parquet_files[1]
end

"""
Load market data for a specific date/time
"""
function load_market_data(base_path, date_str, underlying, time_filter, rate, filter_params)
    parquet_file = find_parquet_file(base_path, date_str, underlying, time_filter)
    println("Loading data from: $(basename(parquet_file))")
    
    market_surface = Hedgehog.load_deribit_parquet(
        parquet_file,
        rate=rate,
        filter_params=filter_params
    )
    
    return market_surface, parquet_file
end

"""
Compute validation metrics for a given market surface and calibrated model
"""
function validate_calibration(market_surface, calibrated_heston, pricing_method, 
                              rate, iv_config, validation_name="")
    reference_date = Dates.epochms2datetime(market_surface.reference_date)
    spot = market_surface.spot
    
    println("  Validating on $(length(market_surface.quotes)) options...")
    
    market_vols = [q.implied_vol for q in market_surface.quotes]
    market_prices = [q.price for q in market_surface.quotes]
    
    # Price with Heston
    heston_prices = [
        solve(PricingProblem(q.payoff, calibrated_heston), pricing_method).price
        for q in market_surface.quotes
    ]
    
    # Calculate price errors
    price_errors = heston_prices .- market_prices
    abs_price_errors = abs.(price_errors)
    rel_price_errors = abs_price_errors ./ market_prices .* 100
    
    # Back out implied vols
    heston_vols = Float64[]
    for (i, vol_quote) in enumerate(market_surface.quotes)
        try
            dummy_inputs = BlackScholesInputs(reference_date, rate, spot, iv_config["initial_guess"])
            basket = BasketPricingProblem([vol_quote.payoff], dummy_inputs)
            
            calib = CalibrationProblem(
                basket,
                BlackScholesAnalytic(),
                [VolLens(1,1)],
                [heston_prices[i]],
                [iv_config["initial_guess"]],
                lb=[iv_config["lower_bound"]],
                ub=[iv_config["upper_bound"]]
            )
            
            heston_vol = solve(calib, RootFinderAlgo()).u
            push!(heston_vols, heston_vol)
        catch e
            push!(heston_vols, market_vols[i])
        end
    end
    
    vol_errors = (heston_vols .- market_vols) .* 100
    abs_vol_errors = abs.(vol_errors)
    
    # Return metrics
    return Dict(
        :name => validation_name,
        :n_quotes => length(market_surface.quotes),
        :spot => spot,
        :price_mae => mean(abs_price_errors),
        :price_rmse => sqrt(mean(price_errors.^2)),
        :price_max_error => maximum(abs_price_errors),
        :price_mean_rel_error => mean(rel_price_errors),
        :vol_mae => mean(abs_vol_errors),
        :vol_rmse => sqrt(mean(vol_errors.^2)),
        :vol_max_error => maximum(abs_vol_errors),
        :market_vols => market_vols,
        :heston_vols => heston_vols,
        :market_prices => market_prices,
        :heston_prices => heston_prices,
        :quotes => market_surface.quotes,
        :reference_date => reference_date
    )
end

# ===== Step 1: Load Calibration Data =====
println("\n[1] Loading calibration data...")

base_path = config["data"]["base_path"]
underlying = config["data"]["underlying"]
calib_date = config["calibration"]["date"]
calib_time = get(config["calibration"], "time_filter", nothing)
rate = config["market"]["risk_free_rate"]

filter_params = (
    min_days=config["filtering"]["min_days"],
    max_years=config["filtering"]["max_years"],
    min_moneyness=config["filtering"]["min_moneyness"],
    max_moneyness=config["filtering"]["max_moneyness"]
)

calib_surface, calib_file = load_market_data(
    base_path, calib_date, underlying, calib_time, rate, filter_params
)

println("\nCalibration Data Summary:")
summary(calib_surface)

# ===== Step 2: Calibrate Heston =====
println("\n[2] Calibrating Heston model...")

initial_params = config["calibration"]["initial_params"]
lb_config = config["calibration"]["lower_bounds"]
ub_config = config["calibration"]["upper_bounds"]

result = Hedgehog.calibrate_heston(
    calib_surface,
    rate,
    (
        v0=initial_params["v0"],
        κ=initial_params["kappa"],
        θ=initial_params["theta"],
        σ=initial_params["sigma"],
        ρ=initial_params["rho"]
    ),
    lb=[lb_config["v0"], lb_config["kappa"], lb_config["theta"], 
        lb_config["sigma"], lb_config["rho"]],
    ub=[ub_config["v0"], ub_config["kappa"], ub_config["theta"], 
        ub_config["sigma"], ub_config["rho"]]
)

calibrated_params = (
    v0 = result.u[1],
    κ = result.u[2],
    θ = result.u[3],
    σ = result.u[4],
    ρ = result.u[5]
)

println("\n✓ Calibration complete!")
println("\nCalibrated Heston parameters:")
@printf("  v₀ = %.6f (%.2f%% vol)\n", calibrated_params.v0, sqrt(calibrated_params.v0)*100)
@printf("  κ  = %.6f\n", calibrated_params.κ)
@printf("  θ  = %.6f (%.2f%% vol)\n", calibrated_params.θ, sqrt(calibrated_params.θ)*100)
@printf("  σ  = %.6f\n", calibrated_params.σ)
@printf("  ρ  = %.6f\n", calibrated_params.ρ)

# Create calibrated Heston model
reference_date = Dates.epochms2datetime(calib_surface.reference_date)
spot = calib_surface.spot

calibrated_heston = HestonInputs(
    reference_date,
    rate,
    spot,
    calibrated_params.v0,
    calibrated_params.κ,
    calibrated_params.θ,
    calibrated_params.σ,
    calibrated_params.ρ)

pricing_method = CarrMadan(
    config["pricing"]["carr_madan"]["alpha"],
    config["pricing"]["carr_madan"]["grid_size"],
    HestonDynamics()
)

# ===== Step 3: Validate on Calibration Data =====
println("\n[3] Evaluating fit on calibration data...")

iv_config = config["implied_vol"]
calib_metrics = validate_calibration(
    calib_surface, calibrated_heston, pricing_method, rate, iv_config, "Calibration"
)

println("\nCalibration Period Metrics:")
@printf("  Price RMSE:  \$%.4f\n", calib_metrics[:price_rmse])
@printf("  Vol RMSE:    %.2f%% points\n", calib_metrics[:vol_rmse])
@printf("  Vol Max Err: %.2f%% points\n", calib_metrics[:vol_max_error])

# ===== Step 4: Validate on Future Dates =====
validation_metrics = [calib_metrics]

if config["validation"]["enabled"]
    println("\n[4] Validating on future time periods...")
    
    # Determine validation times
    validation_times = []
    
    if haskey(config["validation"], "validation_times")
        # Use explicit times
        for vtime_str in config["validation"]["validation_times"]
            push!(validation_times, DateTime(vtime_str))
        end
    else
        # Use hours_ahead
        calib_datetime = DateTime(calib_date) + Time(calib_time === nothing ? "12:00:00" : calib_time)
        for hours in config["validation"]["hours_ahead"]
            push!(validation_times, calib_datetime + Hour(hours))
        end
    end
    
    for (idx, val_datetime) in enumerate(validation_times)
        println("\n  Validation period $(idx): $(val_datetime)")
        
        val_date_str = Dates.format(Date(val_datetime), "yyyy-mm-dd")
        val_time_str = Dates.format(Time(val_datetime), "HH:MM:SS")
        
        try
            val_surface, val_file = load_market_data(
                base_path, val_date_str, underlying, val_time_str, rate, filter_params
            )
            
            val_name = "T+$(Dates.value(val_datetime - DateTime(calib_date) - Time(calib_time === nothing ? "12:00:00" : calib_time))) hours"
            val_metrics = validate_calibration(
                val_surface, calibrated_heston, pricing_method, rate, iv_config, val_name
            )
            
            push!(validation_metrics, val_metrics)
            
            @printf("    Price RMSE:  \$%.4f\n", val_metrics[:price_rmse])
            @printf("    Vol RMSE:    %.2f%% points\n", val_metrics[:vol_rmse])
            @printf("    Vol Max Err: %.2f%% points\n", val_metrics[:vol_max_error])
            
        catch e
            @warn "Failed to load validation data for $(val_datetime): $e"
        end
    end
else
    println("\n[4] Validation disabled in config")
end

# ===== Step 5: Save Results =====
println("\n[5] Saving results...")

# Save calibrated parameters
params_file = joinpath(run_folder, "calibrated_parameters.txt")
open(params_file, "w") do io
    println(io, "Heston Calibration Results")
    println(io, "="^70)
    println(io, "Run timestamp: $timestamp")
    println(io, "Calibration file: $(basename(calib_file))")
    println(io, "Calibration date: $calib_date")
    println(io, "Reference date: $(reference_date)")
    println(io, "Spot price: $(spot)")
    println(io, "Number of quotes: $(length(calib_surface.quotes))")
    println(io, "\nCalibrated Parameters:")
    @printf(io, "  v₀ = %.6f (%.2f%% vol)\n", calibrated_params.v0, sqrt(calibrated_params.v0)*100)
    @printf(io, "  κ  = %.6f\n", calibrated_params.κ)
    @printf(io, "  θ  = %.6f (%.2f%% vol)\n", calibrated_params.θ, sqrt(calibrated_params.θ)*100)
    @printf(io, "  σ  = %.6f\n", calibrated_params.σ)
    @printf(io, "  ρ  = %.6f\n", calibrated_params.ρ)
    println(io, "\nOptimization result:")
    println(io, "  Objective value: $(result.objective)")
    println(io, "  Return code: $(result.retcode)")
end

# Save validation summary
validation_summary_file = joinpath(run_folder, "validation_summary.csv")
summary_df = DataFrame(
    period = [m[:name] for m in validation_metrics],
    n_quotes = [m[:n_quotes] for m in validation_metrics],
    spot = [m[:spot] for m in validation_metrics],
    price_rmse = [m[:price_rmse] for m in validation_metrics],
    price_mae = [m[:price_mae] for m in validation_metrics],
    price_max_error = [m[:price_max_error] for m in validation_metrics],
    vol_rmse = [m[:vol_rmse] for m in validation_metrics],
    vol_mae = [m[:vol_mae] for m in validation_metrics],
    vol_max_error = [m[:vol_max_error] for m in validation_metrics]
)
CSV.write(validation_summary_file, summary_df)
println("✓ Validation summary saved to: $validation_summary_file")

# Save detailed results for each period
for metrics in validation_metrics
    period_name = replace(metrics[:name], " " => "_", "+" => "plus")
    
    detailed_df = DataFrame(
        strike = [q.payoff.strike for q in metrics[:quotes]],
        expiry_date = [Date(Dates.epochms2datetime(q.payoff.expiry)) for q in metrics[:quotes]],
        option_type = [isa(q.payoff.call_put, Call) ? "Call" : "Put" for q in metrics[:quotes]],
        market_vol = metrics[:market_vols] .* 100,
        heston_vol = metrics[:heston_vols] .* 100,
        vol_error = (metrics[:heston_vols] .- metrics[:market_vols]) .* 100,
        market_price = metrics[:market_prices],
        heston_price = metrics[:heston_prices],
        price_error = metrics[:heston_prices] .- metrics[:market_prices]
    )
    
    detailed_file = joinpath(run_folder, "detailed_$(period_name).csv")
    CSV.write(detailed_file, detailed_df)
end

# ===== Step 6: Create Plots =====
println("\n[6] Creating validation plots...")

# Plot 1: RMSE over time
p1 = plot(
    1:length(validation_metrics),
    [m[:vol_rmse] for m in validation_metrics],
    xlabel="Validation Period",
    ylabel="Vol RMSE (% points)",
    title="Model Performance Over Time",
    marker=:circle,
    markersize=6,
    linewidth=2,
    legend=false,
    xticks=(1:length(validation_metrics), [m[:name] for m in validation_metrics]),
    xrotation=45
)

# Plot 2: Vol errors distribution for calibration period
calib_vol_errors = (calib_metrics[:heston_vols] .- calib_metrics[:market_vols]) .* 100
p2 = histogram(
    calib_vol_errors,
    xlabel="Vol Error (% points)",
    ylabel="Frequency",
    title="Calibration Period: Vol Error Distribution",
    legend=false,
    bins=20
)

# Plot 3: Market vs Heston vols scatter (calibration)
p3 = scatter(
    calib_metrics[:market_vols] .* 100,
    calib_metrics[:heston_vols] .* 100,
    xlabel="Market Vol (%)",
    ylabel="Heston Vol (%)",
    title="Calibration Period: Market vs Heston",
    legend=false,
    markersize=4,
    alpha=0.6
)
plot!(p3, [0, 100], [0, 100], linestyle=:dash, color=:red, label="Perfect fit")

# Plot 4: RMSE comparison by validation period
if length(validation_metrics) > 1
    p4 = groupedbar(
        [m[:name] for m in validation_metrics],
        hcat([m[:vol_rmse] for m in validation_metrics], 
             [m[:price_rmse] for m in validation_metrics]),
        xlabel="Validation Period",
        ylabel="RMSE",
        title="Vol RMSE vs Price RMSE",
        label=["Vol RMSE (% pts)" "Price RMSE (\$)"],
        xrotation=45,
        bar_width=0.8
    )
else
    p4 = plot(title="Single Period - No Comparison")
end

combined_plot = plot(p1, p2, p3, p4, layout=(2,2), size=(1400, 1000))
plot_path = joinpath(run_folder, "validation_results.png")
savefig(combined_plot, plot_path)
println("✓ Validation plots saved to: $plot_path")

# ===== Summary =====
println("\n" * "="^70)
println("Multi-Period Validation Complete!")
println("="^70)
println("\nResults saved to: $run_folder")
println("\nValidation Summary:")
for metrics in validation_metrics
    println("  $(metrics[:name]):")
    @printf("    Vol RMSE: %.2f%% points\n", metrics[:vol_rmse])
    @printf("    Price RMSE: \$%.2f\n", metrics[:price_rmse])
end

println("\n" * "="^70)