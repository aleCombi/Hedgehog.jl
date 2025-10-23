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
                         selection="closest")
    parquet_file = find_parquet_file(base_path, date_str, underlying; 
                                     time_filter=time_filter, selection=selection)
    println("Loading data from: $(basename(parquet_file))")
    mkt = Hedgehog.load_deribit_parquet(parquet_file; rate=rate, filter_params=filter_params)
    return mkt, parquet_file
end