using Test, Dates

# --- price <-> iv roundtrip --------------------------------------------------
@testset "price<->iv roundtrip" begin
    ref, exp = Date(2025,1,1), Date(2025,7,1)
    rc = FlatRateCurve(0.02; reference_date=ref)
    for (S, K, σ) in ((100.0, 80.0, 0.2), (100.0, 100.0, 0.5), (100.0, 130.0, 1.0))
        opt = VanillaOption(K, exp, European(), Call(), Spot())
        p   = iv_to_price(opt, S, 0.02, σ, ref, BlackScholesAnalytic())
        σ2  = price_to_iv(opt, S, 0.02, p,  ref, BlackScholesAnalytic(); iv_guess=σ)
        @test isapprox(σ2, σ; rtol=1e-8, atol=1e-10)
    end
end

# --- normalization is price/F ------------------------------------------------
@testset "normalization is price/F" begin
    refD, exp = Date(2025,1,1), Date(2025,7,1)
    ref = to_ticks(refD)          # constructor expects Int64 ticks
    und = SpotObs(100.0)
    r   = 0.02
    opt = VanillaOption(100.0, exp, European(), Call(), Spot())

    vq = VolQuote(opt, und, r; mid_iv=0.4, reference_date=ref)

    p_abs = iv_to_price(vq, 0.4; normalize=false)
    F     = Hedgehog.underlying_forward(und, r, refD, exp)  # forward function accepts TimeType
    @test isapprox(iv_to_price(vq, 0.4; normalize=true), p_abs/F; rtol=1e-12)
end

# --- IV monotonicity warnings ------------------------------------------------
@testset "IV-price monotonicity warnings" begin
    ref = to_ticks(Date(2025,1,1))
    und = SpotObs(100.0); r = 0.02
    opt = VanillaOption(100.0, Date(2025,7,1), European(), Call(), Spot())

    # decreasing IVs and prices -> two warnings
    @test_logs (:warn, r"Price monotonicity") (:warn, r"IV monotonicity") VolQuote(
        opt, und, r;
        bid_iv=0.25, mid_iv=0.24, ask_iv=0.23,
        reference_date=ref,
        iv_monotonicity_handling=:warn,
        price_monotonicity_handling=:warn,
    )
end

# --- NaN storage policy ------------------------------------------------------
@testset "NaN storage policy" begin
    ref = to_ticks(Date(2025,1,1))
    und = SpotObs(100.0); r = 0.02
    opt = VanillaOption(100.0, Date(2025,7,1), European(), Call(), Spot())
    vq  = VolQuote(opt, und, r; mid_iv=0.3, reference_date=ref)
    @test isnan(vq.bid_price) && isnan(vq.bid_iv)
    @test isnan(vq.ask_price) && isnan(vq.ask_iv)
end

# --- inconsistency policy: warn + throw -------------------------------------
@testset "VolPrice/IV inconsistency policy" begin
    ref = to_ticks(Date(2025,1,1))
    und = SpotObs(100.0); r = 0.02
    exp = Date(2025,7,1)
    opt = VanillaOption(100.0, exp, European(), Call(), Spot())

    # baseline: consistent p & iv
    vq_base = VolQuote(opt, und, r; mid_iv=0.4, reference_date=ref, normalized_input=false)
    p_cons  = iv_to_price(vq_base, vq_base.mid_iv; normalize=false)

    # consistent under :warn (no log necessarily emitted)
    vq_ok = VolQuote(
        opt, und, r;
        mid_price=p_cons, mid_iv=0.4,
        reference_date=ref,
        normalized_input=false,
        vol_price_inconsistency_handling=:warn,
    )
    @test vq_ok isa VolQuote

    # force inconsistency by bumping price
    p_bad = p_cons * 1.15

    # warn path
    @test_logs (:warn, r"Inconsistent") VolQuote(
        opt, und, r;
        mid_price=p_bad, mid_iv=0.4,
        reference_date=ref,
        normalized_input=false,
        vol_price_inconsistency_handling=:warn,
    )

    # throw path
    @test_throws ArgumentError VolQuote(
        opt, und, r;
        mid_price=p_bad, mid_iv=0.4,
        reference_date=ref,
        normalized_input=false,
        vol_price_inconsistency_handling=:throw,
        abs_tol_p=1e-12,
    )
end

# --- allocations (small budget, not exact zero) ------------------------------
@testset "BS solve small alloc budget" begin
    refD, exp = Date(2025,1,1), Date(2025,7,1)
    rc = FlatRateCurve(0.02; reference_date=refD)
    mi = BlackScholesInputs(refD, rc, 100.0, 0.4)
    opt = VanillaOption(90.0, exp, European(), Call(), Spot())
    prob = PricingProblem(opt, mi)
    method = BlackScholesAnalytic()

    # keep tight but portable; if you consistently see 0, you can reduce this
    @test @allocated(solve(prob, method).price) ≤ 128
end
