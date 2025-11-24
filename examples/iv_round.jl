using Revise, Hedgehog, Dates

ref, expected = Date(2025,1,1), Date(2025,7,1)
rc = FlatRateCurve(0.02; reference_date=ref)
for (S, K, σ) in ((100.0, 80.0, 0.2), (100.0, 100.0, 0.5), (100.0, 130.0, 1.0))
    opt = VanillaOption(K, expected, European(), Call(), Spot())
    p   = iv_to_price(opt, S, 0.02, σ, ref, BlackScholesAnalytic())
    σ2  = price_to_iv(opt, S, 0.02, p, ref, BlackScholesAnalytic(); iv_guess=σ)
    @show isapprox(σ2, σ; rtol=1e-8, atol=1e-10)
end