# data_loading.jl
# Functions for discovering and loading Deribit parquet data files

using Dates
using Hedgehog

"""
    extract_file_dt(fname::AbstractString) -> (Union{Date,Nothing}, Union{Time,Nothing})

Extract date and time from a filename like "batch_20251021-120022707313.parquet".
Returns (Date, Time) if parsable, otherwise (nothing, nothing).
Only the first 6 time digits (HHMMSS) are parsed.

# Example
```julia
date, time = extract_file_dt("batch_20251021-120022707313.parquet")
# Returns: (Date("2025-10-21"), Time("12:00:22"))
```
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

Find a parquet file matching the specified date and underlying asset.

Searches in: `<base_path>/<root>/data_parquet/deribit_chain/date=YYYY-MM-DD/underlying=<underlying>/*.parquet`

# Arguments
- `base_path`: Root directory containing data folders
- `date_str`: Date string in "YYYY-MM-DD" format
- `underlying`: Asset symbol (e.g., "BTC", "ETH")
- `time_filter`: Optional time string "HH:MM:SS" to filter by time of day
- `selection`: Selection mode when multiple files exist:
  - `"closest"`: Pick file with time closest to target time (default)
  - `"floor"`: Pick latest file not after target time (or earliest if none before)

# Returns
Path to the selected parquet file

# Example
```julia
file = find_parquet_file("/data/deribit", "2025-10-21", "BTC"; 
                         time_filter="12:00:00", selection="floor")
```
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

using Dates, DataFrames, Parquet2

############################
# Filtering configuration  #
############################

"""
    FilterParams(; min_days=0, max_years=Inf, min_moneyness=0.0,
                   max_moneyness=Inf, max_spread_pct=nothing)

Holds filtering parameters for Deribit option chains.

- `min_days` / `max_years`: expiry window relative to reference timestamp
- `min_moneyness` / `max_moneyness`: strike / spot bounds
- `max_spread_pct`: optional bid/ask spread limit (e.g. 0.25 = 25%)
"""
Base.@kwdef struct FilterParams
    min_days::Int = 0
    max_years::Float64 = Inf
    min_moneyness::Float64 = 0.0
    max_moneyness::Float64 = Inf
    max_spread_pct::Union{Nothing,Float64} = nothing
end

"""
    apply_deribit_filters(df; ref_dt, surface_spot, params::FilterParams)

Return a filtered DataFrame based on the given parameters.
If all parameters are "empty" (min_days=0, max_years=Inf, etc.), this effectively returns the same DataFrame.
"""
function apply_deribit_filters(df; ref_dt::DateTime, surface_spot::Real, params::FilterParams)
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

    return filter(df) do row
        expiry_dt = DateTime(row.expiry) + Hour(8)
        mny = row.strike / surface_spot
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

function load_deribit_parquet(
    parquet_file::String;
    rate::Float64 = 0.0,
    params::FilterParams = FilterParams(),  # empty filter by default
    check_mark::Bool = true,
    price_tol_usd::Float64 = 10.0
)
    df = DataFrame(Parquet2.Dataset(parquet_file))

    ref_dt = DateTime(df.ts[1])
    surface_spot = df.underlying_price[1]

    # Basic validity: mark and IV must exist and be > 0
    df_valid = filter(row ->
        !ismissing(row.mark_price) && row.mark_price > 0 &&
        !ismissing(row.mark_iv) && row.mark_iv > 0,
        df
    )

    # Apply filters (no-op if params is empty)
    df_filtered = apply_deribit_filters(df_valid;
        ref_dt=ref_dt, surface_spot=surface_spot, params=params)

    strikes, expiries, call_puts, implied_vols = Float64[], DateTime[], Hedgehog.AbstractCallPut[], Float64[]
    bids, asks = Float64[], Float64[]
    n_checked, n_ok = 0, 0
    bad_rows = Int[]

    for (i, row) in enumerate(eachrow(df_filtered))
        strike = Float64(row.strike)
        expiry = DateTime(row.expiry) + Hour(8)  # 08:00 UTC
        cp     = row.option_type == "C" ? Call() : Put()
        vol    = row.mark_iv / 100.0
        row_spot = row.underlying_price

        push!(strikes, strike)
        push!(expiries, expiry)
        push!(call_puts, cp)
        push!(implied_vols, vol)
        push!(bids, (!ismissing(row.bid_price) && row.bid_price>0) ? row.bid_price*row_spot : NaN)
        push!(asks, (!ismissing(row.ask_price) && row.ask_price>0) ? row.ask_price*row_spot : NaN)

        if check_mark
            try
                ref_t   = DateTime(row.ts)
                mark_usd = row.mark_price * row_spot
                payoff    = VanillaOption(strike, expiry, European(), cp, Spot())
                bs_inputs = BlackScholesInputs(ref_t, rate, row_spot, vol)
                bs_usd    = solve(PricingProblem(payoff, bs_inputs), BlackScholesAnalytic()).price
                n_checked += 1
                (abs(bs_usd - mark_usd) <= price_tol_usd) ? (n_ok += 1) : push!(bad_rows, i)
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
        surface_spot,
        strikes,
        expiries,
        call_puts,
        implied_vols,
        rate,
        bids=bids,
        asks=asks,
        metadata=metadata
    )
end


"""
    load_market_data(base_path, date_str, underlying, time_filter, rate, filter_params; 
                     selection="closest")
    -> (MarketVolSurface, parquet_path)

Load market data from a parquet file with the specified filters.

# Arguments
- `base_path`: Root directory containing data folders
- `date_str`: Date string in "YYYY-MM-DD" format
- `underlying`: Asset symbol (e.g., "BTC", "ETH")
- `time_filter`: Time string "HH:MM:SS" for file selection
- `rate`: Risk-free rate
- `filter_params`: Named tuple with filtering parameters:
  - `min_days`: Minimum days to expiry
  - `max_years`: Maximum years to expiry
  - `min_moneyness`: Minimum moneyness ratio
  - `max_moneyness`: Maximum moneyness ratio
- `selection`: File selection mode ("closest" or "floor")

# Returns
Tuple of (MarketVolSurface, parquet_file_path)

# Example
```julia
filter_params = (min_days=14, max_years=2, min_moneyness=0.8, max_moneyness=1.2)
surface, path = load_market_data("/data", "2025-10-21", "BTC", "12:00:00", 
                                  0.03, filter_params)
```
"""
function load_market_data(base_path, date_str, underlying, time_filter, rate, filter_params;
                          selection="closest", check_mark=true, price_tol_usd=10.0)
    parquet_file = find_parquet_file(base_path, date_str, underlying;
                                     time_filter=time_filter, selection=selection)
    println("Loading data from: $(basename(parquet_file))")
    mkt = load_deribit_parquet(parquet_file;
        rate=rate,
        params=filter_params,          # FilterParams() for empty filter or pass `nothing` if you changed API
        check_mark=check_mark,
        price_tol_usd=price_tol_usd
    )
    return mkt, parquet_file
end
