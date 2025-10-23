# deribit/vol_arb_probe.jl
using Revise, Hedgehog
using DataFrames
using Dates
using YAML
using CSV
using Printf

println("="^70)
println("Deribit BTC Options: Mispricing & Island Probe (Calibration Snapshot)")
println("="^70)

# ------------------------------- #
# [0] Load configuration & setup  #
# ------------------------------- #

config_path = joinpath(@__DIR__, "config.yaml")
isfile(config_path) || error("Configuration file not found: $config_path")
config = YAML.load_file(config_path)
println("\n[0a] Loaded configuration from: $config_path")

timestamp  = Dates.format(now(), "yyyymmdd_HHMMSS")
run_folder = joinpath(@__DIR__, "runs", "arb_probe_$timestamp")
mkpath(run_folder)
println("[0b] Created run folder: $run_folder")

# Optional thresholds (overridable via config.yaml: arb_probe section)
default_probe = Dict(
    "price_abs_threshold" => 50.0,   # currency units
    "price_rel_threshold" => 0.02,   # 2% of market price
    "vol_pp_threshold"    => 0.50    # vol percentage points
)
arb_probe_cfg = get(config, "arb_probe", default_probe)
price_abs_thr = Float64(get(arb_probe_cfg, "price_abs_threshold", default_probe["price_abs_threshold"]))
price_rel_thr = Float64(get(arb_probe_cfg, "price_rel_threshold", default_probe["price_rel_threshold"]))
vol_pp_thr    = Float64(get(arb_probe_cfg, "vol_pp_threshold",    default_probe["vol_pp_threshold"]))

# ------------------------------- #
# [1] Shared helpers (match main) #
# ------------------------------- #

# Extract (Date, Time) from a filename like "batch_YYYYMMDD-HHMMSSxxxxxx.parquet"
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

Searches:
  <root>/data_parquet/deribit_chain/date=YYYY-MM-DD/underlying=<underlying>/*.parquet

selection:
  - "closest" (default): pick file with time closest to target time on that date
  - "floor"           : pick the latest file not after target time (fallback to earliest if none)
"""
function find_parquet_file(base_path, date_str, underlying; time_filter=nothing, selection::AbstractString="closest")
    date_obj    = Date(date_str)
    date_folder = Dates.format(date_obj, dateformat"yyyy-mm-dd")

    # find matching directories
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
            endswith(f, ".parquet") && push!(parquet_files, joinpath(dir, f))
        end
    end
    isempty(parquet_files) && error("No parquet files found in $(join(matching_dirs, ';'))")

    # if no time filter, return first
    if time_filter === nothing
        return parquet_files[1]
    end

    target_time = Time(time_filter)
    candidates = NamedTuple{(:file,:time)}[]
    for fp in parquet_files
        b = basename(fp)
        fdate, ftime = extract_file_dt(b)
        (fdate === nothing || ftime === nothing) && continue
        fdate == date_obj && push!(candidates, (file=fp, time=ftime))
    end
    if isempty(candidates)
        @warn "No files match the date/time filter; using first available parquet."
        return parquet_files[1]
    end

    sel = lowercase(selection)
    if sel == "closest"
        diffs = [abs(Dates.value(c.time - target_time)) for c in candidates]
        chosen = candidates[argmin(diffs)].file
        println("Selected calibration file closest to $time_filter: $(basename(chosen))")
        return chosen
    elseif sel == "floor"
        not_after = filter(c -> c.time <= target_time, candidates)
        if !isempty(not_after)
            idx = argmax([Dates.value(c.time) for c in not_after])
            chosen = not_after[idx].file
            println("Selected calibration file (floor) at/before $time_filter: $(basename(chosen))")
            return chosen
        else
            idx = argmin([Dates.value(c.time) for c in candidates])
            chosen = candidates[idx].file
            println("No file at/before $time_filter; selected earliest: $(basename(chosen))")
            return chosen
        end
    else
        @warn "Unknown selection='$selection'; defaulting to 'closest'."
        diffs = [abs(Dates.value(c.time - target_time)) for c in candidates]
        chosen = candidates[argmin(diffs)].file
        println("Selected calibration file closest to $time_filter: $(basename(chosen))")
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

# ------------------------------- #
# [2] Load calibration snapshot   #
# ------------------------------- #

base_path  = config["data"]["base_path"]
underlying = config["data"]["underlying"]
calib_date = config["calibration"]["date"]
calib_time = get(config["calibration"], "time_filter", nothing)
rate       = config["market"]["risk_free_rate"]

# SAME FILTERING as the main script, driven by config
filter_params = (
    min_days      = config["filtering"]["min_days"],
    max_years     = config["filtering"]["max_years"],
    min_moneyness = config["filtering"]["min_moneyness"],
    max_moneyness = config["filtering"]["max_moneyness"]
)

# Same selection mode used by the main script (validation.schedule.selection if present)
selection_mode = if haskey(config, "validation") &&
                    haskey(config["validation"], "schedule") &&
                    config["validation"]["schedule"] !== nothing &&
                    haskey(config["validation"]["schedule"], "selection")
    config["validation"]["schedule"]["selection"]
else
    "closest"
end

mkt, parquet_file = load_market_data(
    base_path, calib_date, underlying, calib_time, rate, filter_params; selection=selection_mode
)

println("\nCalibration Data Summary:")
summary(mkt)

reference_date = Dates.epochms2datetime(mkt.reference_date)
spot           = mkt.spot

# ------------------------------- #
# [3] Calibrate Heston (t = 0)    #
# ------------------------------- #

initial_params = config["calibration"]["initial_params"]
lb_config      = config["calibration"]["lower_bounds"]
ub_config      = config["calibration"]["upper_bounds"]

result = Hedgehog.calibrate_heston(
    mkt, rate,
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

p = (v0=result.u[1], κ=result.u[2], θ=result.u[3], σ=result.u[4], ρ=result.u[5])
println("\n✓ Calibration complete!")
@printf("  v₀=%.6f (%.2f%%), κ=%.3f, θ=%.6f (%.2f%%), σ=%.6f, ρ=%.3f\n",
        p.v0, sqrt(p.v0)*100, p.κ, p.θ, sqrt(p.θ)*100, p.σ, p.ρ)

H = HestonInputs(reference_date, rate, spot, p.v0, p.κ, p.θ, p.σ, p.ρ)
method = CarrMadan(config["pricing"]["carr_madan"]["alpha"],
                   config["pricing"]["carr_madan"]["grid_size"],
                   HestonDynamics())

# ------------------------------- #
# [4] Price + mispricing flags    #
# ------------------------------- #

# Model vs market prices
model_prices  = [solve(PricingProblem(q.payoff, H), method).price for q in mkt.quotes]
market_prices = [q.price for q in mkt.quotes]
market_vols   = [q.implied_vol for q in mkt.quotes]

# Back out model-implied vols via BS inversion
iv_cfg = config["implied_vol"]
model_vols = Float64[]
for (i, q) in enumerate(mkt.quotes)
    try
        bs_inputs = BlackScholesInputs(reference_date, rate, spot, iv_cfg["initial_guess"])
        basket = BasketPricingProblem([q.payoff], bs_inputs)
        calib = CalibrationProblem(
            basket, BlackScholesAnalytic(),
            [VolLens(1,1)],
            [model_prices[i]],
            [iv_cfg["initial_guess"]];
            lb=[iv_cfg["lower_bound"]],
            ub=[iv_cfg["upper_bound"]]
        )
        push!(model_vols, solve(calib, RootFinderAlgo()).u)
    catch
        push!(model_vols, market_vols[i])
    end
end

# Errors and thresholds
price_err      = model_prices .- market_prices    # >0 => market underpriced relative to model
rel_price_err  = price_err ./ market_prices
vol_err_pp     = (model_vols .- market_vols) .* 100.0  # vol percentage points

# Reason-level flags
price_abs_flag = abs.(price_err) .>= price_abs_thr
price_rel_flag = abs.(rel_price_err) .>= price_rel_thr
vol_pp_flag    = abs.(vol_err_pp) .>= vol_pp_thr

# Polarity
underpriced_price = (price_err .> 0) .& (price_abs_flag .| price_rel_flag)
overpriced_price  = (price_err .< 0) .& (price_abs_flag .| price_rel_flag)

underpriced_vol = (vol_err_pp .> 0) .& vol_pp_flag    # model vol > market vol
overpriced_vol  = (vol_err_pp .< 0) .& vol_pp_flag    # model vol < market vol

# Combined (price OR vol)
underpriced_any = underpriced_price .| underpriced_vol
overpriced_any  = overpriced_price  .| overpriced_vol

# Build dataframe for calibration snapshot
calib_df = DataFrame(
    expiry_date     = [Date(Dates.epochms2datetime(q.payoff.expiry)) for q in mkt.quotes],
    expiry_ts       = [q.payoff.expiry   for q in mkt.quotes],
    strike          = [q.payoff.strike   for q in mkt.quotes],
    option_type     = [isa(q.payoff.call_put, Call) ? "Call" : "Put" for q in mkt.quotes],
    spot            = fill(spot, length(mkt.quotes)),
    market_price    = market_prices,
    model_price     = model_prices,
    price_error     = price_err,
    rel_price_error = rel_price_err,
    market_vol      = market_vols .* 100,
    model_vol       = model_vols  .* 100,
    vol_error_pp    = vol_err_pp,
    price_abs_flag  = price_abs_flag,
    price_rel_flag  = price_rel_flag,
    vol_pp_flag     = vol_pp_flag,
    underpriced_price = underpriced_price,
    overpriced_price  = overpriced_price,
    underpriced_vol   = underpriced_vol,
    overpriced_vol    = overpriced_vol,
    underpriced_any   = underpriced_any,
    overpriced_any    = overpriced_any
)

# ------------------------------- #
# [5] Island detection helpers    #
# ------------------------------- #

# Given boolean columns for "cheap" and "rich", find island points per expiry (by strike)
function find_islands(df::DataFrame; cheap_col::Symbol, rich_col::Symbol)
    out = DataFrame()
    for sub in groupby(df, :expiry_date)
        s = sort(sub, :strike)
        n = nrow(s)
        if n >= 3
            for i in 2:(n-1)
                left  = s[i-1, :]
                mid   = s[i,   :]
                right = s[i+1, :]

                sign_left  = left[cheap_col] ?  1 : (left[rich_col] ? -1 : 0)
                sign_mid   = mid[cheap_col]  ?  1 : (mid[rich_col]  ? -1 : 0)
                sign_right = right[cheap_col] ? 1 : (right[rich_col] ? -1 : 0)

                if sign_mid != 0 && sign_left == -sign_mid && sign_right == -sign_mid
                    push!(out, mid)
                end
            end
        end
    end
    return out
end

islands_price    = find_islands(calib_df; cheap_col=:underpriced_price, rich_col=:overpriced_price)
islands_vol      = find_islands(calib_df; cheap_col=:underpriced_vol,   rich_col=:overpriced_vol)
islands_combined = find_islands(calib_df; cheap_col=:underpriced_any,   rich_col=:overpriced_any)

# ------------------------------- #
# [6] Save outputs + console log  #
# ------------------------------- #

mispricing_csv       = joinpath(run_folder, "mispricing_calibration.csv")
islands_price_csv    = joinpath(run_folder, "islands_price_calibration.csv")
islands_vol_csv      = joinpath(run_folder, "islands_vol_calibration.csv")
islands_comb_csv     = joinpath(run_folder, "islands_combined_calibration.csv")

CSV.write(mispricing_csv, calib_df)
CSV.write(islands_price_csv, islands_price)
CSV.write(islands_vol_csv, islands_vol)
CSV.write(islands_comb_csv, islands_combined)

println("\n✓ Mispricing table written to: $mispricing_csv")
println("✓ Price-based island candidates written to: $islands_price_csv")
println("✓ Vol-based island candidates written to:   $islands_vol_csv")
println("✓ Combined island candidates written to:    $islands_comb_csv")

# Console summary (plain text, no special table printing; no currency symbol)
cheap_p = count(calib_df.underpriced_price)
rich_p  = count(calib_df.overpriced_price)
cheap_v = count(calib_df.underpriced_vol)
rich_v  = count(calib_df.overpriced_vol)

println("\nSummary (Calibration):")
@printf("  Underpriced by price: %d\n", cheap_p)
@printf("  Overpriced  by price: %d\n", rich_p)
@printf("  Underpriced by vol:   %d\n", cheap_v)
@printf("  Overpriced  by vol:   %d\n", rich_v)
@printf("  Price-islands:        %d\n", nrow(islands_price))
@printf("  Vol-islands:          %d\n", nrow(islands_vol))
@printf("  Combined islands:     %d\n", nrow(islands_combined))

# Top-5 extremes by absolute price error (currency units)
function print_top_by_price(df::DataFrame; k::Int=5, heading::AbstractString="")
    idx = sortperm(abs.(df.price_error); rev=true)
    n = min(k, length(idx))
    println(heading)
    for j in 1:n
        i = idx[j]
        @printf("    %2d) %s spot=%8.2f  K=%8.2f  T=%s  price_err=%9.2f  rel_err=%7.2f%%  vol_err_pp=%7.2f\n",
            j, df.option_type[i], df.spot[i], df.strike[i],
            string(df.expiry_date[i]),
            df.price_error[i], df.rel_price_error[i]*100, df.vol_error_pp[i])
    end
end

# Top-5 extremes by absolute vol error (percentage points)
function print_top_by_vol(df::DataFrame; k::Int=5, heading::AbstractString="")
    idx = sortperm(abs.(df.vol_error_pp); rev=true)
    n = min(k, length(idx))
    println(heading)
    for j in 1:n
        i = idx[j]
        @printf("    %2d) %s spot=%8.2f  K=%8.2f  T=%s  vol_err_pp=%7.2f  price_err=%9.2f  rel_err=%7.2f%%\n",
            j, df.option_type[i], df.spot[i], df.strike[i],
            string(df.expiry_date[i]),
            df.vol_error_pp[i], df.price_error[i], df.rel_price_error[i]*100)
    end
end

print_top_by_price(calib_df; k=5, heading="\nTop 5 by absolute price error (currency units):")
print_top_by_vol(calib_df;   k=5, heading="\nTop 5 by absolute vol error (percentage points):")

println("\n" * "="^70)
println("Arb probe complete · results in: $run_folder")
println("="^70)

# ===== Heatmaps: market - model (vol and price) =====
using Plots

# Axes
strikes  = sort(unique(calib_df.strike))
expiries = sort(unique(calib_df.expiry_date))

# Lookups
ix_s = Dict(s => j for (j, s) in enumerate(strikes))
ix_e = Dict(e => i for (i, e) in enumerate(expiries))

# Matrices (rows: expiry, cols: strike)
Z_vol   = fill(NaN, length(expiries), length(strikes))   # percentage points
Z_price = fill(NaN, length(expiries), length(strikes))   # currency units

for r in eachrow(calib_df)
    i = ix_e[r.expiry_date]
    j = ix_s[r.strike]
    # market - model
    Z_vol[i, j]   = r.market_vol  - r.model_vol
    Z_price[i, j] = r.market_price - r.model_price
end

# Symmetric color limits around zero
vol_max   = maximum(abs, filter(!isnan, vec(Z_vol)))
price_max = maximum(abs, filter(!isnan, vec(Z_price)))

# Helpful tick labels
ylabels = string.(expiries)  # show dates on y-axis

# Choose a diverging gradient if available; fall back to default otherwise
grad = :RdBu  # common diverging scheme in Plots

# VOL heatmap (percentage points)
p_vol = heatmap(
    strikes, ylabels, Z_vol;
    xlabel = "Strike",
    ylabel = "Expiry (date)",
    title  = "Market − Model Vol (percentage points)",
    color  = cgrad(grad, rev=true),
    clims  = (-vol_max, vol_max),
    colorbar_title = "pp",
    framestyle = :box
)

# PRICE heatmap (currency units)
p_price = heatmap(
    strikes, ylabels, Z_price;
    xlabel = "Strike",
    ylabel = "Expiry (date)",
    title  = "Market − Model Price (currency units)",
    color  = cgrad(grad, rev=true),
    clims  = (-price_max, price_max),
    colorbar_title = "units",
    framestyle = :box
)

# Save
heatmap_vol_path   = joinpath(run_folder, "heatmap_vol_market_minus_model.png")
heatmap_price_path = joinpath(run_folder, "heatmap_price_market_minus_model.png")
savefig(p_vol,   heatmap_vol_path)
savefig(p_price, heatmap_price_path)

println("\n✓ Vol heatmap saved to:    $heatmap_vol_path")
println("✓ Price heatmap saved to:  $heatmap_price_path")
