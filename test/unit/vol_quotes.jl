using Test
using Dates
using Hedgehog
using Logging

@testset "VolQuote Construction" begin
    
    @testset "Futures-based quote with all data (Deribit example)" begin
        println("\n=== Testing: Futures-based quote with all data (Deribit example) ===")
        # Parse Deribit data
        strike = 144000.0
        expiry = unix2datetime(1766707200000 / 1000) + Hour(8) # Convert ms to seconds
        option_type = Call()
        underlying_price = 109449.27
        mid_iv = 48.7 / 100  # Convert from percentage
        timestamp = unix2datetime(1761153152331 / 1000)
        
        vq = VolQuote(
            strike, expiry, option_type, underlying_price, mid_iv, timestamp;
            underlying_type = FutureUnderlying,
            bid_iv = 48.7 / 100,
            ask_iv = 48.7 / 100,
            mid_price = 0.00981108 * underlying_price,
            bid_price = 0.0095 * underlying_price,
            ask_price = 0.01 * underlying_price,
            last_price = NaN,
            open_interest = 148.0,
            volume = 101.3,
            source = :deribit
        )
        
        # Verify stored values
        @test vq.payoff.strike == strike
        @test vq.underlying_price == underlying_price
        @test vq.underlying_type == FutureUnderlying
        @test vq.mid_iv ≈ 0.487
        @test vq.mid_price ≈ 0.00981108 * underlying_price
        @test vq.bid_price ≈ 0.0095 * underlying_price
        @test vq.ask_price ≈ 0.01 * underlying_price
        @test isnan(vq.last_price)
        @test vq.open_interest == 148.0
        @test vq.volume == 101.3
        @test vq.source == :deribit
        println("✓ All fields stored correctly")
    end
    
    @testset "Futures-based quote - compute prices from IV" begin
        println("\n=== Testing: Futures-based quote - compute prices from IV ===")
        vq = VolQuote(
            50000.0, Date(2025, 12, 26), Call(), 
            109000.0, 0.50, DateTime(2025, 10, 22);
            underlying_type = FutureUnderlying,
            bid_iv = 0.48,
            ask_iv = 0.52
        )
        
        # Prices should be computed (not NaN)
        @test !isnan(vq.mid_price)
        @test !isnan(vq.bid_price)
        @test !isnan(vq.ask_price)
        
        # Bid < Mid < Ask (from IV ordering)
        @test vq.bid_price < vq.mid_price < vq.ask_price
        println("✓ Prices computed correctly from IVs")
        println("  Bid: $(vq.bid_price), Mid: $(vq.mid_price), Ask: $(vq.ask_price)")
    end
    
    @testset "Futures-based quote - compute prices with missing bid/ask IVs" begin
        println("\n=== Testing: Futures-based quote - missing bid/ask IVs ===")
        vq = VolQuote(
            50000.0, Date(2025, 12, 26), Call(), 
            109000.0, 0.50, DateTime(2025, 10, 22);
            underlying_type = FutureUnderlying
            # bid_iv and ask_iv default to NaN
        )
        
        # Mid price should be computed
        @test !isnan(vq.mid_price)
        
        # Bid/ask prices should be NaN (no IVs provided)
        @test isnan(vq.bid_price)
        @test isnan(vq.ask_price)
        
        # Bid/ask IVs should be NaN
        @test isnan(vq.bid_iv)
        @test isnan(vq.ask_iv)
        println("✓ Mid price computed, bid/ask correctly left as NaN")
    end
    
    @testset "Futures-based quote - validate price-IV coherence" begin
        println("\n=== Testing: Futures-based quote - validate price-IV coherence ===")
        # Parse Deribit data - this quote has prices that should match IVs
        strike = 120000.0
        expiry = unix2datetime(1766707200000 / 1000)
        option_type = Call()
        underlying_price = 109449.27
        mark_iv = 46.38 / 100  # Convert from percentage
        timestamp = unix2datetime(1761153152332 / 1000)
        
        println("Creating consistent quote (should produce NO warning):")
        # First test: Prices should be consistent (no warning)
        @test_logs min_level=Logging.Warn begin
            vq_consistent = VolQuote(
                strike, expiry, option_type, underlying_price, mark_iv, timestamp;
                underlying_type = FutureUnderlying,
                mid_price = 0.04213933 * underlying_price,
                bid_price = 0.0415 * underlying_price,
                ask_price = 0.042 * underlying_price,
                open_interest = 7093.4,
                volume = 62.3,
                source = :deribit,
                price_tolerance = 0.01
            )
            
            @test vq_consistent isa VolQuote
            @test vq_consistent.mid_price ≈ 0.04213933 * underlying_price
        end
        println("✓ Consistent quote created without warnings")
        
        # Second test: Create quote with inconsistent price - should trigger warning
        println("\nCreating inconsistent quote (SHOULD produce warning):")
        @test_logs (:warn, r"Mid price-IV inconsistency") begin
            vq_inconsistent = VolQuote(
                strike, expiry, option_type, underlying_price, mark_iv, timestamp;
                underlying_type = FutureUnderlying,
                mid_price = 999.99,  # Clearly wrong price
                price_tolerance = 0.01
            )
            
            # Quote should still be created
            @test vq_inconsistent isa VolQuote
            # Should use the provided price despite inconsistency
            @test vq_inconsistent.mid_price == 999.99
        end
        println("✓ Inconsistent quote created (with warning above)")
    end
    @testset "Spot-based quote with rate curve - compute prices" begin
        println("\n=== Testing: Spot-based quote with rate curve ===")
        spot = 5800.0
        rate_curve = FlatRateCurve(0.05; reference_date=Date(2025, 10, 22))
        
        vq = VolQuote(
            5800.0, Date(2025, 12, 20), Call(),
            spot, 0.20, DateTime(2025, 10, 22);
            underlying_type = SpotUnderlying,
            rate_curve = rate_curve,
            reference_date = Date(2025, 10, 22)
        )
        
        # Should compute prices using forward = spot * exp(r*T)
        @test !isnan(vq.mid_price)
        @test vq.mid_price > 0
        println("✓ Price computed from spot + rate curve")
        println("  Mid price: $(vq.mid_price)")
    end
    
    @testset "Spot-based quote without rate curve - cannot price" begin
        println("\n=== Testing: Spot-based quote without rate curve ===")
        vq = VolQuote(
            5800.0, Date(2025, 12, 20), Call(),
            5800.0, 0.20, DateTime(2025, 10, 22);
            underlying_type = SpotUnderlying
            # No rate_curve provided
        )
        
        # Prices should remain NaN since we can't compute forward
        @test isnan(vq.mid_price)
        @test isnan(vq.bid_price)
        @test isnan(vq.ask_price)
        
        # But IV should be stored
        @test vq.mid_iv == 0.20
        println("✓ Prices correctly left as NaN (cannot compute without rate curve)")
    end
    
    @testset "Spot-based quote with provided prices (no computation)" begin
        println("\n=== Testing: Spot-based quote with provided prices ===")
        vq = VolQuote(
            5800.0, Date(2025, 12, 20), Put(),
            5800.0, 0.18, DateTime(2025, 10, 22);
            underlying_type = SpotUnderlying,
            mid_price = 150.0,
            bid_price = 148.0,
            ask_price = 152.0
        )
        
        # Should use provided prices (no rate curve, so can't validate)
        @test vq.mid_price == 150.0
        @test vq.bid_price == 148.0
        @test vq.ask_price == 152.0
        println("✓ Provided prices used as-is (no validation without rate curve)")
    end
    
    @testset "Forward-based quote" begin
        println("\n=== Testing: Forward-based quote ===")
        forward_price = 102.5
        
        vq = VolQuote(
            100.0, Date(2025, 6, 20), Put(),
            forward_price, 0.25, DateTime(2025, 1, 15);
            underlying_type = ForwardUnderlying
        )
        
        # Should compute prices using forward directly
        @test !isnan(vq.mid_price)
        @test vq.underlying_price == forward_price
        @test vq.underlying_type == ForwardUnderlying
        println("✓ Price computed using forward directly")
        println("  Mid price: $(vq.mid_price)")
    end
    
    @testset "Minimal construction - only required fields" begin
        println("\n=== Testing: Minimal construction ===")
        vq = VolQuote(
            50000.0, Date(2025, 12, 26), Call(),
            109000.0, 0.50, DateTime(2025, 10, 22);
            underlying_type = FutureUnderlying
        )
        
        # Check defaults - bid/ask IVs now default to NaN
        @test isnan(vq.bid_iv)
        @test isnan(vq.ask_iv)
        @test isnan(vq.bid_price)  # No IV means no price computation
        @test isnan(vq.ask_price)
        @test !isnan(vq.mid_price)  # Mid should still be computed
        @test isnan(vq.last_price)
        @test isnan(vq.open_interest)
        @test isnan(vq.volume)
        @test vq.source == :unknown
        println("✓ Defaults applied correctly")
    end
    
    @testset "Type promotion" begin
        println("\n=== Testing: Type promotion ===")
        # Mix Int and Float types
        vq = VolQuote(
            50000, Date(2025, 12, 26), Call(),  # Int strike
            109000.0, 0.50, DateTime(2025, 10, 22);  # Float underlying
            underlying_type = FutureUnderlying,
            open_interest = 100,  # Int
            volume = 50.5  # Float
        )
        
        # All numeric fields should be promoted to same type
        @test typeof(vq.underlying_price) == typeof(vq.mid_iv)
        @test typeof(vq.underlying_price) == typeof(vq.open_interest)
        println("✓ Types promoted correctly to: $(typeof(vq.underlying_price))")
    end
    
    @testset "Put option construction" begin
        println("\n=== Testing: Put option construction ===")
        vq = VolQuote(
            50000.0, Date(2025, 12, 26), Put(),
            109000.0, 0.50, DateTime(2025, 10, 22);
            underlying_type = FutureUnderlying
        )
        
        @test vq.payoff.call_put isa Put
        @test !isnan(vq.mid_price)
        # Put should have positive value when strike > forward
        @test vq.mid_price > 0
        println("✓ Put option created and priced correctly")
        println("  Mid price: $(vq.mid_price)")
    end
    
end