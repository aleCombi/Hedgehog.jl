using Test
using Dates
using Hedgehog
using Accessors

@testset "Calibration" begin
    @testset "Black-Scholes Calibration" begin
        reference_date = Date(2020, 1, 1)
        r, S0, sigma = 0.05, 100.0, 0.25
        market_inputs = BlackScholesInputs(reference_date, r, S0, sigma)

        strikes = collect(60.0:5.0:140.0)
        expiry = reference_date + Day(365)
        payoffs = [VanillaOption(K, expiry, European(), Call(), Spot()) for K in strikes]

        quotes = [
           Hedgehog.solve(PricingProblem(p, market_inputs), BlackScholesAnalytic()).price for
            p in payoffs
        ]

        accessors = [VolLens(1,1)]
        initial_guess = [0.15]

        basket = BasketPricingProblem(payoffs, market_inputs)
        calib = CalibrationProblem(basket, BlackScholesAnalytic(), accessors, quotes, 0.5*ones(length(payoffs)))
        result = Hedgehog.solve(calib, OptimizerAlgo(), maxiters = 100, f_abstol = 1e-5)

        @test isapprox(result.u[1], sigma; atol = 1e-5)
    end

    using Test
    using Dates
    using Hedgehog  # assuming your package is named Hedgehog and properly imported
    using Accessors

    @testset "Heston Carr-Madan Calibration" begin
        reference_date = Date(2020, 1, 1)
        S0 = 100.0
        true_params = (v0 = 0.010201, κ = 6.21, θ = 0.019, σ = 0.61, ρ = -0.7)
        r = 0.0319

        market_inputs = HestonInputs(
            reference_date,
            r,
            S0,
            true_params.v0,
            true_params.κ,
            true_params.θ,
            true_params.σ,
            true_params.ρ,
        )

        strikes = collect(60.0:5.0:140.0)
        expiries = [
            reference_date + Day(90),
            reference_date + Day(180),
            reference_date + Day(365),
        ]

        payoffs = [
            VanillaOption(K, expiry, European(), Call(), Spot()) for K in strikes,
            expiry in expiries
        ] |> vec

        α, boundary = 1.0, 32.0
        method_heston = CarrMadan(α, boundary, HestonDynamics())

        quotes = [Hedgehog.solve(PricingProblem(p, market_inputs), method_heston).price for p in payoffs]

        initial_guess = [0.02, 3.0, 0.03, 0.4, -0.3]
        accessors = [
            @optic(_.market_inputs.V0),
            @optic(_.market_inputs.κ),
            @optic(_.market_inputs.θ),
            @optic(_.market_inputs.σ),
            @optic(_.market_inputs.ρ),
        ]

        basket_problem = BasketPricingProblem(payoffs, market_inputs)
        # 1. Define Bounds (Essential for Heston)
        lower = [1e-5, 1e-3, 1e-5, 1e-3, -0.99]
        upper = [1.0,  20.0, 1.0,  5.0,   0.99]

        calib_problem = CalibrationProblem(
            basket_problem,
            method_heston,
            accessors,
            quotes,
            initial_guess,
        )

        calib_algo = OptimizerAlgo()
        result = Hedgehog.solve(calib_problem, calib_algo, f_abstol = 1e-5, lb = lower,
            ub = upper,
            maxiters = 500,)

        # Extract calibrated parameters
        @test isapprox(result.u[1], true_params.v0, rtol=1e-1)
        @test isapprox(result.u[2],  true_params.κ,  rtol=1e-1)
        @test isapprox(result.u[3],  true_params.θ,  rtol=1e-1)
        @test isapprox(result.u[4],  true_params.σ,  rtol=1e-1)
        @test isapprox(result.u[5],  true_params.ρ,  rtol=1e-1)
    end
end