# data_loading.jl
# Functions for discovering and loading Deribit parquet data files
using Dates
using Hedgehog
using DataFrames
using Parquet2
using Statistics

"""
    extract_file_dt(fname::AbstractString) -> (Union{Date,Nothing}, Union{Time,Nothing})

Extract date and time from a filename like "batch_20251021-120022707313.parquet".
Returns (Date, Time) if parsable, otherwise (nothing, nothing).
Only the first 6 time digits (HHMMSS) are parsed.
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

Searches in: `<base_path>/<root>/data_parquet/deribit_chain/date=YYYY-MM-DD/underlying=<underlying>/*.parquet`
"""
function find_parquet_file(base_path, date_str, underlying; 
                           time_filter=nothing, selection::AbstractString="closest")
    date_obj = Date(date_str)
    date_folder = Dates.format(date_obj, dateformat"yyyy-mm-dd")

    # Find all matching directories
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

    # Collect parquet files
    parquet_files = String[]
    for dir in matching_dirs
        for f in readdir(dir)
            endswith(f, ".parquet") || continue
            push!(parquet_files, joinpath(dir, f))
        end
    end
    isempty(parquet_files) && error("No parquet files found in $(join(matching_dirs, ';'))")

    # If no time filter, just return the first one
    if time_filter === nothing
        return parquet_files[1]
    end

    target_time = Time(time_filter)

    # Collect candidates for the given date
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
        not_after = filter(c -> c.time <= target_time, candidates)
        if !isempty(not_after)
            idx = argmax([Dates.value(c.time) for c in not_after])
            chosen = not_after[idx].file
            println("Selected file (floor) at or before $time_filter: $(basename(chosen))")
            return chosen
        else
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

############################
# Filtering configuration  #
############################

"""
    FilterParams(; min_days=0, max_years=Inf, min_moneyness=0.0,
                   max_moneyness=Inf, max_spread_pct=nothing)

- min_days / max_years: expiry window relative to reference timestamp
- min_moneyness / max_moneyness: strike / forward bounds (per-quote)
- max_spread_pct: optional bid/ask spread limit (e.g. 0.25 = 25%)
"""
Base.@kwdef struct FilterParams
    min_days::Int = 0
    max_years::Float64 = Inf
    min_moneyness::Float64 = 0.0
    max_moneyness::Float64 = Inf
    max_spread_pct::Union{Nothing,Float64} = nothing
end

"""
    apply_deribit_filters(df; ref_dt, params::FilterParams)

Return a filtered DataFrame based on the given parameters.
Uses each row's forward for moneyness.
Assumes `df.underlying_price` exists (rename below if your column differs).
"""
function apply_deribit_filters(df; ref_dt::DateTime, params::FilterParams)
    # If it's the "empty" filter, just return df directly
    if params.min_days == 0 && params.max_years == Inf &&
       params.min_moneyness == 0.0 && params.max_moneyness == Inf &&
       params.max_spread_pct === nothing
        return df
    end

    # Construct expiry window (if finite)
    min_expiry_dt = ref_dt + Day(params.min_days)
    max_expiry_dt = isfinite(params.max_years) ?
                    (ref_dt + Year(floor(Int, params.max_years)) +
                     Day(round(Int, (params.max_years - floor(params.max_years)) * 365))) :
                    DateTime(9999,12,31)

    # NOTE: adjust column name if your parquet uses a different forward column.
    has_forward = hasproperty(df, :underlying_price)
    @assert has_forward "Expected column `underlying_price` in dataframe."

    return filter(df) do row
        expiry_dt = DateTime(row.expiry) + Hour(8) # Deribit 08:00 UTC convention
        fwd = row.underlying_price
        (ismissing(fwd) || fwd <= 0) && return false

        mny = row.strike / fwd
        meets_basic = (expiry_dt >= min_expiry_dt) &&
                      (expiry_dt <= max_expiry_dt) &&
                      (mny >= params.min_moneyness) &&
                      (mny <= params.max_moneyness)

        if params.max_spread_pct === nothing || !meets_basic
            return meets_basic
        end

        if !ismissing(row.bid_price) && !ismissing(row.ask_price) &&
           row.bid_price > 0 && row.ask_price > row.bid_price &&
           !ismissing(row.mark_price) && row.mark_price > 0
            # Spread computed vs mark (same units as raw parquet)
            spread_pct = (row.ask_price - row.bid_price) / row.mark_price
            return meets_basic && (spread_pct <= params.max_spread_pct)
        else
            return false
        end
    end
end

############################
# Main Loader
############################

"""
    load_deribit_parquet(parquet_file; rate=0.0, params=FilterParams(), check_mark=true, price_tol_usd=10.0)
    -> MarketVolSurface

Loads a parquet snapshot and constructs a MarketVolSurface with per-quote forwards.
- Assumes `underlying_price` column exists (futures; we ignore DF and set rate=0 for pricing checks).
- Re-pricing check uses BS with spot := forward, rate = 0.0.
"""
function load_deribit_parquet(
    parquet_file::String;
    rate::Float64 = 0.0,                    # ignored in pricing (kept for signature parity)
    params::FilterParams = FilterParams(),  # empty filter by default
    check_mark::Bool = true,
    price_tol_usd::Float64 = 10.0
)
    df = DataFrame(Parquet2.Dataset(parquet_file))
    @assert hasproperty(df, :underlying_price) "Expected `underlying_price` column in parquet."

    ref_dt = DateTime(df.ts[1])

    # Basic validity: mark and IV and forward must exist and be > 0
    df_valid = filter(row ->
        !ismissing(row.mark_price) && row.mark_price > 0 &&
        !ismissing(row.mark_iv) && row.mark_iv > 0 &&
        !ismissing(row.underlying_price) && row.underlying_price > 0,
        df
    )

    # Apply filters (no-op if params is empty)
    df_filtered = apply_deribit_filters(df_valid; ref_dt=ref_dt, params=params)

    strikes  = Float64[]
    expiries = DateTime[]
    call_puts = Hedgehog.AbstractCallPut[]
    implied_vols = Float64[]
    forwards = Float64[]
    bids, asks = Float64[], Float64[]

    n_checked, n_ok = 0, 0
    bad_rows = Int[]

    for (i, row) in enumerate(eachrow(df_filtered))
        strike = Float64(row.strike)
        expiry = DateTime(row.expiry) + Hour(8)      # 08:00 UTC
        cp     = row.option_type == "C" ? Call() : Put()
        vol    = row.mark_iv / 100.0
        fwd    = Float64(row.underlying_price)

        push!(strikes, strike)
        push!(expiries, expiry)
        push!(call_puts, cp)
        push!(implied_vols, vol)
        push!(forwards, fwd)

        # Keep bid/ask as provided (raw units). If you historically stored USD via *spot,
        # you can switch to *forward here. We keep raw to avoid double-guessing parquet semantics.
        push!(bids, (!ismissing(row.bid_price) && row.bid_price > 0) ? row.bid_price*fwd : NaN)
        push!(asks, (!ismissing(row.ask_price) && row.ask_price > 0) ? row.ask_price*fwd : NaN)

        if check_mark
            try
                ref_t = DateTime(row.ts)
                payoff    = VanillaOption(strike, expiry, European(), cp, Spot())

                # Zero-rate everywhere; price as BS with spot := forward.
                bs_inputs = BlackScholesInputs(ref_t, 0.0, fwd, vol)
                model_price = solve(PricingProblem(payoff, bs_inputs), BlackScholesAnalytic()).price

                # Compare in the same units as parquet mark_price.
                # If your parquet marks are quoted "per underlying", compare row.mark_price vs model_price.
                # If marks are USD and model_price is per-underlying, multiply both by fwd consistently.
                mark_ref = row.mark_price
                diff = abs(model_price - mark_ref)

                n_checked += 1
                (diff <= price_tol_usd) ? (n_ok += 1) : push!(bad_rows, i)
            catch
                push!(bad_rows, i)
            end
        end
    end

    metadata = Dict{Symbol,Any}(
        :source=>"Deribit",
        :underlying=>df.underlying[1],
        :data_file=>basename(parquet_file),
        :timestamp_ms=>df.ts[1],
        :original_count=>nrow(df),
        :filtered_count=>length(strikes),
        :ref_datetime=>string(ref_dt),
        :filters=>params,
        :check_enabled=>check_mark,
        :price_tol_usd=>price_tol_usd,
        :check_n_ok=>n_ok,
        :check_n_total=>n_checked,
        :check_bad_rows=>bad_rows
    )

    return MarketVolSurface(
        ref_dt,
        strikes,
        expiries,
        call_puts,
        forwards,
        implied_vols;
        bids=bids,
        asks=asks,
        metadata=metadata
    )
end

"""
    load_market_data(base_path, date_str, underlying, time_filter, rate, filter_params; selection="closest")
    -> (MarketVolSurface, parquet_path)

Wrapper that finds a parquet and loads it with the given filters.
`rate` is accepted for signature parity but ignored (we use zero-rate pricing elsewhere).
"""
function load_market_data(base_path, date_str, underlying, time_filter, rate, filter_params;
                          selection="closest", check_mark=true, price_tol_usd=10.0)
    parquet_file = find_parquet_file(base_path, date_str, underlying;
                                     time_filter=time_filter, selection=selection)
    println("Loading data from: $(basename(parquet_file))")
    mkt = load_deribit_parquet(parquet_file;
        rate=rate,
        params=filter_params,
        check_mark=check_mark,
        price_tol_usd=price_tol_usd
    )
    return mkt, parquet_file
end
