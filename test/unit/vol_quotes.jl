using Test, Dates, Logging

# --- price <-> iv roundtrip --------------------------------------------------
@testset "price<->iv roundtrip" begin
    ref, exp = Date(2025,1,1), Date(2025,7,1)
    rc = FlatRateCurve(0.02; reference_date=ref)
    for (S, K, σ) in ((100.0, 80.0, 0.2), (100.0, 100.0, 0.5), (100.0, 130.0, 1.0))
        opt = VanillaOption(K, exp, European(), Call(), Spot())
        p   = iv_to_price(opt, S, 0.02, σ, ref, BlackScholesAnalytic())
        σ2  = price_to_iv(opt, S, 0.02, p, ref, BlackScholesAnalytic(); iv_guess=σ)
        @test isapprox(σ2, σ; rtol=1e-8, atol=1e-10)
    end
end

# --- normalization is price/F ------------------------------------------------
@testset "normalization is price/F" begin
    refD, exp = Date(2025,1,1), Date(2025,7,1)
    ref = to_ticks(refD)
    und = SpotObs(100.0)
    r   = 0.02
    opt = VanillaOption(100.0, exp, European(), Call(), Spot())

    config = VolQuoteConfig(normalized_input=false)
    vq = VolQuote(opt, und, r; mid_iv=0.4, reference_date=ref, config=config)

    p_abs = iv_to_price(vq, 0.4; normalize=false)
    F     = Hedgehog.underlying_forward(und, r, refD, exp)
    @test isapprox(iv_to_price(vq, 0.4; normalize=true), p_abs/F; rtol=1e-12)
end

# --- IV monotonicity warnings ------------------------------------------------
@testset "IV-price monotonicity warnings" begin
    ref = to_ticks(Date(2025,1,1))
    und = SpotObs(100.0); r = 0.02
    opt = VanillaOption(100.0, Date(2025,7,1), European(), Call(), Spot())

    # decreasing IVs and prices -> two warnings
    config = VolQuoteConfig(
        iv_monotonicity_handling = :warn,
        price_monotonicity_handling = :warn
    )
    
    @test_logs (:warn, r"Price monotonicity") (:warn, r"IV monotonicity") VolQuote(
        opt, und, r;
        bid_iv=0.25, mid_iv=0.24, ask_iv=0.23,
        reference_date=ref,
        config=config
    )
end

# --- NaN storage policy ------------------------------------------------------
@testset "NaN storage policy" begin
    ref = to_ticks(Date(2025,1,1))
    und = SpotObs(100.0); r = 0.02
    opt = VanillaOption(100.0, Date(2025,7,1), European(), Call(), Spot())
    
    vq = VolQuote(opt, und, r; mid_iv=0.3, reference_date=ref) # default config
    
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
    config_base = VolQuoteConfig(normalized_input=false)
    vq_base = VolQuote(opt, und, r; mid_iv=0.4, reference_date=ref, config=config_base)
    p_cons  = iv_to_price(vq_base, vq_base.mid_iv; normalize=false)

    # consistent under :warn (no log necessarily emitted)
    config_ok = VolQuoteConfig(
        normalized_input = false,
        vol_price_inconsistency_handling = :warn
    )
    vq_ok = VolQuote(
        opt, und, r;
        mid_price=p_cons, mid_iv=0.4,
        reference_date=ref,
        config=config_ok
    )
    @test vq_ok isa VolQuote

    # force inconsistency by bumping price
    p_bad = p_cons * 1.15

    # warn path
    config_warn = VolQuoteConfig(
        normalized_input = false,
        vol_price_inconsistency_handling = :warn
    )
    @test_logs (:warn, r"Inconsistent") VolQuote(
        opt, und, r;
        mid_price=p_bad, mid_iv=0.4,
        reference_date=ref,
        config=config_warn
    )

    # throw path
    config_throw = VolQuoteConfig(
        normalized_input = false,
        vol_price_inconsistency_handling = :throw,
        abs_tol_p = 1e-12
    )
    @test_throws ArgumentError VolQuote(
        opt, und, r;
        mid_price=p_bad, mid_iv=0.4,
        reference_date=ref,
        config=config_throw
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
    @test @allocated(solve(prob, method).price) ≤ 512
end

# --- config reusability test -------------------------------------------------
@testset "Config reusability across multiple VolQuotes" begin
    ref = to_ticks(Date(2025,1,1))
    und = SpotObs(100.0)
    r = 0.02
    exp = Date(2025,7,1)
    
    # Create a strict configuration once
    strict_config = VolQuoteConfig(
        vol_price_inconsistency_handling = :throw,
        missing_mid_handling = :throw,
        price_monotonicity_handling = :throw,
        iv_monotonicity_handling = :throw,
        iv_guess = 0.3
    )
    
    # Reuse config for multiple quotes
    strikes = [90.0, 100.0, 110.0]
    vqs = map(strikes) do K
        opt = VanillaOption(K, exp, European(), Call(), Spot())
        VolQuote(opt, und, r; mid_iv=0.25, reference_date=ref, config=strict_config)
    end
    
    @test length(vqs) == 3
    @test all(vq -> vq isa VolQuote, vqs)
    @test all(vq -> vq.mid_iv ≈ 0.25, vqs)
end

# --- custom pricing model in config -----------------------------------------
@testset "Custom pricing model via config" begin
    ref = to_ticks(Date(2025,1,1))
    und = SpotObs(100.0)
    r = 0.02
    exp = Date(2025,7,1)
    opt = VanillaOption(100.0, exp, European(), Call(), Spot())
    
    # Use BlackScholesAnalytic (default)
    config_bs = VolQuoteConfig()
    vq_bs = VolQuote(opt, und, r; mid_iv=0.3, reference_date=ref, config=config_bs)
    
    @test vq_bs.iv_model isa BlackScholesAnalytic
    @test vq_bs.mid_iv ≈ 0.3
    
    # Verify we can construct with different models (even if we don't test convergence)
    # This just ensures the config system works with other pricing methods
    config_cm = VolQuoteConfig(
        CarrMadan(1.0, 32.0, LognormalDynamics())
    )
    
    # This should construct without error
    vq_cm = VolQuote(opt, und, r; mid_iv=0.3, reference_date=ref, config=config_cm)
    @test vq_cm.iv_model isa CarrMadan
end

# --- normalized input via config --------------------------------------------
@testset "Normalized input handling via config" begin
    refD, exp = Date(2025,1,1), Date(2025,7,1)
    ref = to_ticks(refD)
    und = SpotObs(100.0)
    r = 0.02
    opt = VanillaOption(100.0, exp, European(), Call(), Spot())
    
    # Get absolute price first
    config_abs = VolQuoteConfig(normalized_input=false)
    vq_abs = VolQuote(opt, und, r; mid_iv=0.3, reference_date=ref, config=config_abs)
    p_abs = vq_abs.mid_price
    
    # Calculate forward
    D = Hedgehog.df(FlatRateCurve(ref, r), exp)
    F = und.S / D
    p_normalized = p_abs / F
    
    # Now construct with normalized input
    config_norm = VolQuoteConfig(normalized_input=true)
    vq_norm = VolQuote(
        opt, und, r;
        mid_price=p_normalized,
        reference_date=ref,
        config=config_norm
    )
    
    # Should recover the same absolute price and IV
    @test isapprox(vq_norm.mid_price, p_abs; rtol=1e-10)
    @test isapprox(vq_norm.mid_iv, 0.3; rtol=1e-8)
end

# --- missing mid handling policies -------------------------------------------
@testset "Missing mid handling policies" begin
    ref = to_ticks(Date(2025,1,1))
    und = SpotObs(100.0)
    r = 0.02
    opt = VanillaOption(100.0, Date(2025,7,1), European(), Call(), Spot())
    
    # Default: throw on missing mid
    config_throw = VolQuoteConfig(missing_mid_handling=:throw)
    @test_throws ArgumentError VolQuote(
        opt, und, r;
        bid_iv=0.2, ask_iv=0.4,  # no mid!
        reference_date=ref,
        config=config_throw
    )
    
    # Warn on missing mid
    config_warn = VolQuoteConfig(missing_mid_handling=:warn)
    @test_logs (:warn, r"VolQuote requires") VolQuote(
        opt, und, r;
        bid_iv=0.2, ask_iv=0.4,  # no mid!
        reference_date=ref,
        config=config_warn
    )
end

# --- tolerance configuration -------------------------------------------------
@testset "Custom tolerance configuration" begin
    ref = to_ticks(Date(2025,1,1))
    und = SpotObs(100.0)
    r = 0.02
    exp = Date(2025,7,1)
    opt = VanillaOption(100.0, exp, European(), Call(), Spot())
    
    # Get a baseline price
    config_base = VolQuoteConfig()
    vq_base = VolQuote(opt, und, r; mid_iv=0.3, reference_date=ref, config=config_base)
    p_exact = vq_base.mid_price
    
    # Create slightly inconsistent price (within loose tolerance)
    p_slightly_off = p_exact * 1.0001  # 1 bp difference
    
    # Tight tolerance should throw
    config_tight = VolQuoteConfig(
        vol_price_inconsistency_handling = :throw,
        abs_tol_p = 1e-12,
        rel_tol_p = 1e-10
    )
    @test_throws ArgumentError VolQuote(
        opt, und, r;
        mid_price=p_slightly_off, mid_iv=0.3,
        reference_date=ref,
        config=config_tight
    )
    
    # Loose tolerance should accept
    config_loose = VolQuoteConfig(
        vol_price_inconsistency_handling = :throw,
        abs_tol_p = 1e-2,
        rel_tol_p = 1e-2
    )
    vq_loose = VolQuote(
        opt, und, r;
        mid_price=p_slightly_off, mid_iv=0.3,
        reference_date=ref,
        config=config_loose
    )
    @test vq_loose isa VolQuote
end

# --- ignore mode for inconsistencies -----------------------------------------
@testset "Ignore mode for inconsistencies" begin
    ref = to_ticks(Date(2025,1,1))
    und = SpotObs(100.0)
    r = 0.02
    exp = Date(2025,7,1)
    opt = VanillaOption(100.0, exp, European(), Call(), Spot())
    
    # Get a baseline price
    config_base = VolQuoteConfig()
    vq_base = VolQuote(opt, und, r; mid_iv=0.3, reference_date=ref, config=config_base)
    p_exact = vq_base.mid_price
    
    # Wildly inconsistent price
    p_bad = p_exact * 2.0
    
    # Ignore mode should silently accept
    config_ignore = VolQuoteConfig(
        vol_price_inconsistency_handling = :ignore
    )
    
    # No warning or error should be emitted
    @test_logs min_level=Logging.Info VolQuote(
        opt, und, r;
        mid_price=p_bad, mid_iv=0.3,
        reference_date=ref,
        config=config_ignore
    )
end

# --- full bid/mid/ask workflow -----------------------------------------------
@testset "Full bid/mid/ask workflow with config" begin
    ref = to_ticks(Date(2025,1,1))
    und = SpotObs(100.0)
    r = 0.02
    exp = Date(2025,7,1)
    opt = VanillaOption(100.0, exp, European(), Call(), Spot())
    
    config = VolQuoteConfig(
        iv_guess = 0.25,
        vol_price_inconsistency_handling = :warn,
        price_monotonicity_handling = :warn,
        iv_monotonicity_handling = :warn
    )
    
    vq = VolQuote(
        opt, und, r;
        bid_iv=0.20, mid_iv=0.25, ask_iv=0.30,
        reference_date=ref,
        config=config
    )
    
    # Check structure
    @test !isnan(vq.bid_price) && !isnan(vq.bid_iv)
    @test !isnan(vq.mid_price) && !isnan(vq.mid_iv)
    @test !isnan(vq.ask_price) && !isnan(vq.ask_iv)
    
    # Check monotonicity
    @test vq.bid_price <= vq.mid_price <= vq.ask_price
    @test vq.bid_iv <= vq.mid_iv <= vq.ask_iv
    
    # Check IV values match input
    @test vq.bid_iv ≈ 0.20
    @test vq.mid_iv ≈ 0.25
    @test vq.ask_iv ≈ 0.30
end