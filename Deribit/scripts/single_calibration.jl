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

# ----------------------------
# Plot helper (renamed)
# ----------------------------

using Dates
using Statistics
using Plots
# If you want interactivity:
# try; plotlyjs(); catch; end  # fallback to GR if PlotlyJS isn't available

using Dates
using Statistics
using Plots

using Dates
using Statistics
using Plots

using Dates
using Plots

using Statistics
using Plots


function save_iv_surface_heston_vs_market_scatter(market_surface, heston_inputs, pricing_method, iv_config, out_path; nK=35, nT=12)
    # --- Pull data (all ticks)
    ref_ticks = market_surface.reference_date               # ticks (ms)
    quotes    = market_surface.quotes

    Ks_q   = [q.payoff.strike for q in quotes]
    Ts_q   = [q.payoff.expiry for q in quotes]              # ticks
    IVq    = [q.implied_vol * 100 for q in quotes]
    Tyrs_q = [yearfrac(ref_ticks, t) for t in Ts_q]         # your ACT/365 over ticks

    # --- Expiry grid (thin if needed), keep as ticks
    exp_ticks = sort(collect(unique(Ts_q)))
    if length(exp_ticks) > nT
        idxs = round.(Int, range(1, length(exp_ticks), length=nT))
        exp_ticks = exp_ticks[idxs]
    end
    Tyrs = [yearfrac(ref_ticks, t) for t in exp_ticks]

    # --- Strike grid
    Kmin  = quantile(Ks_q, 0.05)
    Kmax  = quantile(Ks_q, 0.95)
    Kgrid = collect(range(Kmin, Kmax, length=nK))

    # --- Forward per expiry (keyed by ticks)
    fwd_by_exp = Dict{typeof(exp_ticks[1]),Float64}()
    for t in exp_ticks
        fwds = [q.forward for q in quotes if q.payoff.expiry == t]
        fwd_by_exp[t] = isempty(fwds) ? median(skipmissing([q.forward for q in quotes])) : median(skipmissing(fwds))
    end

    # --- IV inversion bounds/guess
    ig = Float64(iv_config["initial_guess"])
    lb = Float64(iv_config["lower_bound"])
    ub = Float64(iv_config["upper_bound"])

    # Price -> BS IV via 1D calibration; all times as ticks
    function implied_vol_from_price(K::Float64, t, price::Float64)
        fwd = get(fwd_by_exp, t, median(values(fwd_by_exp)))
        bs_inputs = BlackScholesInputs(Dates.epochms2datetime(ref_ticks), 0.0, fwd, ig)  # ref date in ticks; r=0; forward-as-spot
        payoff = VanillaOption(K, t, European(), Call(), Spot()) # expiry in ticks
        calib = CalibrationProblem(
            BasketPricingProblem([payoff], bs_inputs),
            BlackScholesAnalytic(),
            [VolLens(1,1)],
            [price], [ig]; lb=[lb], ub=[ub]
        )
        v = try
            res = solve(calib, RootFinderAlgo())
            (res.u isa AbstractVector ? res.u[1] : res.u)::Float64
        catch
            NaN
        end
        return v
    end

    # --- Build Heston IV surface Z[j,i] with j over T, i over K
    Z = Array{Float64}(undef, length(Tyrs), length(Kgrid))
    for (j, t) in enumerate(exp_ticks)
        for (i, K) in enumerate(Kgrid)
            price = try
                # expiry ticks throughout
                solve(PricingProblem(VanillaOption(K, t, European(), Call(), Spot()),
                                     heston_inputs), pricing_method).price
            catch
                NaN
            end
            Z[j, i] = isfinite(price) ? implied_vol_from_price(K, t, price) * 100 : NaN
        end
    end

    # --- Plot
    plt = plot(title = "Implied Vol: Heston Surface + Market Scatter",
               xlabel = "Maturity (years)", ylabel = "Strike", zlabel = "IV (%)",
               legend = :topright)

    surface!(plt, Kgrid, Tyrs, Z; alpha=0.85, label="Heston surface")
    scatter3d!(plt, Ks_q, Tyrs_q, IVq; ms=3, label="Market quotes")

    savefig(plt, out_path)
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

run_folder = create_run_folder(joinpath(@__DIR__, ".."), "heston_calib")
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

println("\nCalibration Data Summary:")
summary(calib_surface)

# 3) Calibrate Heston (single calibration)
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

# 5) Plot & save (renamed function)
png_path = joinpath(run_folder, "iv_surfaces_3d.png")
save_iv_surface_heston_vs_market_scatter(calib_surface, heston_inputs, pricing_method, iv_config, png_path)
println("✓ 3D IV surfaces saved to: $png_path")

println("\n" * "="^70)
println("Single Calibration Complete!")
println("="^70)
println("Results saved to: $run_folder")
