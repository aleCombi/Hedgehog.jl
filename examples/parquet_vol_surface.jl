using Revise, Hedgehog
using DataFrames
using Parquet2
using Plots
using Statistics
using Printf
using Dates

println("="^70)
println("Deribit BTC Options: Heston Calibration & Vol Surface Visualization")
println("="^70)

# Load data
path_parquet = joinpath(@__DIR__, "..", "data", "deribit_btc_2025-10-21.parquet")

println("\n[1] Loading market data...")
market_surface = Hedgehog.load_deribit_parquet(
    path_parquet,
    rate=0.03,
    filter_params=(
        min_days=14,
        max_years=2.0,
        min_moneyness=0.8,
        max_moneyness=1.2
    )
)
summary(market_surface)

# Calibrate Heston
println("\n[2] Calibrating Heston model...")
println("This may take a few minutes...")

result = Hedgehog.calibrate_heston(
    market_surface,
    0.03,
     (v0=0.22, κ=10.0, θ=0.24, σ=2.0, ρ=-0.24)
)

calibrated_params = (
    v0 = result.u[1],
    κ = result.u[2],
    θ = result.u[3],
    σ = result.u[4],
    ρ = result.u[5]
)

println("\n✓ Calibration complete!")
println("\nCalibrated Heston parameters:")
@printf("  v₀ = %.6f (%.2f%% vol)\n", calibrated_params.v0, sqrt(calibrated_params.v0)*100)
@printf("  κ  = %.6f\n", calibrated_params.κ)
@printf("  θ  = %.6f (%.2f%% vol)\n", calibrated_params.θ, sqrt(calibrated_params.θ)*100)
@printf("  σ  = %.6f\n", calibrated_params.σ)
@printf("  ρ  = %.6f\n", calibrated_params.ρ)

# Calculate calibration quality
println("\n[3] Evaluating calibration quality...")

reference_date = Dates.epochms2datetime(market_surface.reference_date)
spot = market_surface.spot
rate = 0.03

calibrated_heston = HestonInputs(
    reference_date,
    rate,
    spot,
    calibrated_params.v0,
    calibrated_params.κ,
    calibrated_params.θ,
    calibrated_params.σ,
    calibrated_params.ρ
)

pricing_method = CarrMadan(1.0, 32.0, HestonDynamics())

# Price all options with calibrated Heston
println("Pricing $(length(market_surface.quotes)) options with calibrated model...")
market_vols = [q.implied_vol for q in market_surface.quotes]
market_prices = [q.price for q in market_surface.quotes]
heston_prices = [
    solve(PricingProblem(q.payoff, calibrated_heston), pricing_method).price
    for q in market_surface.quotes
]

# Calculate errors
price_errors = heston_prices .- market_prices
abs_price_errors = abs.(price_errors)
rel_price_errors = abs_price_errors ./ market_prices .* 100

# Back out implied vols from Heston prices
println("Computing implied vols from Heston prices...")
heston_vols = Float64[]
for (i, quoten) in enumerate(market_surface.quotes)
    dummy_inputs = BlackScholesInputs(reference_date, rate, spot, 0.5)
    basket = BasketPricingProblem([quoten.payoff], dummy_inputs)
    
    calib = CalibrationProblem(
        basket,
        BlackScholesAnalytic(),
        [VolLens(1,1)],
        [heston_prices[i]],
        [0.5]
    )
    
    heston_vol = solve(calib, RootFinderAlgo()).u
    push!(heston_vols, heston_vol)
end

vol_errors = (heston_vols .- market_vols) .* 100  # In percentage points
abs_vol_errors = abs.(vol_errors)

# Print statistics
println("\n" * "="^70)
println("CALIBRATION QUALITY METRICS")
println("="^70)

println("\nPrice Errors:")
@printf("  Mean Absolute Error:  \$%.4f\n", mean(abs_price_errors))
@printf("  RMSE:                 \$%.4f\n", sqrt(mean(price_errors.^2)))
@printf("  Max Absolute Error:   \$%.4f\n", maximum(abs_price_errors))
@printf("  Mean Relative Error:  %.2f%%\n", mean(rel_price_errors))
@printf("  Max Relative Error:   %.2f%%\n", maximum(rel_price_errors))

println("\nImplied Volatility Errors:")
@printf("  Mean Absolute Error:  %.2f%% points\n", mean(abs_vol_errors))
@printf("  RMSE:                 %.2f%% points\n", sqrt(mean(vol_errors.^2)))
@printf("  Max Absolute Error:   %.2f%% points\n", maximum(abs_vol_errors))

# Show worst fits
println("\nWorst 5 fits by volatility error:")
println("Strike | Expiry(Y) | Type | Market Vol | Heston Vol | Error")
println("-------|-----------|------|------------|------------|-------")
worst_indices = sortperm(abs_vol_errors, rev=true)[1:5]
for idx in worst_indices
    quoten = market_surface.quotes[idx]
    expiry_date = Date(Dates.epochms2datetime(quoten.payoff.expiry))
    years = yearfrac(Date(reference_date), expiry_date)
    cp_str = isa(quoten.payoff.call_put, Call) ? "Call" : "Put "
    
    @printf("%7.0f | %9.2f | %s | %9.2f%% | %9.2f%% | %+6.2f%%\n",
            quoten.payoff.strike, years, cp_str,
            market_vols[idx] * 100, heston_vols[idx] * 100, vol_errors[idx])
end

# Create 3D plots
println("\n[4] Creating 3D volatility surface plots...")

# Extract market data
market_strikes = [q.payoff.strike for q in market_surface.quotes]
market_expiries_dates = [Date(Dates.epochms2datetime(q.payoff.expiry)) for q in market_surface.quotes]
market_expiries_years = [yearfrac(Date(reference_date), exp) for exp in market_expiries_dates]
market_vols_pct = market_vols .* 100
heston_vols_pct = heston_vols .* 100

# Create grid for smooth Heston surface
k_min, k_max = extrema(market_strikes)
t_min, t_max = extrema(market_expiries_years)
k_range = k_max - k_min
t_range = t_max - t_min

strike_grid = range(k_min - 0.05*k_range, k_max + 0.05*k_range, length=40)
expiry_grid = range(max(t_min - 0.05*t_range, 0.02), t_max + 0.05*t_range, length=30)

println("Computing Heston surface on 40x30 grid...")
heston_surf = zeros(length(strike_grid), length(expiry_grid))

for (i, K) in enumerate(strike_grid)
    for (j, T_years) in enumerate(expiry_grid)
        expiry_date = Date(reference_date) + Day(round(Int, T_years * 365))
        
        # Determine call/put based on moneyness
        call_put = K < spot ? Put() : Call()
        payoff = VanillaOption(K, expiry_date, European(), call_put, Spot())
        
        # Price with Heston
        prob = PricingProblem(payoff, calibrated_heston)
        heston_price = solve(prob, pricing_method).price
        
        # Back out implied vol
        dummy_inputs = BlackScholesInputs(Date(reference_date), rate, spot, 0.5)
        basket = BasketPricingProblem([payoff], dummy_inputs)
        calib = CalibrationProblem(
            basket,
            BlackScholesAnalytic(),
            [VolLens(1,1)],
            [heston_price],
            [0.5]
        )
        
        try
            vol = solve(calib, RootFinderAlgo()).u
            heston_surf[i, j] = vol * 100
        catch
            heston_surf[i, j] = NaN
        end
    end
end

# Plot 1: Market vol surface (scatter)
p1 = scatter(
    market_strikes,
    market_expiries_years,
    market_vols_pct,
    xlabel="Strike",
    ylabel="Time to Expiry (years)",
    zlabel="Implied Vol (%)",
    title="Market Implied Volatility Surface\n(Deribit BTC Options)",
    marker=:circle,
    markersize=3,
    color=:viridis,
    camera=(30, 30),
    legend=false,
    size=(600, 500)
)

# Plot 2: Fitted Heston surface (smooth)
p2 = surface(
    strike_grid,
    expiry_grid,
    heston_surf',
    xlabel="Strike",
    ylabel="Time to Expiry (years)",
    zlabel="Implied Vol (%)",
    title="Fitted Heston Volatility Surface",
    color=:plasma,
    camera=(30, 30),
    legend=false,
    size=(600, 500)
)

# Plot 3: Market vs Heston overlay
p3 = surface(
    strike_grid,
    expiry_grid,
    heston_surf',
    xlabel="Strike",
    ylabel="Time to Expiry (years)",
    zlabel="Implied Vol (%)",
    title="Market (dots) vs Heston (surface)",
    color=:plasma,
    alpha=0.7,
    camera=(30, 30),
    legend=false,
    size=(600, 500)
)
scatter!(
    p3,
    market_strikes,
    market_expiries_years,
    market_vols_pct,
    marker=:circle,
    markersize=3,
    color=:red,
    label="Market"
)

# Plot 4: Errors
error_colors = [err > 0 ? :red : :blue for err in vol_errors]
p4 = scatter(
    market_strikes,
    market_expiries_years,
    abs_vol_errors,
    xlabel="Strike",
    ylabel="Time to Expiry (years)",
    zlabel="Abs Vol Error (% points)",
    title="Calibration Errors\n(RMSE: $(round(sqrt(mean(vol_errors.^2)), digits=2))% points)",
    marker=:circle,
    markersize=4,
    color=error_colors,
    camera=(30, 30),
    legend=false,
    size=(600, 500)
)

# Combine all plots
combined_plot = plot(p1, p2, p3, p4, layout=(2,2), size=(1200, 1000))

println("✓ Plots created")
display(combined_plot)

# Save plot
output_path = joinpath(@__DIR__, "heston_calibration_results.png")
savefig(combined_plot, output_path)
println("\n✓ Plot saved to: $output_path")

println("\n" * "="^70)
println("Analysis Complete!")
println("="^70)