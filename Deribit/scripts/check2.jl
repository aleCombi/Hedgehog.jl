# test_bid_ask_units.jl
using Hedgehog, Dates, Symbolics

# Load one quote from your parquet file
parquet_file = "C:/repos/DeribitVols/data/downloaded/all_20251022-192655/20251020-120020Z/data_parquet/deribit_chain/date=2025-10-20/underlying=BTC/batch_20251020-120021343926.parquet"
# check.jl
# check.jl
# check.jl
using Parquet2, DataFrames, Hedgehog, Dates, Printf

df = DataFrame(Parquet2.Dataset(parquet_file))

df_test = filter(row -> 
    !ismissing(row.mark_price) && 
    !ismissing(row.mark_iv) &&
    !ismissing(row.bid_price) &&
    !ismissing(row.ask_price) &&
    row.mark_price > 0,
    df)[1:100, :]


for row in eachrow(df_test)
    rate = 0.00
    spot = row.underlying_price
    ref_date = DateTime(row.ts)
    strike = row.strike
    expiry = DateTime(row.expiry) + Hour(8)

    mark_iv = row.mark_iv / 100.0
    mark_price = row.mark_price
    bid = row.bid_price
    ask = row.ask_price
    call_put = row.option_type == "C" ? Call() : Put()
    payoff = VanillaOption(strike, expiry, European(), call_put, Spot())
    bs_inputs = BlackScholesInputs(ref_date, rate, spot, mark_iv)
    bs_price = solve(PricingProblem(payoff, bs_inputs), BlackScholesAnalytic()).price
    
    println("\nK=$strike, exp=$expiry")
    @printf("  mark_price:       %.4f BTC\n", mark_price)
    @printf("  mark_price*spot:  %.2f USD\n", mark_price * spot)
    @printf("  BS(mark_iv):      %.2f USD\n", bs_price)
    @printf("  Match? %s (diff=%.2f)\n", 
            abs(mark_price * spot - bs_price) < 10.0 ? "✓" : "✗",
            abs(mark_price * spot - bs_price))
    println()
    @printf("  bid:        %.4f BTC  →  %.2f USD\n", bid, bid * spot)
    @printf("  ask:        %.4f BTC  →  %.2f USD\n", ask, ask * spot)

    @variables rate spot strike vol
    payoff = VanillaOption(strike, expiry, European(), call_put, Spot())
    bs_inputs = BlackScholesInputs(ref_date, rate, spot, mark_iv)
    bs_price = solve(PricingProblem(payoff, bs_inputs), BlackScholesAnalytic()).price
    # @show bs_price
end