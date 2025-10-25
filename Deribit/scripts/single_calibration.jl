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

expiries    = unique(q.payoff.expiry for q in calib_surface.quotes)
Tmin        = minimum(expiries)
fwd_bucket  = [q.forward for q in calib_surface.quotes if q.payoff.expiry == Tmin]
# @assert !isempty(fwd_bucket) "Cannot infer spot: no quotes at the shortest expiry."
spot = median(fwd_bucket)

println("\nDEBUG - Reference date: $(calib_surface.reference_date) (ticks)")
println("DEBUG - Reference date: $(Dates.epochms2datetime(calib_surface.reference_date)) (DateTime)")
println("DEBUG - Sample expiries (first 3):")
for (i, q) in enumerate(calib_surface.quotes[1:min(3, length(calib_surface.quotes))])
    exp_dt = Dates.epochms2datetime(q.payoff.expiry)
    ttm = yearfrac(calib_surface.reference_date, q.payoff.expiry)
    println("  $i) Expiry: $exp_dt, TTM: $(round(ttm, digits=4)) years")
end

println("\nCalibration Data Summary:")
summary(calib_surface)
r_date = Dates.epochms2datetime(calib_surface.reference_date)
heston_inputs = HestonInputs(
        r_date,
        0.0,
        spot,
        calib_cfg.initial_params.v0,
        calib_cfg.initial_params.κ,
        calib_cfg.initial_params.θ,
        calib_cfg.initial_params.σ,
        calib_cfg.initial_params.ρ
    )

payofffs = [q.payoff for q in calib_surface.quotes]
basket = BasketPricingProblem(payofffs, heston_inputs)
basket_sol = solve(basket, pricing_method)
model_prices = [bsp.price for bsp in basket_sol.solutions]
market_prices = [q.price for q in calib_surface.quotes]
using Accessors
accessors = [
        @optic(_.market_inputs.V0),
        @optic(_.market_inputs.κ),
        @optic(_.market_inputs.θ),
        @optic(_.market_inputs.σ),
        @optic(_.market_inputs.ρ)
    ]
initial_guess = [
    calib_cfg.initial_params.v0,
    calib_cfg.initial_params.κ,
    calib_cfg.initial_params.θ,
    calib_cfg.initial_params.σ,
    calib_cfg.initial_params.ρ
]
println("\n[2] Calibrating Heston model...")

calib_problem = CalibrationProblem(
    basket,
    pricing_method,
    accessors,
    market_prices,
    initial_guess;
    lb=calib_cfg.lower_bounds,
    ub=calib_cfg.upper_bounds
)
calib_result_manual = solve(calib_problem, OptimizerAlgo())


calib_result = Deribit.calibrate_heston(calib_surface, 0.0, calib_cfg.initial_params;
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
heston_inputs = @set heston_inputs.V0 = calib_result_manual.u[1]
heston_inputs = @set heston_inputs.κ  = calib_result_manual.u[2]  
heston_inputs = @set heston_inputs.θ  = calib_result_manual.u[3]
heston_inputs = @set heston_inputs.σ  = calib_result_manual.u[4]
heston_inputs = @set heston_inputs.ρ  = calib_result_manual.u[5]

calib_stats_manual = compute_fit_statistics(
    calib_surface,
    heston_inputs,
    pricing_method,
    rate,
    iv_config;
    validation_name="Calibration"
)

calib_stats = compute_fit_statistics(
    calib_surface,
    to_heston_inputs(calib_result),
    pricing_method,
    rate,
    iv_config;
    validation_name="Calibration"
)
print("\nFit Statistics Summary (Manual Calibrator):")
print_fit_summary(calib_stats_manual)

print("\nFit Statistics Summary (Deribit Calibrator):")
print_fit_summary(calib_stats)
# Save CSVs
save_fit_summary_csv([calib_stats_manual], joinpath(run_folder, "validation_summary_manual.csv"))
save_fit_detailed_csv(calib_stats_manual, joinpath(run_folder, "detailed_calibration_manual.csv"))
save_fit_summary_csv([calib_stats], joinpath(run_folder, "validation_summary.csv"))
save_fit_detailed_csv(calib_stats, joinpath(run_folder, "detailed_calibration.csv"))

# 5) Plot & save (renamed function)
png_path = joinpath(run_folder, "iv_surfaces_3d.png")
save_iv_surface_heston_vs_market_scatter(calib_stats_manual, png_path)
println("✓ 3D IV surfaces saved to: $png_path")

# 5) Plot & save (renamed function)
png_path = joinpath(run_folder, "iv_surfaces_3d_manual.png")
save_iv_surface_heston_vs_market_scatter(calib_stats, png_path)
println("✓ 3D IV surfaces saved to: $png_path")

println("\n" * "="^70)
println("Single Calibration Complete!")
println("="^70)
println("Results saved to: $run_folder")
