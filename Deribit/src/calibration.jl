# calibration.jl
# Heston model calibration wrapper functions

using Dates
using Printf
using Hedgehog

"""
    HestonCalibrationResult

Container for Heston calibration results.

# Fields
- `v0`, `κ`, `θ`, `σ`, `ρ`: Calibrated Heston parameters
- `reference_date`: Market data reference date
- `spot`: Spot price
- `rate`: Risk-free rate
- `objective_value`: Final optimization objective
- `return_code`: Optimization return code (e.g., :success)
- `n_quotes`: Number of options used in calibration
- `parquet_file`: Source data file
"""
struct HestonCalibrationResult
    # Calibrated parameters
    v0::Float64
    κ::Float64
    θ::Float64
    σ::Float64
    ρ::Float64
    
    # Market info
    reference_date::DateTime
    spot::Float64
    rate::Float64
    
    # Optimization info
    objective_value::Float64
    return_code::Symbol
    n_quotes::Int
    
    # Source
    parquet_file::String
end

"""
    calibrate_heston(market_surface, rate, initial_params; lb, ub)
    -> HestonCalibrationResult

Calibrate Heston model to market data.

# Arguments
- `market_surface`: MarketVolSurface with market quotes
- `rate`: Risk-free rate
- `initial_params`: Named tuple with initial guesses (v0, κ, θ, σ, ρ)
- `lb`: Lower bounds vector [v0, κ, θ, σ, ρ]
- `ub`: Upper bounds vector [v0, κ, θ, σ, ρ]

# Returns
HestonCalibrationResult with calibrated parameters and metadata

# Example
```julia
initial = (v0=0.25, κ=20.0, θ=0.24, σ=5.0, ρ=-0.3)
lb = [0.04, 0.5, 0.04, 0.1, -0.99]
ub = [0.8, 80.0, 0.8, 15.0, 0.99]
result = calibrate_heston(mkt_surface, 0.03, initial; lb=lb, ub=ub)
```
"""
function calibrate_heston(market_surface, rate, initial_params; lb, ub, parquet_file="")
    println("Calibrating Heston model on $(length(market_surface.quotes)) options...")
    
    result = Hedgehog.calibrate_heston(
        market_surface,
        rate,
        initial_params;
        lb=lb,
        ub=ub
    )
    
    reference_date = Dates.epochms2datetime(market_surface.reference_date)
    spot = market_surface.spot
    
    return HestonCalibrationResult(
        result.u[1],  # v0
        result.u[2],  # κ
        result.u[3],  # θ
        result.u[4],  # σ
        result.u[5],  # ρ
        reference_date,
        spot,
        rate,
        result.objective,
        Symbol(result.retcode),  # Convert enum to Symbol
        length(market_surface.quotes),
        parquet_file
    )
end

"""
    to_heston_inputs(calib::HestonCalibrationResult) -> HestonInputs

Convert calibration result to HestonInputs for pricing.

# Example
```julia
calib_result = calibrate_heston(...)
heston_inputs = to_heston_inputs(calib_result)
price = solve(PricingProblem(payoff, heston_inputs), method)
```
"""
function to_heston_inputs(calib::HestonCalibrationResult)
    return HestonInputs(
        calib.reference_date,
        calib.rate,
        calib.spot,
        calib.v0,
        calib.κ,
        calib.θ,
        calib.σ,
        calib.ρ
    )
end

"""
    print_calibration_summary(calib::HestonCalibrationResult)

Print formatted calibration summary to stdout.
"""
function print_calibration_summary(calib::HestonCalibrationResult)
    println("\n" * "="^70)
    println("Heston Calibration Results")
    println("="^70)
    println("Reference date: $(calib.reference_date)")
    println("Spot price:     $(round(calib.spot, digits=2))")
    println("Risk-free rate: $(round(calib.rate * 100, digits=2))%")
    println("Quotes used:    $(calib.n_quotes)")
    println("\nCalibrated Parameters:")
    @printf("  v₀ = %.6f  (%.2f%% vol)\n", calib.v0, sqrt(calib.v0) * 100)
    @printf("  κ  = %.6f\n", calib.κ)
    @printf("  θ  = %.6f  (%.2f%% vol)\n", calib.θ, sqrt(calib.θ) * 100)
    @printf("  σ  = %.6f\n", calib.σ)
    @printf("  ρ  = %.6f\n", calib.ρ)
    println("\nOptimization:")
    @printf("  Objective: %.6f\n", calib.objective_value)
    @printf("  Status:    %s\n", calib.return_code)
    println("="^70)
end

"""
    save_calibration_params(calib::HestonCalibrationResult, filepath::String; 
                           calib_date="", calib_file="")

Save calibration parameters to a text file.

# Arguments
- `calib`: HestonCalibrationResult
- `filepath`: Output file path
- `calib_date`: Optional calibration date string for header
- `calib_file`: Optional calibration file basename for header
"""
function save_calibration_params(calib::HestonCalibrationResult, filepath::String;
                                calib_date="", calib_file="")
    open(filepath, "w") do io
        println(io, "Heston Calibration Results")
        println(io, "="^70)
        
        if !isempty(calib_date)
            println(io, "Calibration date: $calib_date")
        end
        if !isempty(calib_file)
            println(io, "Calibration file: $calib_file")
        end
        
        println(io, "Reference date: $(calib.reference_date)")
        println(io, "Spot price: $(calib.spot)")
        println(io, "Risk-free rate: $(calib.rate)")
        println(io, "Number of quotes: $(calib.n_quotes)")
        
        println(io, "\nCalibrated Parameters:")
        @printf(io, "  v₀ = %.6f  (%.2f%% vol)\n", calib.v0, sqrt(calib.v0) * 100)
        @printf(io, "  κ  = %.6f\n", calib.κ)
        @printf(io, "  θ  = %.6f  (%.2f%% vol)\n", calib.θ, sqrt(calib.θ) * 100)
        @printf(io, "  σ  = %.6f\n", calib.σ)
        @printf(io, "  ρ  = %.6f\n", calib.ρ)
        
        println(io, "\nOptimization result:")
        println(io, "  Objective value: $(calib.objective_value)")
        println(io, "  Return code: $(calib.return_code)")
    end
    println("✓ Parameters saved to: $filepath")
end

"""
    get_param_tuple(calib::HestonCalibrationResult) -> NamedTuple

Extract parameters as a named tuple.

# Returns
Named tuple with fields (v0, κ, θ, σ, ρ)

# Example
```julia
params = get_param_tuple(calib_result)
println("Initial variance: ", params.v0)
```
"""
function get_param_tuple(calib::HestonCalibrationResult)
    return (v0=calib.v0, κ=calib.κ, θ=calib.θ, σ=calib.σ, ρ=calib.ρ)
end