using Test
using Hedgehog
using Dates
using Random
using Statistics

@testset "LSM vs Binomial Tree Agreement for American Options" begin
    
    @testset "American Put Option Agreement" begin
        # Setup common parameters
        strike = 100.0
        reference_date = Date(2020, 1, 1)
        expiry = reference_date + Year(1)
        rate = 0.05
        spot = 100.0
        sigma = 0.2
        
        # Create American put option
        american_put = VanillaOption(strike, expiry, American(), Put(), Spot())
        market_inputs = BlackScholesInputs(reference_date, rate, spot, sigma)
        prob = PricingProblem(american_put, market_inputs)
        
        # Binomial tree method (high number of steps for accuracy)
        crr_steps = 1000
        crr_method = CoxRossRubinsteinMethod(crr_steps)
        crr_solution = solve(prob, crr_method)
        
        # LSM method with fixed seeds for reproducibility
        trajectories = 50_000
        steps = 100
        rng = Xoshiro(12345)
        seeds = rand(rng, UInt64, trajectories)
        
        dynamics = LognormalDynamics()
        strategy = BlackScholesExact()
        config = SimulationConfig(trajectories; steps=steps, seeds=seeds, variance_reduction=Antithetic())
        degree = 5
        lsm_method = LSM(dynamics, strategy, config, degree)
        
        lsm_solution = solve(prob, lsm_method)
        
        # Test agreement with reasonable tolerance
        # LSM has Monte Carlo error, so we allow larger tolerance
        relative_error = abs(lsm_solution.price - crr_solution.price) / crr_solution.price
        
        println("American Put Pricing Comparison:")
        println("  Binomial Tree ($(crr_steps) steps): $(crr_solution.price)")
        println("  LSM ($(trajectories) paths):       $(lsm_solution.price)")
        println("  Relative Error:                    $(relative_error * 100)%")
        
        @test isapprox(lsm_solution.price, crr_solution.price; rtol=0.02)
    end
    
    @testset "American Call Option Agreement (High Dividend Yield)" begin
        # For American calls to have early exercise value, we need high dividend yield
        # We simulate this by using a high rate scenario
        strike = 100.0
        reference_date = Date(2020, 1, 1)
        expiry = reference_date + Year(1)
        rate = 0.15  # High rate to make early exercise attractive
        spot = 120.0  # ITM call
        sigma = 0.3
        
        # Create American call option
        american_call = VanillaOption(strike, expiry, American(), Call(), Spot())
        market_inputs = BlackScholesInputs(reference_date, rate, spot, sigma)
        prob = PricingProblem(american_call, market_inputs)
        
        # Binomial tree method
        crr_steps = 800
        crr_method = CoxRossRubinsteinMethod(crr_steps)
        crr_solution = solve(prob, crr_method)
        
        # LSM method
        trajectories = 30_000
        steps = 100
        rng = Xoshiro(54321)
        seeds = rand(rng, UInt64, trajectories)
        
        dynamics = LognormalDynamics()
        strategy = BlackScholesExact()
        config = SimulationConfig(trajectories; steps=steps, seeds=seeds, variance_reduction=Antithetic())
        degree = 5
        lsm_method = LSM(dynamics, strategy, config, degree)
        
        lsm_solution = solve(prob, lsm_method)
        
        relative_error = abs(lsm_solution.price - crr_solution.price) / crr_solution.price
        
        println("\nAmerican Call Pricing Comparison (High Rate Scenario):")
        println("  Binomial Tree ($(crr_steps) steps): $(crr_solution.price)")
        println("  LSM ($(trajectories) paths):       $(lsm_solution.price)")
        println("  Relative Error:                    $(relative_error * 100)%")
        
        @test isapprox(lsm_solution.price, crr_solution.price; rtol=0.03)
    end
    
    @testset "Multiple Strike Agreement Test" begin
        # Test agreement across different moneyness levels
        reference_date = Date(2020, 1, 1)
        expiry = reference_date + Month(6)  # Shorter maturity
        rate = 0.05
        spot = 100.0
        sigma = 0.25
        
        strikes = [80.0, 90.0, 100.0, 110.0, 120.0]  # OTM to ITM puts
        
        println("\nMultiple Strike Agreement Test (American Puts, 6M maturity):")
        println("Strike | Binomial | LSM      | Rel Error")
        println("-------|----------|----------|----------")
        
        for strike in strikes
            # Create American put option
            american_put = VanillaOption(strike, expiry, American(), Put(), Spot())
            market_inputs = BlackScholesInputs(reference_date, rate, spot, sigma)
            prob = PricingProblem(american_put, market_inputs)
            
            # Binomial tree method
            crr_steps = 500
            crr_method = CoxRossRubinsteinMethod(crr_steps)
            crr_solution = solve(prob, crr_method)
            
            # LSM method (smaller number of paths for speed)
            trajectories = 20_000
            steps = 50
            rng = Xoshiro(Int(strike) * 1000)  # Different seed per strike
            seeds = rand(rng, UInt64, trajectories)
            
            dynamics = LognormalDynamics()
            strategy = BlackScholesExact()
            config = SimulationConfig(trajectories; steps=steps, seeds=seeds, variance_reduction=Antithetic())
            degree = 4
            lsm_method = LSM(dynamics, strategy, config, degree)
            
            lsm_solution = solve(prob, lsm_method)
            
            relative_error = abs(lsm_solution.price - crr_solution.price) / crr_solution.price
            
            @printf("%6.1f | %8.4f | %8.4f | %7.2f%%\n", 
                    strike, crr_solution.price, lsm_solution.price, relative_error * 100)
            
            # More lenient tolerance for OTM options (lower absolute prices)
            tolerance = strike < spot ? 0.05 : 0.03
            @test isapprox(lsm_solution.price, crr_solution.price; rtol=tolerance)
        end
    end
    
    @testset "Early Exercise Premium Consistency" begin
        # Compare early exercise premium: American - European
        strike = 110.0
        reference_date = Date(2020, 1, 1)
        expiry = reference_date + Year(1)
        rate = 0.03
        spot = 100.0
        sigma = 0.3
        
        # American put
        american_put = VanillaOption(strike, expiry, American(), Put(), Spot())
        market_inputs = BlackScholesInputs(reference_date, rate, spot, sigma)
        american_prob = PricingProblem(american_put, market_inputs)
        
        # European put
        european_put = VanillaOption(strike, expiry, European(), Put(), Spot())
        european_prob = PricingProblem(european_put, market_inputs)
        
        # Prices using both methods
        crr_method = CoxRossRubinsteinMethod(800)
        bs_method = BlackScholesAnalytic()
        
        american_crr = solve(american_prob, crr_method)
        european_bs = solve(european_prob, bs_method)
        early_exercise_premium_crr = american_crr.price - european_bs.price
        
        # LSM for American
        trajectories = 40_000
        steps = 100
        rng = Xoshiro(98765)
        seeds = rand(rng, UInt64, trajectories)
        
        dynamics = LognormalDynamics()
        strategy = BlackScholesExact()
        config = SimulationConfig(trajectories; steps=steps, seeds=seeds, variance_reduction=Antithetic())
        degree = 5
        lsm_method = LSM(dynamics, strategy, config, degree)
        
        american_lsm = solve(american_prob, lsm_method)
        early_exercise_premium_lsm = american_lsm.price - european_bs.price
        
        println("\nEarly Exercise Premium Consistency:")
        println("  European Put (BS):           $(european_bs.price)")
        println("  American Put (Binomial):     $(american_crr.price)")
        println("  American Put (LSM):          $(american_lsm.price)")
        println("  Early Ex Premium (Binomial): $(early_exercise_premium_crr)")
        println("  Early Ex Premium (LSM):      $(early_exercise_premium_lsm)")
        
        # Both methods should agree that American >= European
        @test american_crr.price >= european_bs.price
        @test american_lsm.price >= european_bs.price
        
        # Early exercise premiums should be similar
        @test isapprox(early_exercise_premium_lsm, early_exercise_premium_crr; rtol=0.04)
    end
end