@testset "Price Agreement" begin
    @testset "Binomial tree vs Black-Scholes analytic" begin
        # Define European put option on spot
        strike = 1.1
        expiry = Date(2021, 1, 1)
        euro_payoff = VanillaOption(strike, expiry, European(), Put(), Spot())

        # Market inputs
        reference_date = Date(2020, 1, 1)
        rate = 0.2
        spot = 1.0
        sigma = 0.4
        market_inputs = BlackScholesInputs(reference_date, rate, spot, sigma)

        # Create pricing problem
        prob = PricingProblem(euro_payoff, market_inputs)

        # Solve using Black-Scholes analytic
        analytic_sol = Hedgehog.solve(prob, BlackScholesAnalytic())

        # Solve using binomial tree (CRR)
        crr_method = CoxRossRubinsteinMethod(100)
        crr_sol = Hedgehog.solve(prob, crr_method)

        @test isapprox(analytic_sol.price, crr_sol.price; atol = 1e-3)
    end

    @testset "COS method vs Black-Scholes analytical (Call)" begin
        reference_date = Date(2020, 1, 1)
        interest_rate = 0.2
        spot = 100.0
        sigma = 0.4
        market_inputs = BlackScholesInputs(reference_date, interest_rate, spot, sigma)

        expiry = reference_date + Day(365)
        strike = 100.0
        payoff = VanillaOption(strike, expiry, European(), Call(), Spot())
        prob = PricingProblem(payoff, market_inputs)

        cos_method = COSMethod(LognormalDynamics(); N=128, L=10)
        cos_solution = Hedgehog.solve(prob, cos_method)

        bs_solution = Hedgehog.solve(prob, BlackScholesAnalytic())

        @test isapprox(cos_solution.price, bs_solution.price; atol = 1e-6)
    end

    @testset "COS method vs Black-Scholes analytical (Put)" begin
        reference_date = Date(2020, 1, 1)
        interest_rate = 0.05
        spot = 100.0
        sigma = 0.3
        market_inputs = BlackScholesInputs(reference_date, interest_rate, spot, sigma)

        expiry = reference_date + Day(180)
        strike = 110.0
        payoff = VanillaOption(strike, expiry, European(), Put(), Spot())
        prob = PricingProblem(payoff, market_inputs)

        cos_method = COSMethod(LognormalDynamics(); N=128, L=10)
        cos_solution = Hedgehog.solve(prob, cos_method)

        bs_solution = Hedgehog.solve(prob, BlackScholesAnalytic())

        @test isapprox(cos_solution.price, bs_solution.price; atol = 1e-6)
    end

    @testset "COS method vs Carr-Madan (Heston)" begin
        reference_date = Date(2020, 1, 1)
        rate = 0.05
        spot = 100.0
        V0 = 0.04
        κ = 2.0
        θ = 0.04
        σ = 0.3
        ρ = -0.7
        market_inputs = HestonInputs(reference_date, rate, spot, V0, κ, θ, σ, ρ)

        expiry = reference_date + Day(365)
        strike = 100.0
        payoff = VanillaOption(strike, expiry, European(), Call(), Spot())
        prob = PricingProblem(payoff, market_inputs)

        cos_method = COSMethod(HestonDynamics(); N=256, L=12)
        cos_solution = Hedgehog.solve(prob, cos_method)

        carr_madan_method = CarrMadan(1.0, 32, HestonDynamics())
        carr_madan_solution = Hedgehog.solve(prob, carr_madan_method)

        @test isapprox(cos_solution.price, carr_madan_solution.price; atol = 1e-4)
    end

    @testset "Carr-Madan vs Black-Scholes analytical" begin
        # Define market inputs
        reference_date = Date(2020, 1, 1)
        interest_rate = 0.2
        spot = 100.0
        sigma = 0.4
        market_inputs = BlackScholesInputs(reference_date, interest_rate, spot, sigma)
    
        # Define payoff
        expiry = reference_date + Day(365)
        strike = 100.0
        payoff = VanillaOption(strike, expiry, European(), Call(), Spot())
    
        # Define pricing problem
        prob = PricingProblem(payoff, market_inputs)
    
        # Carr-Madan method
        boundary = 16
        α = 1.0
        carr_madan_method = CarrMadan(α, boundary, LognormalDynamics())
        carr_madan_solution = Hedgehog.solve(prob, carr_madan_method)
    
        # Analytical Black-Scholes method
        bs_solution = Hedgehog.solve(prob, BlackScholesAnalytic())
    
        @test isapprox(carr_madan_solution.price, bs_solution.price; atol = 1e-6)
    end
    
end