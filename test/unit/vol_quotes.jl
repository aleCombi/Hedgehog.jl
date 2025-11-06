
function volquote_from_dict(
    q::Dict;
    r::Real = 0.0,
    iv_model = BlackScholesAnalytic(),
    normalized_prices::Bool = true,
    iv_in_percent::Union{Bool,Nothing} = nothing,
    warn_inconsistency::Bool = true,
    throw_inconsistency::Bool = false,
    warn_monotonicity::Bool = true,
    throw_monotonicity::Bool = false,
)
    fnum(x) = (x === nothing || x === missing) ? NaN : Float64(x)

    # Required-ish fields (tests provide them)
    K      = fnum(get(q, "strike", nothing))
    expiry = Int64(get(q, "expiry", 0))
    tside  = String(get(q, "option_type", "C")) == "C" ? Call() : Put()
    S      = fnum(get(q, "underlying_price", nothing))

    # Reference date
    ref = haskey(q, "ts")   ? Int64(q["ts"]) :
          haskey(q, "date") ? to_ticks(Date(String(q["date"]))) :
                               Int64(0)

    # Prices (Deribit feeds are often forward-normalized; default true)
    bid_p = fnum(get(q, "bid_price",  nothing))
    mid_p = fnum(get(q, "mark_price", nothing))
    ask_p = fnum(get(q, "ask_price",  nothing))

    # IV (auto-detect percent if not specified)
    raw_iv = fnum(get(q, "mark_iv", nothing))
    mid_iv = if isnan(raw_iv)
        NaN
    else
        is_pct = iv_in_percent === nothing ? (raw_iv > 1.0) : iv_in_percent
        is_pct ? raw_iv / 100 : raw_iv
    end

    payoff = VanillaOption(K, expiry, European(), tside, Spot())
    und    = SpotObs(S)

    return VolQuote(
        payoff,
        und,
        Float64(r);
        mid_price = mid_p,
        mid_iv    = mid_iv,
        bid_price = bid_p,
        ask_price = ask_p,
        reference_date = ref,
        source = :deribit,
        iv_model = iv_model,
        normalized_input = normalized_prices,
        warn_inconsistency = warn_inconsistency,
        throw_inconsistency = throw_inconsistency,
        warn_monotonicity = warn_monotonicity,
        throw_monotonicity = throw_monotonicity,
    )
end


@testset "price<->iv roundtrip" begin
    ref, exp = Date(2025,1,1), Date(2025,7,1)
    rc = FlatRateCurve(0.02; reference_date=ref)
    for (S, K, σ) in ((100.0, 80.0, 0.2), (100.0, 100.0, 0.5), (100.0, 130.0, 1.0))
        mi  = BlackScholesInputs(ref, rc, S, σ)
        opt = VanillaOption(K, exp, European(), Call(), Spot())
        p   = iv_to_price(opt, S, 0.02, σ, ref, BlackScholesAnalytic())
        σ2  = price_to_iv(opt, S, 0.02, p, ref, BlackScholesAnalytic(); iv_guess=σ)
        @test isapprox(σ2, σ; rtol=1e-8, atol=1e-10)
    end
end

@testset "normalization is price/F" begin
    ref, exp = Date(2025,1,1), Date(2025,7,1)
    und = SpotObs(100.0); r = 0.02
    opt = VanillaOption(100.0, exp, European(), Call(), Spot())
    vq = VolQuote(opt, und, r; mid_iv=0.4, reference_date=to_ticks(ref))
    p_abs = iv_to_price(vq, 0.4; normalize=false)
    F = Hedgehog.underlying_forward(und, r, ref, exp)
    @test isapprox(iv_to_price(vq, 0.4; normalize=true), p_abs/F; rtol=1e-12)
end

@testset "monotonicity warnings" begin
    ref = to_ticks(Date(2025,1,1))
    und = SpotObs(100.0); r = 0.02
    opt = VanillaOption(100.0, Date(2025,7,1), European(), Call(), Spot())
    @test_logs (:warn,) (:warn,) VolQuote(
        opt, und, r;
        bid_iv=0.25, mid_iv=0.24, ask_iv=0.23,  # intentionally decreasing
        reference_date=ref,
        warn_monotonicity=true, throw_monotonicity=false
    )
end

@testset "NaN storage policy" begin
    ref = to_ticks(Date(2025,1,1))
    und = SpotObs(100.0); r = 0.02
    opt = VanillaOption(100.0, Date(2025,7,1), European(), Call(), Spot())
    vq = VolQuote(opt, und, r; mid_iv=0.3, reference_date=ref)
    @test isnan(vq.bid_price) && isnan(vq.bid_iv)
    @test isnan(vq.ask_price) && isnan(vq.ask_iv)
end

@testset "BS solve alloc-free" begin
    ref, exp = Date(2025,1,1), Date(2025,7,1)
    rc = FlatRateCurve(0.02; reference_date=ref)
    mi = BlackScholesInputs(ref, rc, 100.0, 0.4)
    opt = VanillaOption(90.0, exp, European(), Call(), Spot())
    prob = PricingProblem(opt, mi)
    method = BlackScholesAnalytic()
    @test @allocated(solve(prob, method).price) == 0
end

"""
    test_deribit_quote_policy(q::Dict; expect_warn=false, expect_throw=false)

Asserts the VolQuote constructor's policy reactions (warnings or throws) when building from `q`.
Does not re-check any invariants; it just ensures the constructor behaves as configured.
"""
function test_deribit_quote_policy(q::Dict; expect_warn::Bool=false, expect_throw::Bool=false)
    if expect_throw
        @test_throws ArgumentError volquote_from_dict(q)
    elseif expect_warn
        @test_logs (:warn,) volquote_from_dict(q)
    else
        vq = volquote_from_dict(q)
        @test vq isa VolQuote
        return vq
    end
end

"""
    test_volquote_inconsistency_warn(q::Dict; bump=:price, factor=1.10)

Mutates a copy of `q` to make mid price/IV inconsistent, then asserts that
building via `volquote_from_dict` emits a warning (the default policy).

`bump` can be `:price` (scale mark_price) or `:iv` (scale mark_iv).
`factor` should be > 1.0 to force a mismatch beyond tolerances.
"""
function test_volquote_inconsistency_warn(q::Dict; bump::Symbol=:price, factor::Float64=1.10)
    bad = copy(q)

    if bump === :price
        @assert haskey(bad, "mark_price") && !isnothing(bad["mark_price"]) "need mark_price in dict"
        bad["mark_price"] = bad["mark_price"] * factor
    elseif bump === :iv
        @assert haskey(bad, "mark_iv") && !isnothing(bad["mark_iv"]) "need mark_iv in dict"
        # if IVs are in %, this still breaks; if in decimals, factor>1 breaks too
        bad["mark_iv"] = bad["mark_iv"] * factor
    else
        error("bump must be :price or :iv")
    end

    # Expect two warnings: inconsistency + (price or IV) monotonicity
    @test_logs (:warn,) (:warn,) volquote_from_dict(bad)

    return nothing
end

"""
    test_volquote_inconsistency_throw(q::Dict; bump=:price, factor=1.10)

Builds a *baseline* VolQuote from `q`, then reconstructs a VolQuote using the
same components but with inconsistent mid price/IV and `throw_inconsistency=true`,
asserting the constructor raises `ArgumentError`.

This avoids re-implementing the Deribit mapping: we reuse fields from the baseline VQ.
"""
function test_volquote_inconsistency_throw(q::Dict; bump::Symbol=:price, factor::Float64=1.10)
    # 1) Build a clean baseline via your mapper
    vq0 = volquote_from_dict(q)

    # 2) Create mismatched mid fields
    mid_price = vq0.mid_price
    mid_iv    = vq0.mid_iv
    @assert !isnan(mid_price) && !isnan(mid_iv) "baseline quote needs mid price & IV"

    bad_price, bad_iv =
        bump === :price ? (mid_price * factor, mid_iv) :
        bump === :iv    ? (mid_price,          mid_iv * factor) :
        error("bump must be :price or :iv")

    # 3) Rebuild directly with the same components but force throw_inconsistency=true
    @test_throws ArgumentError VolQuote(
        vq0.payoff,
        vq0.underlying,
        vq0.interest_rate;
        mid_price = bad_price,
        mid_iv    = bad_iv,
        reference_date = vq0.reference_date,
        source          = vq0.source,
        iv_model        = vq0.iv_model,
        warn_inconsistency  = false,
        throw_inconsistency = true,
        # tighten tolerances to make failures deterministic if needed:
        abs_tol_p = typeof(bad_price)(1e-12), 
    )

    return nothing
end

@testset "VolQuote policy reactions on inconsistent mid" begin
    # minimal dict in the Deribit format (you’ll paste your real ones)
    q = Dict(
        "instrument_name" => "BTC-28NOV25-105000-C",
        "underlying"      => "BTC",
        "expiry"          => 1764288000000,
        "strike"          => 105000.0,
        "option_type"     => "C",
        "bid_price"       => 0.0815,
        "ask_price"       => 0.0830,
        "mark_price"      => 0.08222802,
        "mark_iv"         => 46.99,            # whatever your mapper expects (% or decimal)
        "underlying_price"=> 109_297.95,
        "ts"              => 1760886918803,
        "date"            => "2025-10-19",
    )

    # expect a warning when the mapper + constructor see an inconsistency
    test_volquote_inconsistency_warn(q; bump=:price, factor=1.15)
    test_volquote_inconsistency_warn(q; bump=:iv,    factor=1.15)

    # expect a throw when we force throw_inconsistency=true
    test_volquote_inconsistency_throw(q; bump=:price, factor=1.15)
    test_volquote_inconsistency_throw(q; bump=:iv,    factor=1.15)
end
