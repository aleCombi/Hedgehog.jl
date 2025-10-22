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
println("Deribit BTC Options: Heston Calibration & Vol Surface Visualization")
println("="^70)

# Load configuration
config_path = joinpath(@__DIR__, "config.yaml")
if !isfile(config_path)
    error("Configuration file not found: $config_path")
end
config = YAML.load_file(config_path)
println("\n[0a] Loaded configuration from: $config_path")

# Create timestamped run folder
timestamp = Dates.format(now(), "yyyymmdd_HHMMSS")
run_folder = joinpath(@__DIR__, config["output"]["runs_folder"], "heston_calib_$timestamp")
mkpath(run_folder)
println("[0b] Created run folder: $run_folder")

# Copy config to run folder for reproducibility
cp(config_path, joinpath(run_folder, "config.yaml"))

# Load data
data_path = joinpath(@__DIR__, "..", config["data"]["parquet_file"])
if !isfile(data_path)
    error("Data file not found: $data_path")
end

println("\n[1] Loading market data...")
market_surface = Hedgehog.load_deribit_parquet(
    data_path,
    rate=config["market"]["risk_free_rate"],
    filter_params=(
        min_days=config["filtering"]["min_days"],
        max_years=config["filtering"]["max_years"],
        min_moneyness=config["filtering"]["min_moneyness"],
        max_moneyness=config["filtering"]["max_moneyness"]
    )
)
summary(market_surface)

# Calibrate Heston
println("\n[2] Calibrating Heston model...")
println("This may take a few minutes...")

# Extract parameters from config
initial_params = config["calibration"]["initial_params"]
lb_config = config["calibration"]["lower_bounds"]
ub_config = config["calibration"]["upper_bounds"]

result = Hedgehog.calibrate_heston(
    market_surface,
    config["market"]["risk_free_rate"],
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

# Save calibration parameters to file
params_file = joinpath(run_folder, "calibrated_parameters.txt")
open(params_file, "w") do io
    println(io, "Heston Calibration Results")
    println(io, "="^70)
    println(io, "Run timestamp: $timestamp")
    println(io, "Data source: $(basename(data_path))")
    println(io, "Reference date: $(Dates.epochms2datetime(market_surface.reference_date))")
    println(io, "Spot price: $(market_surface.spot)")
    println(io, "Number of quotes: $(length(market_surface.quotes))")
    println(io, "\nFilter parameters:")
    println(io, "  Min days to expiry: $(config["filtering"]["min_days"])")
    println(io, "  Max years to expiry: $(config["filtering"]["max_years"])")
    println(io, "  Moneyness range: $(config["filtering"]["min_moneyness"]) - $(config["filtering"]["max_moneyness"])")
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
println("✓ Parameters saved to: $params_file")

# Calculate calibration quality
println("\n[3] Evaluating calibration quality...")

reference_date = Dates.epochms2datetime(market_surface.reference_date)
spot = market_surface.spot
rate = config["market"]["risk_free_rate"]

calibrated_heston = HestonInputs(
    reference_date,
    rate,
    spot,
    calibrated_params.v0,
    calibrated_params.κ,
    calibrated_params.θ,
    calibrated_params.σ,
    calibrated_params.ρ
)

pricing_method = CarrMadan(
    config["pricing"]["carr_madan"]["alpha"],
    config["pricing"]["carr_madan"]["grid_size"],
    HestonDynamics()
)

# Price all options with calibrated Heston
println("Pricing $(length(market_surface.quotes)) options with calibrated model...")
market_vols = [q.implied_vol for q in market_surface.quotes]
market_prices = [q.price for q in market_surface.quotes]
heston_prices = [
    solve(PricingProblem(q.payoff, calibrated_heston), pricing_method).price
    for q in market_surface.quotes
]

# Calculate errors
price_errors = heston_prices .- market_prices
abs_price_errors = abs.(price_errors)
rel_price_errors = abs_price_errors ./ market_prices .* 100

# Back out implied vols from Heston prices
println("Computing implied vols from Heston prices...")
iv_config = config["implied_vol"]
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
        println("Warning: Failed to compute implied vol for option $i")
    end
end

vol_errors = (heston_vols .- market_vols) .* 100
abs_vol_errors = abs.(vol_errors)

# Print and save statistics
println("\n" * "="^70)
println("CALIBRATION QUALITY METRICS")
println("="^70)

println("\nPrice Errors:")
@printf("  Mean Absolute Error:  \$%.4f\n", mean(abs_price_errors))
@printf("  RMSE:                 \$%.4f\n", sqrt(mean(price_errors.^2)))
@printf("  Max Absolute Error:   \$%.4f\n", maximum(abs_price_errors))
@printf("  Mean Relative Error:  %.2f%%\n", mean(rel_price_errors))
@printf("  Max Relative Error:   %.2f%%\n", maximum(rel_price_errors))

println("\nImplied Volatility Errors:")
@printf("  Mean Absolute Error:  %.2f%% points\n", mean(abs_vol_errors))
@printf("  RMSE:                 %.2f%% points\n", sqrt(mean(vol_errors.^2)))
@printf("  Max Absolute Error:   %.2f%% points\n", maximum(abs_vol_errors))

# Save quality metrics
metrics_file = joinpath(run_folder, "calibration_metrics.txt")
open(metrics_file, "w") do io
    println(io, "Calibration Quality Metrics")
    println(io, "="^70)
    println(io, "\nPrice Errors:")
    @printf(io, "  Mean Absolute Error:  \$%.4f\n", mean(abs_price_errors))
    @printf(io, "  RMSE:                 \$%.4f\n", sqrt(mean(price_errors.^2)))
    @printf(io, "  Max Absolute Error:   \$%.4f\n", maximum(abs_price_errors))
    @printf(io, "  Mean Relative Error:  %.2f%%\n", mean(rel_price_errors))
    @printf(io, "  Max Relative Error:   %.2f%%\n", maximum(rel_price_errors))
    println(io, "\nImplied Volatility Errors:")
    @printf(io, "  Mean Absolute Error:  %.2f%% points\n", mean(abs_vol_errors))
    @printf(io, "  RMSE:                 %.2f%% points\n", sqrt(mean(vol_errors.^2)))
    @printf(io, "  Max Absolute Error:   %.2f%% points\n", maximum(abs_vol_errors))
    
    println(io, "\nWorst 5 fits by volatility error:")
    println(io, "Strike | Expiry(Y) | Type | Market Vol | Heston Vol | Error")
    println(io, "-------|-----------|------|------------|------------|-------")
    worst_indices = sortperm(abs_vol_errors, rev=true)[1:min(5, length(abs_vol_errors))]
    for idx in worst_indices
        vol_quote = market_surface.quotes[idx]
        expiry_date = Date(Dates.epochms2datetime(vol_quote.payoff.expiry))
        years = yearfrac(Date(reference_date), expiry_date)
        cp_str = isa(vol_quote.payoff.call_put, Call) ? "Call" : "Put "
        
        @printf(io, "%7.0f | %9.2f | %s | %9.2f%% | %9.2f%% | %+6.2f%%\n",
                vol_quote.payoff.strike, years, cp_str,
                market_vols[idx] * 100, heston_vols[idx] * 100, vol_errors[idx])
    end
end
println("✓ Metrics saved to: $metrics_file")

# Show worst fits
println("\nWorst 5 fits by volatility error:")
println("Strike | Expiry(Y) | Type | Market Vol | Heston Vol | Error")
println("-------|-----------|------|------------|------------|-------")
worst_indices = sortperm(abs_vol_errors, rev=true)[1:min(5, length(abs_vol_errors))]
for idx in worst_indices
    vol_quote = market_surface.quotes[idx]
    expiry_date = Date(Dates.epochms2datetime(vol_quote.payoff.expiry))
    years = yearfrac(Date(reference_date), expiry_date)
    cp_str = isa(vol_quote.payoff.call_put, Call) ? "Call" : "Put "
    
    @printf("%7.0f | %9.2f | %s | %9.2f%% | %9.2f%% | %+6.2f%%\n",
            vol_quote.payoff.strike, years, cp_str,
            market_vols[idx] * 100, heston_vols[idx] * 100, vol_errors[idx])
end

# Save market quotes with errors to CSV
println("\n[3b] Saving market quotes comparison to CSV...")
market_quotes_df = DataFrame(
    strike = [q.payoff.strike for q in market_surface.quotes],
    expiry_date = [Date(Dates.epochms2datetime(q.payoff.expiry)) for q in market_surface.quotes],
    expiry_years = [yearfrac(Date(reference_date), Date(Dates.epochms2datetime(q.payoff.expiry))) for q in market_surface.quotes],
    option_type = [isa(q.payoff.call_put, Call) ? "Call" : "Put" for q in market_surface.quotes],
    market_price = market_prices,
    heston_price = heston_prices,
    price_error = price_errors,
    abs_price_error = abs_price_errors,
    market_vol = market_vols .* 100,
    heston_vol = heston_vols .* 100,
    vol_error = vol_errors,
    abs_vol_error = abs_vol_errors
)

market_csv_path = joinpath(run_folder, "market_quotes_comparison.csv")
CSV.write(market_csv_path, market_quotes_df)
println("✓ Market quotes saved to: $market_csv_path")

# Create 3D plots
println("\n[4] Creating 3D volatility surface plots...")

# Extract market data
market_strikes = [q.payoff.strike for q in market_surface.quotes]
market_expiries_dates = [Date(Dates.epochms2datetime(q.payoff.expiry)) for q in market_surface.quotes]
market_expiries_years = [yearfrac(Date(reference_date), exp) for exp in market_expiries_dates]
market_vols_pct = market_vols .* 100
heston_vols_pct = heston_vols .* 100

# Create grid for smooth Heston surface
k_min, k_max = extrema(market_strikes)
t_min, t_max = extrema(market_expiries_years)

grid_config = config["surface_grid"]
strike_grid = range(k_min, k_max, length=grid_config["num_strikes"])
expiry_grid = range(t_min, t_max, length=grid_config["num_expiries"])

println("Computing Heston surface on $(grid_config["num_strikes"])x$(grid_config["num_expiries"]) grid...")
println("Strike range: $(round(k_min)) to $(round(k_max))")
println("Expiry range: $(round(t_min, digits=2)) to $(round(t_max, digits=2)) years")

# Use let block to avoid scope warnings
heston_surf, failed_points_count, failed_details = let
    surf = zeros(length(strike_grid), length(expiry_grid))
    failed_count = 0
    failed_list = []
    min_price_threshold = grid_config["min_price_threshold"]
    
    for (i, K) in enumerate(strike_grid)
        for (j, T_years) in enumerate(expiry_grid)
            expiry_date = Date(reference_date) + Day(round(Int, T_years * 365))
            
            call_put = K < spot ? Put() : Call()
            payoff = VanillaOption(K, expiry_date, European(), call_put, Spot())
            
            try
                # Price with Heston
                prob = PricingProblem(payoff, calibrated_heston)
                heston_price = solve(prob, pricing_method).price
                
                # Check if price is reasonable
                if heston_price < min_price_threshold
                    push!(failed_list, (K=K, T=T_years, price=heston_price, reason="price too small"))
                    surf[i, j] = NaN
                    failed_count += 1
                    continue
                end
                
                # Back out implied vol
                dummy_inputs = BlackScholesInputs(Date(reference_date), rate, spot, iv_config["initial_guess"])
                basket = BasketPricingProblem([payoff], dummy_inputs)
                
                calib = CalibrationProblem(
                    basket,
                    BlackScholesAnalytic(),
                    [VolLens(1,1)],
                    [heston_price],
                    [iv_config["initial_guess"]],
                    lb=[iv_config["lower_bound"]],
                    ub=[iv_config["upper_bound"]]
                )
                
                vol_result = solve(calib, RootFinderAlgo())
                vol = vol_result.u
                
                if vol < iv_config["lower_bound"] || vol > iv_config["upper_bound"] || isnan(vol)
                    push!(failed_list, (K=K, T=T_years, price=heston_price, vol=vol, reason="vol out of bounds"))
                    surf[i, j] = NaN
                    failed_count += 1
                else
                    surf[i, j] = vol * 100
                end
            catch e
                push!(failed_list, (K=K, T=T_years, error=string(e), reason="exception"))
                surf[i, j] = NaN
                failed_count += 1
            end
        end
    end
    
    surf, failed_count, failed_list
end

println("✓ Surface computed ($(failed_points_count)/$(length(strike_grid)*length(expiry_grid)) points failed)")

if failed_points_count > 0
    println("\nFailed points analysis:")
    println("Total failed: $failed_points_count")
    
    # Save failed points details
    failed_csv_path = joinpath(run_folder, "failed_grid_points.csv")
    failed_df = DataFrame(failed_details)
    CSV.write(failed_csv_path, failed_df)
    println("✓ Failed points saved to: $failed_csv_path")
end

# Save Heston surface grid to CSV
println("\n[4b] Saving Heston volatility surface grid to CSV...")
surface_data = []
for (i, K) in enumerate(strike_grid)
    for (j, T_years) in enumerate(expiry_grid)
        push!(surface_data, (
            strike = K,
            expiry_years = T_years,
            expiry_date = Date(reference_date) + Day(round(Int, T_years * 365)),
            heston_vol = heston_surf[i, j],
            moneyness = K / spot,
            log_moneyness = log(K / spot)
        ))
    end
end
surface_df = DataFrame(surface_data)

surface_csv_path = joinpath(run_folder, "heston_vol_surface_grid.csv")
CSV.write(surface_csv_path, surface_df)
println("✓ Heston surface grid saved to: $surface_csv_path")

# Get plot settings from config
cam_angle = config["output"]["camera_angle"]
plot_width = config["output"]["plot_size"]["width"]
plot_height = config["output"]["plot_size"]["height"]

# Plot 1: Market vol surface (scatter)
p1 = scatter(
    market_strikes,
    market_expiries_years,
    market_vols_pct,
    xlabel="Strike",
    ylabel="Time to Expiry (years)",
    zlabel="Implied Vol (%)",
    title="Market Implied Volatility Surface\n(Deribit BTC Options)",
    marker=:circle,
    markersize=4,
    color=:viridis,
    camera=(cam_angle["azimuth"], cam_angle["elevation"]),
    legend=false,
    size=(plot_width÷2, plot_height÷2)
)

# Plot 2: Fitted Heston surface (smooth)
p2 = surface(
    strike_grid,
    expiry_grid,
    heston_surf',
    xlabel="Strike",
    ylabel="Time to Expiry (years)",
    zlabel="Implied Vol (%)",
    title="Fitted Heston Volatility Surface\n($(failed_points_count) grid points failed)",
    color=:plasma,
    camera=(cam_angle["azimuth"], cam_angle["elevation"]),
    legend=false,
    size=(plot_width÷2, plot_height÷2)
)

# Plot 3: Market vs Heston overlay
p3 = surface(
    strike_grid,
    expiry_grid,
    heston_surf',
    xlabel="Strike",
    ylabel="Time to Expiry (years)",
    zlabel="Implied Vol (%)",
    title="Market (dots) vs Heston (surface)",
    color=:plasma,
    alpha=0.6,
    camera=(cam_angle["azimuth"], cam_angle["elevation"]),
    legend=false,
    size=(plot_width÷2, plot_height÷2)
)
scatter!(
    p3,
    market_strikes,
    market_expiries_years,
    market_vols_pct,
    marker=:circle,
    markersize=4,
    color=:red,
    label="Market"
)

# Plot 4: Errors (only on actual market options)
error_colors = [err > 0 ? :red : :blue for err in vol_errors]
p4 = scatter(
    market_strikes,
    market_expiries_years,
    abs_vol_errors,
    xlabel="Strike",
    ylabel="Time to Expiry (years)",
    zlabel="Abs Vol Error (% points)",
    title="Calibration Errors\n(RMSE: $(round(sqrt(mean(vol_errors.^2)), digits=2))% points)\nMax: $(round(maximum(abs_vol_errors), digits=2))%",
    marker=:circle,
    markersize=5,
    color=error_colors,
    camera=(cam_angle["azimuth"], cam_angle["elevation"]),
    legend=false,
    size=(plot_width÷2, plot_height÷2)
)

# Combine all plots
combined_plot = plot(p1, p2, p3, p4, layout=(2,2), size=(plot_width, plot_height))

println("✓ Plots created")
display(combined_plot)

# Save plots
plot_path = joinpath(run_folder, "volatility_surfaces.png")
savefig(combined_plot, plot_path)
println("✓ Plot saved to: $plot_path")

println("\n" * "="^70)
println("Summary of Output Files in: $run_folder")
println("="^70)
println("  1. config.yaml")
println("     - Copy of configuration used for this run")
println("  2. calibrated_parameters.txt")
println("     - Calibrated Heston parameters and optimization details")
println("  3. calibration_metrics.txt")
println("     - Detailed error metrics and worst fits")
println("  4. market_quotes_comparison.csv")
println("     - Market vs Heston comparison for all $(length(market_surface.quotes)) options")
println("  5. heston_vol_surface_grid.csv")
println("     - Full Heston vol surface grid ($(length(strike_grid))×$(length(expiry_grid)) = $(length(strike_grid)*length(expiry_grid)) points)")
if failed_points_count > 0
    println("  6. failed_grid_points.csv")
    println("     - Details of $(failed_points_count) failed grid points")
    println("  7. volatility_surfaces.png")
else
    println("  6. volatility_surfaces.png")
end
println("     - 3D visualization plots")

println("\n" * "="^70)
println("Analysis Complete!")
println("="^70)