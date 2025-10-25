# config.jl
# Configuration loading and extraction utilities

using YAML
using Dates

"""
    load_config(config_path::String) -> Dict

Load and validate YAML configuration file.

# Arguments
- `config_path`: Path to config.yaml file

# Returns
Configuration dictionary

# Example
```julia
config = load_config("config.yaml")
```
"""
function load_config(config_path::String)
    isfile(config_path) || error("Configuration file not found: $config_path")
    config = YAML.load_file(config_path)
    println("✓ Loaded configuration from: $config_path")
    return config
end

"""
    extract_filter_params(config::Dict) -> NamedTuple

Extract market data filtering parameters from config.

# Returns
Named tuple with fields:
- `min_days`: Minimum days to expiry
- `max_years`: Maximum years to expiry
- `min_moneyness`: Minimum moneyness ratio
- `max_moneyness`: Maximum moneyness ratio

# Example
```julia
filter_params = extract_filter_params(config)
# Returns: (min_days=14, max_years=2, min_moneyness=0.8, max_moneyness=1.2)
```
"""
function extract_filter_params(config::Dict)
    if !haskey(config, "filtering")
        return FilterParams()
    end

    filtering = config["filtering"]
    getv(k, default) = haskey(filtering, k) ? filtering[k] : default

    return FilterParams(
        min_days       = Int(getv("min_days", 0)),
        max_years      = Float64(getv("max_years", Inf)),
        min_moneyness  = Float64(getv("min_moneyness", 0.0)),
        max_moneyness  = Float64(getv("max_moneyness", Inf)),
        max_spread_pct = getv("max_spread_pct", nothing)
    )
end


"""
    extract_iv_config(config::Dict) -> Dict

Extract implied volatility solver configuration.

# Returns
Dictionary with keys:
- `"initial_guess"`: Starting vol for solver
- `"lower_bound"`: Lower bound for vol
- `"upper_bound"`: Upper bound for vol

# Example
```julia
iv_config = extract_iv_config(config)
# Returns: Dict("initial_guess" => 0.5, "lower_bound" => 0.05, "upper_bound" => 2.0)
```
"""
function extract_iv_config(config::Dict)
    iv = config["implied_vol"]
    return Dict(
        "initial_guess" => iv["initial_guess"],
        "lower_bound" => iv["lower_bound"],
        "upper_bound" => iv["upper_bound"]
    )
end

"""
    extract_calibration_config(config::Dict) -> NamedTuple

Extract calibration configuration.

# Returns
Named tuple with fields:
- `initial_params`: Named tuple (v0, κ, θ, σ, ρ)
- `lower_bounds`: Vector [v0, κ, θ, σ, ρ]
- `upper_bounds`: Vector [v0, κ, θ, σ, ρ]

# Example
```julia
calib_cfg = extract_calibration_config(config)
initial = calib_cfg.initial_params
lb = calib_cfg.lower_bounds
ub = calib_cfg.upper_bounds
```
"""
function extract_calibration_config(config::Dict)
    calib = config["calibration"]
    initial = calib["initial_params"]
    lb = calib["lower_bounds"]
    ub = calib["upper_bounds"]
    
    return (
        initial_params = (
            v0 = initial["v0"],
            κ = initial["kappa"],
            θ = initial["theta"],
            σ = initial["sigma"],
            ρ = initial["rho"]
        ),
        lower_bounds = [
            lb["v0"],
            lb["kappa"],
            lb["theta"],
            lb["sigma"],
            lb["rho"]
        ],
        upper_bounds = [
            ub["v0"],
            ub["kappa"],
            ub["theta"],
            ub["sigma"],
            ub["rho"]
        ]
    )
end

"""
    extract_validation_config(config::Dict) -> Union{Dict,Nothing}

Extract validation configuration if enabled.

# Returns
Validation config Dict if enabled, nothing otherwise

# Example
```julia
val_cfg = extract_validation_config(config)
if val_cfg !== nothing
    # Process validation
end
```
"""
function extract_validation_config(config::Dict)
    if haskey(config, "validation") && config["validation"]["enabled"]
        return config["validation"]
    end
    return nothing
end

"""
    extract_mispricing_config(config::Dict) -> NamedTuple

Extract mispricing detection thresholds.

# Returns
Named tuple with fields:
- `price_abs_threshold`: Absolute price threshold (currency units)
- `price_rel_threshold`: Relative price threshold (fraction, e.g., 0.02)
- `vol_pp_threshold`: Vol threshold (percentage points)

# Default values
If not present in config, uses defaults:
- price_abs: 50.0
- price_rel: 0.02 (2%)
- vol_pp: 0.50

# Example
```julia
thresholds = extract_mispricing_config(config)
# Returns: (price_abs_threshold=50.0, price_rel_threshold=0.02, vol_pp_threshold=0.5)
```
"""
function extract_mispricing_config(config::Dict)
    default_probe = Dict(
        "price_abs_threshold" => 50.0,
        "price_rel_threshold" => 0.02,
        "vol_pp_threshold" => 0.50
    )
    
    arb_probe = get(config, "arb_probe", default_probe)
    
    return (
        price_abs_threshold = Float64(get(arb_probe, "price_abs_threshold", 
                                         default_probe["price_abs_threshold"])),
        price_rel_threshold = Float64(get(arb_probe, "price_rel_threshold", 
                                         default_probe["price_rel_threshold"])),
        vol_pp_threshold = Float64(get(arb_probe, "vol_pp_threshold", 
                                       default_probe["vol_pp_threshold"]))
    )
end

"""
    get_selection_mode(config::Dict) -> String

Get file selection mode from validation config.

# Returns
"closest" or "floor", defaulting to "closest" if not specified

# Example
```julia
selection = get_selection_mode(config)
# Returns: "floor" or "closest"
```
"""
function get_selection_mode(config::Dict)
    if haskey(config, "validation") &&
       haskey(config["validation"], "schedule") &&
       config["validation"]["schedule"] !== nothing &&
       haskey(config["validation"]["schedule"], "selection")
        return config["validation"]["schedule"]["selection"]
    end
    return "closest"
end

"""
    get_pricing_method(config::Dict) -> CarrMadan

Extract pricing method configuration and create pricing method object.

Currently only supports CarrMadan method.

# Returns
CarrMadan pricing method configured from config

# Example
```julia
method = get_pricing_method(config)
price = solve(PricingProblem(payoff, heston_inputs), method)
```
"""
function get_pricing_method(config::Dict)
    pricing = config["pricing"]
    
    if pricing["method"] == "CarrMadan"
        cm = pricing["carr_madan"]
        return CarrMadan(
            cm["alpha"],
            cm["grid_size"],
            HestonDynamics()
        )
    else
        error("Unsupported pricing method: $(pricing["method"])")
    end
end

"""
    create_run_folder(base_dir::String, prefix::String) -> String

Create timestamped run folder for output.

# Arguments
- `base_dir`: Base directory (e.g., "deribit")
- `prefix`: Folder name prefix (e.g., "heston_calib", "arb_probe")

# Returns
Path to created folder

# Example
```julia
run_folder = create_run_folder("deribit", "heston_calib")
# Creates: deribit/runs/heston_calib_20251023_143022/
```
"""
function create_run_folder(base_dir::String, prefix::String)
    timestamp = Dates.format(now(), "yyyymmdd_HHMMSS")
    run_folder = joinpath(base_dir, "runs", "$(prefix)_$(timestamp)")
    mkpath(run_folder)
    println("✓ Created run folder: $run_folder")
    return run_folder
end

"""
    save_config_copy(config_path::String, run_folder::String)

Copy configuration file to run folder for reproducibility.

# Example
```julia
save_config_copy("config.yaml", run_folder)
```
"""
function save_config_copy(config_path::String, run_folder::String)
    cp(config_path, joinpath(run_folder, "config.yaml"); force=true)
    println("✓ Config copied to run folder")
end

"""
    get_plot_size(config::Dict) -> Tuple{Int,Int}

Extract plot size from config.

# Returns
Tuple of (width, height) in pixels

# Defaults
(1400, 1200) if not specified in config

# Example
```julia
width, height = get_plot_size(config)
plot(...; size=(width, height))
```
"""
function get_plot_size(config::Dict)
    if haskey(config, "output") && config["output"] !== nothing &&
       haskey(config["output"], "plot_size") && config["output"]["plot_size"] !== nothing
        ps = config["output"]["plot_size"]
        return (get(ps, "width", 1400), get(ps, "height", 1200))
    end
    return (1400, 1200)
end