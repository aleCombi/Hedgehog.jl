@testsnippet RateCurveSetup begin
    using Dates
    # Create mock dates and day count convention
    pricing_date = Date(2022, 1, 1)
    dates = [Date(2023, 1, 1), Date(2023, 7, 1), Date(2024, 1, 1)]
    discount_factors = [0.95, 0.90, 0.85]
    time_fractions = day_count_fraction(pricing_date, dates, ACT360())
    rates = implied_rate(1 ./ discount_factors, time_fractions, LinearRate())

    rate_curve = InterpolatedRateCurve(pricing_date; input_values=rates, input_type=Hedgehog.Rate(), spine_dates=dates)
end

# Test for price_fixed_flows_stream
@testitem "price_fixed_flows_stream" setup=[RateCurveSetup] begin
    # Create a mock FixedRateStream
    payment_dates = [Date(2023, 1, 1), Date(2023, 7, 1), Date(2024, 1, 1)]
    cash_flows = [1000.0, 1000.0, 1000.0]
    
    # Calculate the price
    price = price_flow_stream(payment_dates, cash_flows, RateMarketData(rate_curve))

    # Expected price
    expected_price = sum(cash_flows .* [0.95, 0.90, 0.85])

    @test price == expected_price
end

@testitem "float_rate_pricing" setup=[RateCurveSetup] begin
    include("../dummy_struct_functions.jl")
    # Create a mock FloatRateStream
    principal = 1000.0
    start_date = Date(2023, 1, 1)
    end_date = Date(2024, 1, 1)
    day_count = ACT365()
    rate_type = LinearRate()
    rate_index = RateIndex("RateIndex", Hedgehog.ForwardLooking(), Month(6), NoHolidays(), NoneBusinessDayConvention(), rate_type, day_count)
    rate_convention = DummyRateType()
    schedule_config = DummyScheduleConfig()
    instrument_schedule = InstrumentSchedule(start_date, end_date, schedule_config)
    rate_config = SimpleRateConfig(day_count, rate_type, NoShift(false), AdditiveMargin(0))
    instrument_rate = SimpleInstrumentRate(rate_index, rate_config)
    stream_config = FloatStreamConfig(principal, instrument_rate, instrument_schedule)
    stream = SimpleFloatRateStream(stream_config)
    # print(stream.schedules.pay_dates)
    # Calculate the price
    price = price_flow_stream(stream, RateMarketData(rate_curve))

    # Expected price
    expected_price = 1000.0 * (0.9 * (0.95 / 0.90 - 1) + 0.85 * (0.90 / 0.85 - 1))

    @test price ≈ expected_price atol=1e-8
end