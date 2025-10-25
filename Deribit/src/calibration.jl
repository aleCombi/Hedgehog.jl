# calibration.jl
# Heston model calibration wrapper functions

using Dates
using Printf
using Statistics          # <-- needed for median
using Hedgehog

"""
    HestonCalibrationResult
...
"""
struct HestonCalibrationResult
    v0::Float64
    κ::Float64
    θ::Float64
    σ::Float64
    ρ::Float64
    reference_date::DateTime
    spot::Float64
    rate::Float64
    objective_value::Float64
    return_code::Symbol
    n_quotes::Int
    parquet_file::String
end

"""
    calibrate_heston(market_surface, rate, initial_params; lb=nothing, ub=nothing, parquet_file="", spot_override=nothing)
    -> HestonCalibrationResult
"""
function calibrate_heston(market_surface, rate, initial_params;
                          lb=nothing, ub=nothing, parquet_file="",
                          spot_override::Union{Nothing,Real}=nothing)
    nopt = length(market_surface.quotes)
    @assert nopt > 0 "Empty market surface."

    println("Calibrating Heston model on $nopt options...")

    # Infer spot from shortest-maturity forwards (median), unless overridden
    spot_est = if spot_override === nothing
        expiries    = unique(q.payoff.expiry for q in market_surface.quotes)
        Tmin        = minimum(expiries)
        fwd_bucket  = [q.forward for q in market_surface.quotes if q.payoff.expiry == Tmin]
        @assert !isempty(fwd_bucket) "Cannot infer spot: no quotes at the shortest expiry."
        median(fwd_bucket)
    else
        Float64(spot_override)
    end

    # Library calibrator (forward-based surface; pass spot and rate explicitly)
    result = Hedgehog.calibrate_heston(
        market_surface,
        initial_params;
        spot = spot_est,
        rate = rate,
        lb   = lb,
        ub   = ub
    )

    reference_date = Dates.epochms2datetime(market_surface.reference_date)

    return HestonCalibrationResult(
        result.u[1],  # v0
        result.u[2],  # κ
        result.u[3],  # θ
        result.u[4],  # σ
        result.u[5],  # ρ
        reference_date,
        spot_est,
        rate,
        result.objective,
        Symbol(result.retcode),
        nopt,
        parquet_file
    )
end

"""
    to_heston_inputs(calib::HestonCalibrationResult) -> HestonInputs
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
    @printf("  κ  = %.6f\n",  calib.κ)
    @printf("  θ  = %.6f  (%.2f%% vol)\n", calib.θ, sqrt(calib.θ) * 100)
    @printf("  σ  = %.6f\n",  calib.σ)
    @printf("  ρ  = %.6f\n",  calib.ρ)
    println("\nOptimization:")
    @printf("  Objective: %.6f\n", calib.objective_value)
    @printf("  Status:    %s\n", string(calib.return_code))
    println("="^70)
end

"""
    save_calibration_params(calib::HestonCalibrationResult, filepath::String;
                            calib_date="", calib_file="")
"""
function save_calibration_params(calib::HestonCalibrationResult, filepath::String;
                                 calib_date="", calib_file="")
    open(filepath, "w") do io
        println(io, "Heston Calibration Results")
        println(io, "="^70)
        if !isempty(calib_date); println(io, "Calibration date: $calib_date"); end
        if !isempty(calib_file); println(io, "Calibration file: $calib_file"); end
        println(io, "Reference date: $(calib.reference_date)")
        println(io, "Spot price: $(calib.spot)")
        println(io, "Risk-free rate: $(calib.rate)")
        println(io, "Number of quotes: $(calib.n_quotes)")
        println(io, "\nCalibrated Parameters:")
        @printf(io, "  v₀ = %.6f  (%.2f%% vol)\n", calib.v0, sqrt(calib.v0) * 100)
        @printf(io, "  κ  = %.6f\n",  calib.κ)
        @printf(io, "  θ  = %.6f  (%.2f%% vol)\n", calib.θ, sqrt(calib.θ) * 100)
        @printf(io, "  σ  = %.6f\n",  calib.σ)
        @printf(io, "  ρ  = %.6f\n",  calib.ρ)
        println(io, "\nOptimization result:")
        println(io, "  Objective value: $(calib.objective_value)")
        println(io, "  Return code: $(calib.return_code)")
    end
    println("✓ Parameters saved to: $filepath")
end

"""
    get_param_tuple(calib::HestonCalibrationResult) -> NamedTuple
"""
get_param_tuple(calib::HestonCalibrationResult) =
    (v0=calib.v0, κ=calib.κ, θ=calib.θ, σ=calib.σ, ρ=calib.ρ)
