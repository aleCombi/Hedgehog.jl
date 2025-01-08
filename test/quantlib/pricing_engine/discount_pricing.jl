# act365, cmp rate, modified preceding, 3 months, 2 days pay delay
@testitem "Quantlib:  act365, cmp rate, modified preceding, 3 months, 2 days pay delay" setup=[QuantlibSetup] begin
## Getting Hedgehog Results
# schedule configuration
start_date = Date(2019, 6, 27)
end_date = Date(2029, 6, 27)
schedule_config = ScheduleConfig(Month(3); business_days_convention=ModifiedPreceding(), calendar=BusinessDays.TARGET())
instrument_schedule = InstrumentSchedule(start_date, end_date, schedule_config)

# rate configuration
rate = 0.0047
rate_config = FixedRateConfig(ACT360(), LinearRate())
instrument_rate = FixedRate(rate, rate_config)

# fixed rate stream configuration
principal = 1.0
stream_config = FixedStreamConfig(principal, instrument_rate, instrument_schedule)

# fixed rate stream calculations
fixed_rate_stream = FixedRateStream(stream_config)

## Getting Quanatlib Results

ql_start_date = to_ql_date(start_date)
ql_end_date = to_ql_date(end_date)

# Define schedule with NullCalendar (treat all days as business)
schedule = ql.Schedule(ql_start_date, ql_end_date, ql.Period(ql.Quarterly),
                        ql.TARGET(), ql.ModifiedPreceding, ql.ModifiedPreceding,
                       ql.DateGeneration.Forward, false)

ql_fixed_rate_leg = ql.FixedRateLeg(schedule, ql.Actual360(), [principal], [rate])
ql_fixed_flows = [cash_flow.amount() for cash_flow in ql_fixed_rate_leg]

# Define the discount rate for the flat curve
flat_rate = 0.02  # Example: 2% flat rate

# Set the reference date (valuation date) for the curve, matching the start of the instrument
valuation_date = ql_start_date  # Could be any date, but often the start date is used
ql.Settings.instance().evaluationDate = valuation_date

# Create a flat forward curve
day_count = ql.Actual360()  # Use the same day count convention as the instrument
calendar = ql.NullCalendar()  # NullCalendar for simplicity, no holidays considered
flat_forward_curve = ql.FlatForward(valuation_date, ql.QuoteHandle(ql.SimpleQuote(flat_rate)), day_count)

# Turn the curve into a YieldTermStructureHandle for pricing
discount_curve_handle = ql.YieldTermStructureHandle(flat_forward_curve)

# Define the fixed rate leg based on the previously defined schedule and principal
fixed_rate_leg = ql.FixedRateLeg(schedule, day_count, [principal], [rate])

# Discount each cash flow and calculate the present value
present_value = sum([
    cash_flow.amount() * discount_curve_handle.discount(cash_flow.date())
    for cash_flow in fixed_rate_leg
])

print("Present Value of Fixed Rate Stream:", present_value)

rate_curve = FlatRateCurve("Curve", start_date, 0.02, ACT360(), Exponential())
price_hh = price_flow_stream(fixed_rate_stream, RateMarketData(rate_curve))

@test isapprox(present_value, price_hh; atol=1e-15)
end

@testitem "Quantlib: 6 Month, Linear, ACT360, ModifiedFollowing, Target calendar (for accrual), WeekendsOnly calendar (for fixing), 10 business days fixing shifter from start" setup=[QuantlibSetup] begin
    ## Getting Hedgehog Results
    # schedule configuration
    start_date = Date(2019, 6, 27)
    end_date = Date(2019, 7, 27)
    business_day_convention=FollowingBusinessDay()
    period = Month(1)
    calendar=BusinessDays.TARGET()
    schedule_config = ScheduleConfig(period; 
        business_days_convention=business_day_convention, 
        termination_bd_convention=business_day_convention, calendar=calendar)

    instrument_schedule = InstrumentSchedule(start_date, end_date, schedule_config)

    # rate configuration
    day_count = ACT360()
    rate_type = LinearRate()
    fixing_days_delay = 0
    rate_config = SimpleRateConfig(day_count, rate_type, NoShift(false), AdditiveMargin())
    rate_index = RateIndex("RateIndex", Hedgehog.ForwardLooking(), Month(1), calendar, business_day_convention, rate_type, day_count)
    instrument_rate = SimpleInstrumentRate(rate_index, rate_config)

    # fixed rate stream configuration
    principal = 1.0
    stream_config = FloatStreamConfig(principal, instrument_rate, instrument_schedule)

    # float rate stream calculations
    float_rate_stream = SimpleFloatRateStream(stream_config)

    ## Getting Quanatlib Results
    ql_start_date = to_ql_date(start_date)
    ql_end_date = to_ql_date(end_date)

    # Define schedule
    schedule = get_quantlib_schedule(start_date, end_date, period, calendar, NoRollConvention(), business_day_convention, business_day_convention, schedule_config.stub_period.position)
    
    ql.Settings.instance().evaluationDate = to_ql_date(Date(2017,1,1))
    yts = ql.YieldTermStructureHandle(ql.FlatForward(0, ql.NullCalendar(), 0.05, to_ql_day_count(day_count)))
    engine = ql.DiscountingSwapEngine(yts)

    index = ql.IborIndex("MyIndex", ql.Period(1, ql.Months), fixing_days_delay, ql.USDCurrency(), ql.NullCalendar(), ql.Unadjusted, false, to_ql_day_count(day_count))
    index = index.clone(yts)

    floating_rate_leg = ql.IborLeg([principal], schedule, index)
    swap = ql.Swap(ql.Leg(), floating_rate_leg)  # Only a fixed-rate leg, no floating leg

    coupons = [float_rate_stream.schedules[i] for i in 1:length(float_rate_stream.schedules)]
    # ql coupon
    ql_coupon = ql.as_floating_rate_coupon(floating_rate_leg[1])
    ql_coupons = [ql.as_floating_rate_coupon(el) for el in floating_rate_leg]

    # Attach the discounting engine to the bond
    swap.setPricingEngine(engine)

    # Calculate NPV
    npv = swap.NPV()
    # Calculate NPV
    println(npv)

    rate_curve = FlatRateCurve("Curve", Date(2017,1,1), 0.05, ACT360(), Exponential())
    price_hh = price_flow_stream(float_rate_stream, RateMarketData(rate_curve))
    println("discount factor ql:", yts.discount(to_ql_date(end_date)))

    println(price_hh)
    @test price_hh == npv
    # compare schedules per coupon
    for (i, (ql_coupon, coupon)) in enumerate(zip(ql_coupons, coupons))
        println("Quantlib accrual start date: ", to_julia_date(ql_coupon.accrualStartDate()))
        println("DP accrual start date: ", coupon.accrual_start)
        @assert coupon.accrual_start == to_julia_date(ql_coupon.accrualStartDate())
        @assert coupon.accrual_end == to_julia_date(ql_coupon.accrualEndDate())
        println("Quantlib fixing date: ", to_julia_date(ql_coupon.fixingDate()))
        @assert coupon.fixing_date == to_julia_date(ql_coupon.fixingDate())
    end
end