using Hedgehog
using Dates
using Printf
using Random
using Statistics

println("="^60)
println("Heston Calibration: Synthetic Market Test")
println("="^60)

# ===== Step 1: Define TRUE Heston Parameters =====
println("\n[Step 1] Setting up TRUE Heston parameters...")
println("-"^60)

reference_date = Date(2024, 1, 1)
spot = 100.0
rate = 0.03

# TRUE parameters (what we'll try to recover)
true_params = (
    v0 = 0.04,      # 20% initial vol
    κ = 3.0,        # Mean reversion speed
    θ = 0.0225,     # 15% long-term vol
    σ = 0.4,        # Vol-of-vol
    ρ = -0.6        # Correlation
)

println("TRUE Heston parameters:")
@printf("  v₀ (initial variance):   %.6f (%.2f%% vol)\n", true_params.v0, sqrt(true_params.v0)*100)
@printf("  κ  (mean reversion):     %.6f\n", true_params.κ)
@printf("  θ  (long-term variance): %.6f (%.2f%% vol)\n", true_params.θ, sqrt(true_params.θ)*100)
@printf("  σ  (vol-of-vol):         %.6f\n", true_params.σ)
@printf("  ρ  (correlation):        %.6f\n", true_params.ρ)

# ===== Step 2: Create TRUE Heston Market =====
println("\n[Step 2] Creating synthetic market with TRUE Heston model...")
println("-"^60)

true_heston = HestonInputs(
    reference_date,
    rate,
    spot,
    true_params.v0,
    true_params.κ,
    true_params.θ,
    true_params.σ,
    true_params.ρ
)

# ===== Step 3: Generate Option Grid =====
println("\n[Step 3] Defining option grid...")
println("-"^60)

# Create a realistic grid of strikes and maturities
strikes = [
    # OTM puts, ATM, ITM calls
    80.0, 85.0, 90.0, 95.0, 100.0, 105.0, 110.0, 115.0, 120.0
]

expiry_dates = [
    reference_date + Month(3),   # 3 months
    reference_date + Month(6),   # 6 months
    reference_date + Year(1),    # 1 year
    reference_date + Year(2),    # 2 years
]

# Generate all combinations
payoffs = VanillaOption[]
for expiry in expiry_dates
    for strike in strikes
        # Use puts for OTM (K < S) and calls for ITM (K >= S)
        call_put = strike < spot ? Put() : Call()
        push!(payoffs, VanillaOption(strike, expiry, European(), call_put, Spot()))
    end
end

println("Generated $(length(payoffs)) option contracts")
println("  Expiries: $(length(expiry_dates))")
println("  Strikes per expiry: $(length(strikes))")

# ===== Step 4: Price Options with TRUE Heston =====
println("\n[Step 4] Pricing options with TRUE Heston model...")
println("-"^60)

pricing_method = CarrMadan(1.0, 32.0, HestonDynamics())

println("Pricing $(length(payoffs)) options using Carr-Madan...")
market_prices = [
    solve(PricingProblem(payoff, true_heston), pricing_method).price
    for payoff in payoffs
]
println("✓ All options priced")

# ===== Step 5: Convert to Implied Vols =====
println("\n[Step 5] Converting prices to implied volatilities...")
println("-"^60)

println("Inverting Black-Scholes for implied vols...")
implied_vols = Float64[]
for (payoff, price) in zip(payoffs, market_prices)
    dummy_inputs = BlackScholesInputs(reference_date, rate, spot, 0.2)
    basket = BasketPricingProblem([payoff], dummy_inputs)
    
    calib = CalibrationProblem(
        basket,
        BlackScholesAnalytic(),
        [VolLens(1,1)],
        [price],
        [0.2]
    )
    
    iv = solve(calib, RootFinderAlgo()).u
    push!(implied_vols, iv)
end
println("✓ Implied vols calculated")

# Show sample of the implied vol surface
println("\nSample implied vols (1-year expiry):")
println("Strike | Type | Impl Vol | Price")
println("-------|------|----------|-------")
one_year_expiry = reference_date + Year(1)
one_year_idx = findfirst(p -> Date(Dates.epochms2datetime(p.expiry)) == one_year_expiry, payoffs)
for i in 0:8
    idx = one_year_idx + i
    payoff = payoffs[idx]
    cp_str = isa(payoff.call_put, Call) ? "Call" : "Put "
    @printf("%6.1f | %s | %8.4f | %6.2f\n",
            payoff.strike, cp_str, implied_vols[idx], market_prices[idx])
end

# ===== Step 6: Create MarketVolSurface =====
println("\n[Step 6] Creating MarketVolSurface from synthetic data...")
println("-"^60)

market_surface = MarketVolSurface(
    reference_date,
    spot,
    payoffs,
    implied_vols,
    market_prices,
    metadata=Dict(
        :source => "Synthetic Heston",
        :true_params => true_params
    )
)

println("✓ Market surface created")
summary(market_surface)

# ===== Step 7: Calibrate with WRONG Initial Guess =====
println("\n[Step 7] Calibrating Heston with WRONG initial guess...")
println("-"^60)

# Use deliberately wrong initial guess
initial_guess = (
    v0 = 0.06,      # Off by 50%
    κ = 1.5,        # Off by 50%
    θ = 0.04,       # Off by ~80%
    σ = 0.6,        # Off by 50%
    ρ = -0.3        # Off by 50%
)

println("Initial guess (deliberately wrong):")
@printf("  v₀ = %.6f  (true: %.6f, error: %+.1f%%)\n", 
        initial_guess.v0, true_params.v0, 
        (initial_guess.v0/true_params.v0 - 1)*100)
@printf("  κ  = %.6f  (true: %.6f, error: %+.1f%%)\n", 
        initial_guess.κ, true_params.κ, 
        (initial_guess.κ/true_params.κ - 1)*100)
@printf("  θ  = %.6f  (true: %.6f, error: %+.1f%%)\n", 
        initial_guess.θ, true_params.θ, 
        (initial_guess.θ/true_params.θ - 1)*100)
@printf("  σ  = %.6f  (true: %.6f, error: %+.1f%%)\n", 
        initial_guess.σ, true_params.σ, 
        (initial_guess.σ/true_params.σ - 1)*100)
@printf("  ρ  = %.6f  (true: %.6f, error: %+.1f%%)\n", 
        initial_guess.ρ, true_params.ρ, 
        (initial_guess.ρ/true_params.ρ - 1)*100)

println("\nCalibrating... (this may take 30-60 seconds)")

result = calibrate_heston(
    market_surface,
    rate,
    initial_guess,
    pricing_method=CarrMadan(1.0, 32.0, HestonDynamics())
)

println("✓ Calibration complete!")

# ===== Step 8: Compare Results =====
println("\n[Step 8] Comparing calibrated vs TRUE parameters...")
println("="^60)

calibrated = (
    v0 = result.u[1],
    κ = result.u[2],
    θ = result.u[3],
    σ = result.u[4],
    ρ = result.u[5]
)

println("\nParameter | TRUE     | Calibrated | Abs Error | Rel Error")
println("----------|----------|------------|-----------|----------")
@printf("v₀        | %.6f | %.6f   | %.6f  | %6.2f%%\n",
        true_params.v0, calibrated.v0,
        abs(calibrated.v0 - true_params.v0),
        abs(calibrated.v0 - true_params.v0)/true_params.v0 * 100)
@printf("κ         | %.6f | %.6f   | %.6f  | %6.2f%%\n",
        true_params.κ, calibrated.κ,
        abs(calibrated.κ - true_params.κ),
        abs(calibrated.κ - true_params.κ)/true_params.κ * 100)
@printf("θ         | %.6f | %.6f   | %.6f  | %6.2f%%\n",
        true_params.θ, calibrated.θ,
        abs(calibrated.θ - true_params.θ),
        abs(calibrated.θ - true_params.θ)/true_params.θ * 100)
@printf("σ         | %.6f | %.6f   | %.6f  | %6.2f%%\n",
        true_params.σ, calibrated.σ,
        abs(calibrated.σ - true_params.σ),
        abs(calibrated.σ - true_params.σ)/true_params.σ * 100)
@printf("ρ         | %.6f | %.6f   | %.6f  | %6.2f%%\n",
        true_params.ρ, calibrated.ρ,
        abs(calibrated.ρ - true_params.ρ),
        abs(calibrated.ρ - true_params.ρ)/abs(true_params.ρ) * 100)

println("\nObjective function value: $(result.objective)")

# ===== Step 9: Validate with Pricing Errors =====
println("\n[Step 9] Validating calibration quality...")
println("="^60)

calibrated_heston = HestonInputs(
    reference_date,
    rate,
    spot,
    calibrated.v0,
    calibrated.κ,
    calibrated.θ,
    calibrated.σ,
    calibrated.ρ
)

# Price all options with calibrated parameters
calibrated_prices = [
    solve(PricingProblem(payoff, calibrated_heston), pricing_method).price
    for payoff in payoffs
]

# Calculate pricing errors
abs_errors = abs.(calibrated_prices .- market_prices)
rel_errors = abs_errors ./ market_prices .* 100

println("\nPricing error statistics:")
@printf("  Mean absolute error: %.6f\n", mean(abs_errors))
@printf("  Max absolute error:  %.6f\n", maximum(abs_errors))
@printf("  Mean relative error: %.4f%%\n", mean(rel_errors))
@printf("  Max relative error:  %.4f%%\n", maximum(rel_errors))

# Show worst cases
println("\nWorst 5 pricing errors:")
println("Strike | Expiry | Type | Market | Calibrated | Abs Err | Rel Err")
println("-------|--------|------|--------|------------|---------|--------")
worst_indices = sortperm(abs_errors, rev=true)[1:5]
for idx in worst_indices
    payoff = payoffs[idx]
    expiry_date = Date(Dates.epochms2datetime(payoff.expiry))
    years = yearfrac(reference_date, expiry_date)
    months = round(Int, years * 12)
    cp_str = isa(payoff.call_put, Call) ? "Call" : "Put "
    
    @printf("%6.1f | %5dM | %s | %6.2f | %10.2f | %7.4f | %6.2f%%\n",
            payoff.strike, months, cp_str,
            market_prices[idx], calibrated_prices[idx],
            abs_errors[idx], rel_errors[idx])
end

println("\n" * "="^60)
println("Calibration Test Complete!")
println("="^60)

# ===== Step 10: Summary Assessment =====
println("\n[Assessment]")
max_rel_error = maximum([
    abs(calibrated.v0 - true_params.v0)/true_params.v0,
    abs(calibrated.κ - true_params.κ)/true_params.κ,
    abs(calibrated.θ - true_params.θ)/true_params.θ,
    abs(calibrated.σ - true_params.σ)/true_params.σ,
    abs(calibrated.ρ - true_params.ρ)/abs(true_params.ρ)
]) * 100

if max_rel_error < 1.0
    println("✓ EXCELLENT: Parameters recovered within 1% error")
elseif max_rel_error < 5.0
    println("✓ GOOD: Parameters recovered within 5% error")
elseif max_rel_error < 10.0
    println("⚠ ACCEPTABLE: Parameters recovered within 10% error")
else
    println("✗ POOR: Parameter errors exceed 10%")
end

@printf("\nMax parameter error: %.2f%%\n", max_rel_error)
@printf("Max pricing error: %.4f%%\n", maximum(rel_errors))