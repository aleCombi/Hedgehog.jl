using Revise, Hedgehog
using DataFrames
using Parquet2
using Plots
using Statistics
using Printf
using Dates
using CSV
using YAML

# ===============================
# Deribit BTC Options:
# Multi-Period Heston Calibration & Validation
# ===============================

println("="^70)
println("Deribit BTC Options: Multi-Period Heston Calibration & Validation")
println("="^70)

# ------------------------------- #
# [0] Load configuration & setup  #
# ------------------------------- #

const MS_PER_MIN  = 60_000
const MS_PER_HOUR = 3_600_000
const MS_PER_DAY  = 86_400_000

config_path = joinpath(@__DIR__, "config.yaml")
isfile(config_path) || error("Configuration file not found: $config_path")
config = YAML.load_file(config_path)
println("\n[0a] Loaded configuration from: $config_path")

timestamp  = Dates.format(now(), "yyyymmdd_HHMMSS")
run_folder = joinpath(@__DIR__, "runs", "heston_calib_$timestamp")
mkpath(run_folder)
println("[0b] Created run folder: $run_folder")

cp(config_path, joinpath(run_folder, "config.yaml"); force=true)

# -------------------- #
# Helpers              #
# -------------------- #

"""
parse_dt(s) -> DateTime

Accepts forms like:
- "2025-10-21 12:00:00"
- "2025-10-21T12:00:00"
"""
function parse_dt(s::AbstractString)
    str = strip(s)
    try
        return DateTime(str)  # supports both " " and "T"
    catch
        # Try explicit formats if needed
        try
            return DateTime(str, dateformat"yyyy-mm-dd HH:MM:SS")
        catch
            return DateTime(str, dateformat"yyyy-mm-ddTHH:MM:SS")
        end
    end
end

"""
parse_period("30m"|"2h"|"1d") -> Period
"""
function parse_period(s::AbstractString)::Period
    str = lowercase(strip(s))
    m = match(r"^(\d+)\s*([mhd])$", str)
    m === nothing && error("Invalid duration '$s'. Use forms like '15m', '2h', '1d'.")
    n = parse(Int, m.captures[1])
    u = m.captures[2]
    u == "m" && return Minute(n)
    u == "h" && return Hour(n)
    u == "d" && return Day(n)
    error("Unsupported unit '$u' in duration '$s'.")
end

"""
period_ms(p::Period) -> Int milliseconds
"""
function period_ms(p::Period)::Int
    if p isa Minute
        return Int(Dates.value(p)) * MS_PER_MIN
    elseif p isa Hour
        return Int(Dates.value(p)) * MS_PER_HOUR
    elseif p isa Day
        return Int(Dates.value(p)) * MS_PER_DAY
    else
        error("Unsupported Period type $(typeof(p)).")
    end
end

"""
extract_file_dt(file_basename) -> Union{Date,Time,Nothing,Nothing}

From file name like "batch_20251021-120022707313.parquet"
returns (Date("2025-10-21"), Time("12:00:00")) if parsable, else (nothing,nothing).
Only first 6 time digits HHMMSS are read.
"""
function extract_file_dt(fname::AbstractString)
    if (m = match(r"batch_(\d{8})-(\d{6})", fname)) !== nothing
        file_date = Date(m.captures[1], dateformat"yyyymmdd")
        file_time = Time(m.captures[2], dateformat"HHMMSS")
        return file_date, file_time
    end
    return nothing, nothing
end

"""
find_parquet_file(base_path, date_str, underlying; time_filter=nothing, selection="closest")
 -> String

Find parquet file under:
  <root>/data_parquet/deribit_chain/date=YYYY-MM-DD/underlying=<underlying>/*.parquet

If `time_filter` provided (HH:MM:SS), it will select:
- selection="closest" (default): file with time closest to target time (same date)
- selection="floor": the most recent file not after target time (same date). If none <= target, falls back to earliest file of that date.

If no `time_filter`, returns the first available parquet.
"""
function find_parquet_file(base_path, date_str, underlying; time_filter=nothing, selection::AbstractString="closest")
    date_obj    = Date(date_str)
    date_folder = Dates.format(date_obj, dateformat"yyyy-mm-dd")

    # find all matching directories
    matching_dirs = String[]
    for root_dir in readdir(base_path, join=true)
        isdir(root_dir) || continue
        test_path = joinpath(root_dir, "data_parquet", "deribit_chain",
                             "date=$date_folder", "underlying=$underlying")
        if isdir(test_path)
            push!(matching_dirs, test_path)
        end
    end
    isempty(matching_dirs) && error("No data found for date=$date_folder, underlying=$underlying")

    # collect parquet files
    parquet_files = String[]
    for dir in matching_dirs
        for f in readdir(dir)
            endswith(f, ".parquet") || continue
            push!(parquet_files, joinpath(dir, f))
        end
    end
    isempty(parquet_files) && error("No parquet files found in $(join(matching_dirs, ';'))")

    # if no time filter, just return the first one
    if time_filter === nothing
        return parquet_files[1]
    end

    target_time = Time(time_filter)

    # collect candidates for the given date
    candidates = NamedTuple{(:file,:time)}[]
    for fp in parquet_files
        b = basename(fp)
        fdate, ftime = extract_file_dt(b)
        (fdate === nothing || ftime === nothing) && continue
        fdate == date_obj && push!(candidates, (file=fp, time=ftime))
    end
    if isempty(candidates)
        @warn "No files match date=$date_folder for time filtering; falling back to first parquet."
        return parquet_files[1]
    end

    if lowercase(selection) == "closest"
        diffs = [abs(Dates.value(c.time - target_time)) for c in candidates]
        chosen = candidates[argmin(diffs)].file
        println("Selected file closest to $time_filter: $(basename(chosen))")
        return chosen
    elseif lowercase(selection) == "floor"
        # choose the latest time <= target_time; if none, choose earliest of that day
        not_after = filter(c -> c.time <= target_time, candidates)
        if !isempty(not_after)
            idx = argmax([Dates.value(c.time) for c in not_after])
            chosen = not_after[idx].file
            println("Selected file (floor) at or before $time_filter: $(basename(chosen))")
            return chosen
        else
            # fallback to earliest of the day
            idx = argmin([Dates.value(c.time) for c in candidates])
            chosen = candidates[idx].file
            println("No file at/before $time_filter; selected earliest: $(basename(chosen))")
            return chosen
        end
    else
        @warn "Unknown selection='$selection'; using 'closest'."
        diffs = [abs(Dates.value(c.time - target_time)) for c in candidates]
        chosen = candidates[argmin(diffs)].file
        println("Selected file closest to $time_filter: $(basename(chosen))")
        return chosen
    end
end

"""
load_market_data(base_path, date_str, underlying, time_filter, rate, filter_params; selection="closest")
 -> (MarketVolSurface, parquet_path)
"""
function load_market_data(base_path, date_str, underlying, time_filter, rate, filter_params; selection="closest")
    parquet_file = find_parquet_file(base_path, date_str, underlying; time_filter=time_filter, selection=selection)
    println("Loading data from: $(basename(parquet_file))")
    mkt = Hedgehog.load_deribit_parquet(parquet_file; rate=rate, filter_params=filter_params)
    return mkt, parquet_file
end

"""
validate_calibration(market_surface, calibrated_heston, pricing_method, rate, iv_config; validation_name="")
 -> Dict with metrics and arrays used later for CSV/plots.
"""
function validate_calibration(market_surface, calibrated_heston, pricing_method,
                              rate, iv_config; validation_name="")
    reference_date = Dates.epochms2datetime(market_surface.reference_date)
    spot = market_surface.spot

    println("  Validating on $(length(market_surface.quotes)) options...")

    market_vols   = [q.implied_vol for q in market_surface.quotes]
    market_prices = [q.price       for q in market_surface.quotes]

    # Heston prices
    heston_prices = [
        solve(PricingProblem(q.payoff, calibrated_heston), pricing_method).price
        for q in market_surface.quotes
    ]

    # Price errors
    price_errors       = heston_prices .- market_prices
    abs_price_errors   = abs.(price_errors)
    rel_price_errors   = abs_price_errors ./ market_prices .* 100

    # Back out implied vols via BS by solving for vol that matches each Heston price
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
                [iv_config["initial_guess"]];
                lb=[iv_config["lower_bound"]],
                ub=[iv_config["upper_bound"]]
            )
            push!(heston_vols, solve(calib, RootFinderAlgo()).u)
        catch
            # Fall back to market vol if inversion fails
            push!(heston_vols, market_vols[i])
        end
    end

    vol_errors     = (heston_vols .- market_vols) .* 100
    abs_vol_errors = abs.(vol_errors)

    return Dict(
        :name               => validation_name,
        :n_quotes           => length(market_surface.quotes),
        :spot               => spot,
        :price_mae          => mean(abs_price_errors),
        :price_rmse         => sqrt(mean(price_errors.^2)),
        :price_max_error    => maximum(abs_price_errors),
        :price_mean_rel_err => mean(rel_price_errors),
        :vol_mae            => mean(abs_vol_errors),
        :vol_rmse           => sqrt(mean(vol_errors.^2)),
        :vol_max_error      => maximum(abs_vol_errors),
        :market_vols        => market_vols,
        :heston_vols        => heston_vols,
        :market_prices      => market_prices,
        :heston_prices      => heston_prices,
        :quotes             => market_surface.quotes,
        :reference_date     => reference_date
    )
end

# --------------------------------- #
# [1] Load Calibration Data         #
# --------------------------------- #

println("\n[1] Loading calibration data...")

base_path  = config["data"]["base_path"]
underlying = config["data"]["underlying"]
calib_date = config["calibration"]["date"]
calib_time = get(config["calibration"], "time_filter", nothing)
rate       = config["market"]["risk_free_rate"]

filter_params = (
    min_days      = config["filtering"]["min_days"],
    max_years     = config["filtering"]["max_years"],
    min_moneyness = config["filtering"]["min_moneyness"],
    max_moneyness = config["filtering"]["max_moneyness"]
)

# selection mode for file choice in validation (default "closest")
selection_mode = if haskey(config, "validation") &&
                    haskey(config["validation"], "schedule") &&
                    config["validation"]["schedule"] !== nothing &&
                    haskey(config["validation"]["schedule"], "selection")
    config["validation"]["schedule"]["selection"]
else
    "closest"
end

calib_surface, calib_file = load_market_data(
    base_path, calib_date, underlying, calib_time, rate, filter_params; selection=selection_mode
)

println("\nCalibration Data Summary:")
summary(calib_surface)

# --------------------------------- #
# [2] Calibrate Heston              #
# --------------------------------- #

println("\n[2] Calibrating Heston model...")

initial_params = config["calibration"]["initial_params"]
lb_config      = config["calibration"]["lower_bounds"]
ub_config      = config["calibration"]["upper_bounds"]

result = Hedgehog.calibrate_heston(
    calib_surface,
    rate,
    (
        v0 = initial_params["v0"],
        κ  = initial_params["kappa"],
        θ  = initial_params["theta"],
        σ  = initial_params["sigma"],
        ρ  = initial_params["rho"]
    );
    lb=[lb_config["v0"], lb_config["kappa"], lb_config["theta"],
        lb_config["sigma"], lb_config["rho"]],
    ub=[ub_config["v0"], ub_config["kappa"], ub_config["theta"],
        ub_config["sigma"], ub_config["rho"]]
)

calibrated_params = (
    v0 = result.u[1],
    κ  = result.u[2],
    θ  = result.u[3],
    σ  = result.u[4],
    ρ  = result.u[5]
)

println("\n✓ Calibration complete!")
println("\nCalibrated Heston parameters:")
@printf("  v₀ = %.6f (%.2f%% vol)\n", calibrated_params.v0, sqrt(calibrated_params.v0)*100)
@printf("  κ  = %.6f\n",           calibrated_params.κ)
@printf("  θ  = %.6f (%.2f%% vol)\n", calibrated_params.θ, sqrt(calibrated_params.θ)*100)
@printf("  σ  = %.6f\n",           calibrated_params.σ)
@printf("  ρ  = %.6f\n",           calibrated_params.ρ)

reference_date = Dates.epochms2datetime(calib_surface.reference_date)
spot           = calib_surface.spot

calibrated_heston = HestonInputs(
    reference_date, rate, spot,
    calibrated_params.v0, calibrated_params.κ, calibrated_params.θ,
    calibrated_params.σ, calibrated_params.ρ
)

# pricing method (kept minimal here; you can branch on method if needed)
pricing_method = CarrMadan(
    config["pricing"]["carr_madan"]["alpha"],
    config["pricing"]["carr_madan"]["grid_size"],
    HestonDynamics()
)

# --------------------------------- #
# [3] Validate on Calibration Data  #
# --------------------------------- #

println("\n[3] Evaluating fit on calibration data...")

iv_config     = config["implied_vol"]
calib_metrics = validate_calibration(
    calib_surface, calibrated_heston, pricing_method, rate, iv_config; validation_name="Calibration"
)

println("\nCalibration Period Metrics:")
@printf("  Price RMSE:  \$%.4f\n", calib_metrics[:price_rmse])
@printf("  Vol RMSE:    %.2f%% points\n", calib_metrics[:vol_rmse])
@printf("  Vol Max Err: %.2f%% points\n",  calib_metrics[:vol_max_error])

# --------------------------------- #
# [4] Validate on Future Periods    #
# --------------------------------- #

validation_metrics = [calib_metrics]

if get(config, "validation", Dict())["enabled"]
    println("\n[4] Validating on future time periods...")

    # Anchor DateTime (calibration)
    base_date = Date(calib_date)
    base_time = calib_time === nothing ? Time("12:00:00") : Time(calib_time)
    calib_dt  = DateTime(base_date, base_time)

    # Build list of DateTimes to validate
    validation_times = DateTime[]

    if haskey(config["validation"], "schedule") && config["validation"]["schedule"] !== nothing
        sched     = config["validation"]["schedule"]
        every_str = sched["every"]
        for_str   = sched["for"]
        start_at  = get(sched, "start_at", nothing)
        max_steps = get(sched, "max_steps", nothing)

        step_period    = parse_period(every_str)
        horizon = parse_period(for_str)

        anchor_dt = start_at === nothing ? calib_dt : parse_dt(start_at)

        total_ms = period_ms(horizon)
        step_ms  = period_ms(step_period)
        nsteps   = max(0, Int(floor(total_ms / step_ms)))
        if max_steps !== nothing
            nsteps = min(nsteps, Int(max_steps))
        end

        for k in 1:nsteps
            push!(validation_times, anchor_dt + k*step_period)
        end

    elseif haskey(config["validation"], "validation_times")
        for vstr in config["validation"]["validation_times"]
            push!(validation_times, parse_dt(vstr))
        end
    elseif haskey(config["validation"], "hours_ahead")
        for h in config["validation"]["hours_ahead"]
            push!(validation_times, calib_dt + Hour(h))
        end
    end

    for (idx, vdt) in enumerate(validation_times)
        println("\n  Validation period $(idx): $(vdt)")

        val_date_str = Dates.format(Date(vdt), dateformat"yyyy-mm-dd")
        val_time_str = Dates.format(Time(vdt), dateformat"HH:MM:SS")

        try
            val_surface, _ = load_market_data(
                base_path, val_date_str, underlying, val_time_str, rate, filter_params; selection=selection_mode
            )

            Δms    = Dates.value(vdt - calib_dt)
            Δhours = round(Int, Δms / MS_PER_HOUR)
            val_name = "T+$(Δhours) hours"

            val_metrics = validate_calibration(
                val_surface, calibrated_heston, pricing_method, rate, iv_config; validation_name=val_name
            )
            push!(validation_metrics, val_metrics)

            @printf("    Price RMSE:  \$%.4f\n", val_metrics[:price_rmse])
            @printf("    Vol RMSE:    %.2f%% points\n", val_metrics[:vol_rmse])
            @printf("    Vol Max Err: %.2f%% points\n",  val_metrics[:vol_max_error])

        catch e
            @warn "Failed to load validation data for $(vdt): $e"
        end
    end
else
    println("\n[4] Validation disabled in config")
end

# ----------------------- #
# [5] Save Results Files  #
# ----------------------- #

println("\n[5] Saving results...")

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
    @printf(io, "  κ  = %.6f\n",           calibrated_params.κ)
    @printf(io, "  θ  = %.6f (%.2f%% vol)\n", calibrated_params.θ, sqrt(calibrated_params.θ)*100)
    @printf(io, "  σ  = %.6f\n",           calibrated_params.σ)
    @printf(io, "  ρ  = %.6f\n",           calibrated_params.ρ)
    println(io, "\nOptimization result:")
    println(io, "  Objective value: $(result.objective)")
    println(io, "  Return code: $(result.retcode)")
end

validation_summary_file = joinpath(run_folder, "validation_summary.csv")
summary_df = DataFrame(
    period          = [m[:name]          for m in validation_metrics],
    n_quotes        = [m[:n_quotes]      for m in validation_metrics],
    spot            = [m[:spot]          for m in validation_metrics],
    price_rmse      = [m[:price_rmse]    for m in validation_metrics],
    price_mae       = [m[:price_mae]     for m in validation_metrics],
    price_max_error = [m[:price_max_error] for m in validation_metrics],
    vol_rmse        = [m[:vol_rmse]      for m in validation_metrics],
    vol_mae         = [m[:vol_mae]       for m in validation_metrics],
    vol_max_error   = [m[:vol_max_error] for m in validation_metrics]
)
CSV.write(validation_summary_file, summary_df)
println("✓ Validation summary saved to: $validation_summary_file")

for metrics in validation_metrics
    period_name = replace(metrics[:name], " " => "_", "+" => "plus")

    detailed_df = DataFrame(
        strike        = [q.payoff.strike for q in metrics[:quotes]],
        expiry_date   = [Date(Dates.epochms2datetime(q.payoff.expiry)) for q in metrics[:quotes]],
        option_type   = [isa(q.payoff.call_put, Call) ? "Call" : "Put" for q in metrics[:quotes]],
        market_vol    = metrics[:market_vols] .* 100,
        heston_vol    = metrics[:heston_vols] .* 100,
        vol_error     = (metrics[:heston_vols] .- metrics[:market_vols]) .* 100,
        market_price  = metrics[:market_prices],
        heston_price  = metrics[:heston_prices],
        price_error   = metrics[:heston_prices] .- metrics[:market_prices]
    )

    detailed_file = joinpath(run_folder, "detailed_$(period_name).csv")
    CSV.write(detailed_file, detailed_df)
end

# ---------------------- #
# [6] Plots              #
# ---------------------- #

println("\n[6] Creating validation plots...")

plot_w = get(config, "output", Dict())["plot_size"] |> x -> x === nothing ? 1400 : get(x, "width", 1400)
plot_h = get(config, "output", Dict())["plot_size"] |> x -> x === nothing ? 1200 : get(x, "height", 1200)

# Plot 1: Vol RMSE over periods
p1 = plot(
    1:length(validation_metrics),
    [m[:vol_rmse] for m in validation_metrics];
    xlabel="Validation Period",
    ylabel="Vol RMSE (% points)",
    title="Model Performance Over Time",
    marker=:circle, markersize=6, linewidth=2, legend=false,
    xticks=(1:length(validation_metrics), [m[:name] for m in validation_metrics]),
    xrotation=45
)

# Plot 2: Calibration vol error histogram
calib_vol_errors = (calib_metrics[:heston_vols] .- calib_metrics[:market_vols]) .* 100
p2 = histogram(
    calib_vol_errors;
    xlabel="Vol Error (% points)",
    ylabel="Frequency",
    title="Calibration Period: Vol Error Distribution",
    legend=false, bins=20
)

# Plot 3: Market vs Heston vols (calibration)
p3 = scatter(
    calib_metrics[:market_vols] .* 100,
    calib_metrics[:heston_vols] .* 100;
    xlabel="Market Vol (%)", ylabel="Heston Vol (%)",
    title="Calibration Period: Market vs Heston",
    legend=false, markersize=4, alpha=0.6
)
plot!(p3, [0, 100], [0, 100]; linestyle=:dash, color=:red, label="Perfect fit")

# Plot 4: RMSE comparison (no StatsPlots dependency)
names_vec  = [m[:name] for m in validation_metrics]
vol_rmse   = [m[:vol_rmse]  for m in validation_metrics]
price_rmse = [m[:price_rmse] for m in validation_metrics]

p4 = bar(
    names_vec,
    [vol_rmse, price_rmse];
    xlabel="Validation Period", ylabel="RMSE",
    title="Vol RMSE vs Price RMSE",
    label=["Vol RMSE (% pts)" "Price RMSE (\$)"],
    xrotation=45, bar_width=0.8, legend=:topright
)

combined_plot = plot(p1, p2, p3, p4; layout=(2,2), size=(plot_w, plot_h))
plot_path = joinpath(run_folder, "validation_results.png")
savefig(combined_plot, plot_path)
println("✓ Validation plots saved to: $plot_path")

# ---------------------- #
# [7] Summary            #
# ---------------------- #

println("\n" * "="^70)
println("Multi-Period Validation Complete!")
println("="^70)
println("\nResults saved to: $run_folder")
println("\nValidation Summary:")
for metrics in validation_metrics
    println("  $(metrics[:name]):")
    @printf("    Vol RMSE: %.2f%% points\n", metrics[:vol_rmse])
    @printf("    Price RMSE: \$%.2f\n",     metrics[:price_rmse])
end
println("\n" * "="^70)
