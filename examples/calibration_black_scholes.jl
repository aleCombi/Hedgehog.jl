using Revise, Hedgehog2, Dates, Accessors
# True model inputs
# -- Market Inputs
reference_date = Date(2020, 1, 1)
rate = 0.2
spot = 100.0
sigma = 0.4
market = BlackScholesInputs(reference_date, rate, spot, sigma)

# -- Payoff
expiry = reference_date + Day(365)
strike = 100.0
payoff = VanillaOption(strike, expiry, European(), Call(), Spot())

# -- Pricing problem
pp = PricingProblem(payoff, market)
pricing_method =BlackScholesAnalytic()
# Generate market quote
price = solve(pp, pricing_method).price  # True model price

# Define calibration problem
calib_problem = Hedgehog2.CalibrationProblem(
    Hedgehog2.BasketPricingProblem([payoff], market),
    pricing_method,
    [@optic _.market.sigma],
    [price]
)

# Run calibration starting from wrong sigma
result = solve(calib_problem, [0.2])

# Output
@show sigma
@show result.u[1]
@show price
