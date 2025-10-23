# validation_scheduling.jl
# Time period parsing and validation scheduling utilities

using Dates

const MS_PER_MIN  = 60_000
const MS_PER_HOUR = 3_600_000
const MS_PER_DAY  = 86_400_000

"""
    parse_datetime(s::AbstractString) -> DateTime

Parse datetime from various formats:
- "2025-10-21 12:00:00"
- "2025-10-21T12:00:00"

# Example
```julia
dt = parse_datetime("2025-10-21 12:00:00")
dt = parse_datetime("2025-10-21T12:00:00")
```
"""
function parse_datetime(s::AbstractString)
    str = strip(s)
    try
        return DateTime(str)  # supports both " " and "T"
    catch
        try
            return DateTime(str, dateformat"yyyy-mm-dd HH:MM:SS")
        catch
            return DateTime(str, dateformat"yyyy-mm-ddTHH:MM:SS")
        end
    end
end

"""
    parse_period(s::AbstractString) -> Period

Parse period string in format "<int><unit>" where unit is m/h/d.

# Examples
```julia
parse_period("5m")   # -> Minute(5)
parse_period("2h")   # -> Hour(2)
parse_period("1d")   # -> Day(1)
parse_period("30m")  # -> Minute(30)
```
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
    period_ms(p::Period) -> Int

Convert a Period to milliseconds.

# Example
```julia
period_ms(Minute(5))  # -> 300_000
period_ms(Hour(2))    # -> 7_200_000
period_ms(Day(1))     # -> 86_400_000
```
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
    format_delta_label(calib_dt::DateTime, vdt::DateTime) -> String

Format a human-readable ΔT label showing time difference from calibration anchor 
and absolute timestamp.

Only non-zero components are shown (except when everything is zero).

# Example
```julia
calib = DateTime("2025-10-21 12:00:00")
valid = DateTime("2025-10-22 14:05:03")
format_delta_label(calib, valid)
# -> "ΔT=+1d 2h 05m 03s @ 2025-10-22 14:05:03"
```
"""
function format_delta_label(calib_dt::DateTime, vdt::DateTime)::String
    ms = Dates.value(vdt - calib_dt)
    sign = ms < 0 ? "-" : "+"
    absms = abs(ms)
    d  = absms ÷ MS_PER_DAY
    r1 = absms % MS_PER_DAY
    h  = r1 ÷ MS_PER_HOUR
    r2 = r1 % MS_PER_HOUR
    m  = r2 ÷ MS_PER_MIN
    s  = (r2 % MS_PER_MIN) ÷ 1000

    parts = String[]
    d > 0 && push!(parts, "$(d)d")
    h > 0 && push!(parts, "$(h)h")
    (m > 0 || (d==0 && h==0 && (m>0 || s>0))) && push!(parts, @sprintf("%02dm", m))
    (s > 0 || isempty(parts)) && push!(parts, @sprintf("%02ds", s))

    stamp = Dates.format(vdt, dateformat"yyyy-mm-dd HH:MM:SS")
    return "ΔT=$(sign)$(join(parts, " ")) @ $(stamp)"
end

"""
    generate_validation_times(validation_config::Dict, calib_dt::DateTime) 
    -> Vector{DateTime}

Generate validation times based on config specification.

Supports three modes:
1. **Schedule mode** (preferred): Periodic schedule with `every` and `for` parameters
2. **Explicit times**: List of specific datetime strings
3. **Hours ahead**: Simple list of hours from calibration time

# Arguments
- `validation_config`: Dict with validation settings from config.yaml
- `calib_dt`: Calibration anchor datetime

# Returns
Vector of DateTime objects for validation

# Config Format

## Option A: Schedule (recommended)
```yaml
validation:
  schedule:
    every: "5m"        # "15m", "30m", "1h", "2h", "6h", "1d"
    for: "6h"          # horizon from anchor
    start_at: null     # optional override anchor; null uses calib_dt
    max_steps: null    # optional cap; null = unlimited
    selection: "floor" # "closest" or "floor"
```

## Option B: Explicit times
```yaml
validation:
  validation_times:
    - "2025-10-21 13:00:00"
    - "2025-10-21 15:00:00"
```

## Option C: Hours ahead
```yaml
validation:
  hours_ahead: [1, 2, 3, 4, 5, 6]
```

# Example
```julia
config = Dict(
    "schedule" => Dict(
        "every" => "30m",
        "for" => "6h",
        "start_at" => nothing,
        "max_steps" => nothing
    )
)
times = generate_validation_times(config, DateTime("2025-10-21 12:00:00"))
# Returns 12 times: 12:30, 13:00, 13:30, ..., 18:00
```
"""
function generate_validation_times(validation_config::Dict, calib_dt::DateTime)
    validation_times = DateTime[]

    # Mode 1: Schedule (preferred)
    if haskey(validation_config, "schedule") && validation_config["schedule"] !== nothing
        sched = validation_config["schedule"]
        every_str = sched["every"]
        for_str = sched["for"]
        start_at = get(sched, "start_at", nothing)
        max_steps = get(sched, "max_steps", nothing)

        step_period = parse_period(every_str)
        horizon = parse_period(for_str)

        anchor_dt = start_at === nothing ? calib_dt : parse_datetime(start_at)

        total_ms = period_ms(horizon)
        step_ms = period_ms(step_period)
        nsteps = max(0, Int(floor(total_ms / step_ms)))
        if max_steps !== nothing
            nsteps = min(nsteps, Int(max_steps))
        end

        for k in 1:nsteps
            push!(validation_times, anchor_dt + k * step_period)
        end

    # Mode 2: Explicit times
    elseif haskey(validation_config, "validation_times")
        for vstr in validation_config["validation_times"]
            push!(validation_times, parse_datetime(vstr))
        end

    # Mode 3: Hours ahead
    elseif haskey(validation_config, "hours_ahead")
        for h in validation_config["hours_ahead"]
            push!(validation_times, calib_dt + Hour(h))
        end
    end

    return validation_times
end