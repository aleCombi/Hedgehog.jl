# This tests the forward rates calculation when the rate fixes in advance (forward looking) before the accrual start and the accrual period is shorter than the benchmark rate accrual period (e.g. you read a benchmark rate referred to a period longer or shorter than the one you apply it to), with some margin.
@testitem "Forward rates on a flat exponential curve" begin
    using Dates
    accrual_dates = [Date(2013,3,1), Date(2013,6,1), Date(2013,9,1), Date(2013,12,1)]
    rates = [0.02, 0.02, 0.02, 0.02]
    pricing_date = Date(2013,2,1)
    rate_curve = InterpolatedRateCurve(pricing_date; input_values=rates, rate_type=Exponential(),spine_dates=accrual_dates, input_type=Hedgehog.Rate())
    forward_rates = forward_rate(rate_curve, Date(2013,6,1), Date(2013,9,1))
    @test forward_rates ≈ 0.02
end

@testitem "Forward rates on a linear curve" begin
    using Dates
    accrual_dates = [Date(2013,3,1), Date(2013,6,1), Date(2013,9,1)]
    rates = [0.02, 0.03, 0.04]
    pricing_date = Date(2013,2,1)
    rate_curve = InterpolatedRateCurve(pricing_date; input_values=rates, input_type=Hedgehog.Rate(), spine_dates=accrual_dates, rate_type=LinearRate())
    forward_rates = forward_rate(rate_curve, Date(2013,6,1), Date(2013,9,1))
    day_count_0 = day_count_fraction(pricing_date, Date(2013,6,1), rate_curve.day_count_convention)
    day_count_1 = day_count_fraction(Date(2013,6,1), Date(2013,9,1), rate_curve.day_count_convention)
    day_count_2 = day_count_fraction(pricing_date, Date(2013,9,1), rate_curve.day_count_convention)
    @test 1 + day_count_2 * 0.04 ≈ (1 + day_count_1 * forward_rates) * (1 + day_count_0 * 0.03)
end

@testitem "Forward rates on a linear curve with additive margin" begin
    using Dates
    accrual_dates = [Date(2013,3,1), Date(2013,6,1), Date(2013,9,1)]
    rates = [0.02, 0.03, 0.04]
    pricing_date = Date(2013,2,1)
    margin=0.001
    rate_curve = InterpolatedRateCurve(pricing_date; input_values=rates, input_type=Hedgehog.Rate(), spine_dates=accrual_dates, rate_type=LinearRate())
    forward_rates = forward_rate(rate_curve, Date(2013,6,1), Date(2013,9,1); margin_config=AdditiveMargin(margin))
    day_count_0 = day_count_fraction(pricing_date, Date(2013,6,1), rate_curve.day_count_convention)
    day_count_1 = day_count_fraction(Date(2013,6,1), Date(2013,9,1), rate_curve.day_count_convention)
    day_count_2 = day_count_fraction(pricing_date, Date(2013,9,1), rate_curve.day_count_convention)
    @test 1 + day_count_2 * 0.04 ≈ (1 + day_count_1 * (forward_rates - margin)) * (1 + day_count_0 * 0.03)
end

@testitem "Forward rates on a linear curve with multiplicative margin" begin
    using Dates
    accrual_dates = [Date(2013,3,1), Date(2013,6,1), Date(2013,9,1)]
    rates = [0.02, 0.03, 0.04]
    pricing_date = Date(2013,2,1)
    margin=0.001
    rate_curve = InterpolatedRateCurve(pricing_date; input_values=rates, input_type=Hedgehog.Rate(),spine_dates=accrual_dates, rate_type=LinearRate())
    forward_rates = forward_rate(rate_curve, Date(2013,6,1), Date(2013,9,1); margin_config=MultiplicativeMargin(margin))
    day_count_0 = day_count_fraction(pricing_date, Date(2013,6,1), rate_curve.day_count_convention)
    day_count_1 = day_count_fraction(Date(2013,6,1), Date(2013,9,1), rate_curve.day_count_convention)
    day_count_2 = day_count_fraction(pricing_date, Date(2013,9,1), rate_curve.day_count_convention)
    @test 1 + day_count_2 * 0.04 ≈ (1 + day_count_1 * (forward_rates - forward_rates * margin)) * (1 + day_count_0 * 0.03)
end

@testitem "Forward rates on a linear curve with multiplicative margin with prefilled day_count" begin
    using Dates
    accrual_dates = [Date(2013,3,1), Date(2013,6,1), Date(2013,9,1)]
    rates = [0.02, 0.03, 0.04]
    pricing_date = Date(2013,2,1)
    margin=0.001
    rate_curve = InterpolatedRateCurve(pricing_date; input_values=rates, input_type=Hedgehog.Rate(),spine_dates=accrual_dates, rate_type=LinearRate())
    day_count_1 = day_count_fraction(Date(2013,6,1), Date(2013,9,1), rate_curve.day_count_convention)
    forward_rates = forward_rate(rate_curve, Date(2013,6,1), Date(2013,9,1), day_count_1; margin_config=MultiplicativeMargin(margin))
    day_count_0 = day_count_fraction(pricing_date, Date(2013,6,1), rate_curve.day_count_convention)
    day_count_1 = day_count_fraction(Date(2013,6,1), Date(2013,9,1), rate_curve.day_count_convention)
    day_count_2 = day_count_fraction(pricing_date, Date(2013,9,1), rate_curve.day_count_convention)
    @test 1 + day_count_2 * 0.04 ≈ (1 + day_count_1 * (forward_rates - forward_rates * margin)) * (1 + day_count_0 * 0.03)
end

@testitem "Forward rates on a linear curve with multiplicative margin with SimpleRateStreamSchedules" begin
    using Dates
    accrual_dates = [Date(2013,3,1), Date(2013,6,1), Date(2013,9,1)]
    rates = [0.02, 0.03, 0.04]
    pricing_date = Date(2013,2,1)
    margin=0.001
    rate_curve = InterpolatedRateCurve(pricing_date; input_values=rates, input_type=Hedgehog.Rate(), spine_dates=accrual_dates, rate_type=LinearRate())
    day_count_1 = day_count_fraction(Date(2013,6,1), Date(2013,9,1), rate_curve.day_count_convention)
    market_data = RateMarketData(rate_curve)

    accrual_dates = [Date(2013,6,1), Date(2013,9,1)]
    fixing_dates = [accrual_dates[1]]
    discount_start_dates = fixing_dates
    discount_end_dates = accrual_dates[2:end]
    accrual_day_counts = [day_count_1]
    schedules = SimpleRateSchedule(fixing_dates, discount_start_dates, discount_end_dates, accrual_dates, accrual_day_counts)
    forward_rates = forward_rate(schedules, market_data, rate_curve.rate_type, MultiplicativeMargin(margin))[1]
    day_count_0 = day_count_fraction(pricing_date, Date(2013,6,1), rate_curve.day_count_convention)
    day_count_1 = day_count_fraction(Date(2013,6,1), Date(2013,9,1), rate_curve.day_count_convention)
    day_count_2 = day_count_fraction(pricing_date, Date(2013,9,1), rate_curve.day_count_convention)
    @test 1 + day_count_2 * 0.04 ≈ (1 + day_count_1 * (forward_rates - forward_rates * margin)) * (1 + day_count_0 * 0.03)
end

# Test for forward_rates
@testitem "forward_rates" setup=[RateCurveSetup] begin
    rate_config = SimpleRateConfig(ACT360(), LinearRate(), NoShift(), AdditiveMargin(0))
    day_counts = day_count_fraction(dates, rate_config.day_count_convention)
    schedules = SimpleRateSchedule(dates[1:end-1], dates[1:end-1], dates[2:end], dates, day_counts)
    # Calculate forward rates
    fwd_rates = forward_rate(schedules, RateMarketData(rate_curve), rate_config)

    # Expected forward rates
    expected_fwd_rates = [(0.95 / 0.90 - 1) / 181 * 360, (0.90 / 0.85 - 1) / 184 * 360]

    @test fwd_rates ≈ expected_fwd_rates rtol=1e-7
end

@testitem "compounded forward rates with 0 margin on compounded rate" begin
    using Dates
    rate_curve = FlatRateCurve("FlatCurve", Date(2000,1,1), 0.05, ACT365(), LinearRate())
    fixings = RateFixingTuples(Base.ImmutableDict(Date(2000,1,1) => 0.05))
    rate_market_data = RateMarketData(RateIndex("dummyRate"), rate_curve, fixings)
    pay_dates = [Date(2001,1,1)]
    accrual_dates = [Date(2000,1,1), Date(2000,2,1), Date(2000,3,1)]
    fixing_dates = accrual_dates[1:end-1]
    discount_start_dates = fixing_dates
    discount_end_dates = accrual_dates[2:end]
    compounding_schedules = [SimpleRateSchedule(fixing_dates, discount_start_dates, discount_end_dates, accrual_dates, ACT365())]
    schedules = CompoundedRateSchedules(pay_dates, compounding_schedules)
    compound_schedule = ScheduleConfig(Month(1); stub_period=StubPeriod(UpfrontStubPosition(), ShortStubLength()))
    rate_config = CompoundRateConfig(ACT365(), LinearRate(), TimeShift(Day(0)), compound_schedule, MarginOnCompoundedRate(AdditiveMargin(0)), CompoundedRate())
    @test forward_rate(schedules, rate_market_data, rate_config)[1] ≈ 0.05
end

@testitem "compounded forward rates with non-0 margin on compounded rate" begin
    using Dates
    rate_curve = FlatRateCurve("FlatCurve", Date(2000,1,1), 0.05, ACT365(), Exponential())
    fixings = RateFixingTuples(Base.ImmutableDict(Date(2000,1,1) => 0.05))
    rate_market_data = RateMarketData(RateIndex("dummyRate"), rate_curve, fixings)
    pay_dates = [Date(2001,1,1)]
    accrual_dates = [Date(2000,1,1), Date(2000,2,1), Date(2000,3,1)]
    fixing_dates = accrual_dates[1:end-1]
    discount_start_dates = fixing_dates
    discount_end_dates = accrual_dates[2:end]
    compounding_schedules = [SimpleRateSchedule(fixing_dates, discount_start_dates, discount_end_dates, accrual_dates, ACT365())]
    schedules = CompoundedRateSchedules(pay_dates, compounding_schedules)
    compound_schedule = ScheduleConfig(Month(1); stub_period=StubPeriod(UpfrontStubPosition(), ShortStubLength()))
    rate_config = CompoundRateConfig(ACT365(), Exponential(), compound_schedule; margin=MarginOnCompoundedRate(AdditiveMargin(2)))
    @test forward_rate(schedules, rate_market_data, rate_config)[1] ≈ 0.05 + 2
end


@testitem "compounded forward rates with 0 margin on underlying" begin
    # create rate curve
    using Dates
    rate_curve = FlatRateCurve("FlatCurve", Date(2000,1,1), 0.05, ACT365(), LinearRate())
    fixings = RateFixingTuples(Base.ImmutableDict(Date(2000,1,1) => 0.05))
    rate_market_data = RateMarketData(RateIndex("dummyRate"), rate_curve, fixings)

    pay_dates = [Date(2001,1,1)]

    accrual_dates = [Date(2000,1,1), Date(2000,2,1), Date(2000,3,1)]
    fixing_dates = accrual_dates[1:end-1]
    discount_start_dates = fixing_dates
    discount_end_dates = accrual_dates[2:end]
    compounding_schedules = [SimpleRateSchedule(fixing_dates, discount_start_dates, discount_end_dates, accrual_dates, ACT365())]
    schedules = CompoundedRateSchedules(pay_dates, compounding_schedules)
    compound_schedule = ScheduleConfig(Month(1); stub_period=StubPeriod(UpfrontStubPosition(), ShortStubLength()))
    rate_config = CompoundRateConfig(ACT365(), LinearRate(), TimeShift(Day(0)), compound_schedule, MarginOnUnderlying(AdditiveMargin(0)), CompoundedRate())
    @test forward_rate(schedules, rate_market_data, rate_config)[1] ≈ 0.05
end

@testitem "compounded forward rates with 0 margin on underlying with different rate conventions between curve and product" begin
    # create rate curve
    using Dates
    rate_curve = FlatRateCurve("FlatCurve", Date(2000,1,1), 0.05, ACT365(), LinearRate())

    pay_dates = [Date(2001,1,1)]
    fixings = RateFixingTuples(Base.ImmutableDict(Date(2000,1,1) => 0.05))
    rate_market_data = RateMarketData(RateIndex("dummyRate"), rate_curve, fixings)
    accrual_dates = [Date(2000,1,1), Date(2000,2,1), Date(2000,3,1)]
    fixing_dates = accrual_dates[1:end-1]
    discount_start_dates = fixing_dates
    discount_end_dates = accrual_dates[2:end]
    compounding_schedules = [SimpleRateSchedule(fixing_dates, discount_start_dates, discount_end_dates, accrual_dates, ACT365())]
    schedules = CompoundedRateSchedules(pay_dates, compounding_schedules)
    compound_schedule = ScheduleConfig(Month(1); stub_period=StubPeriod(UpfrontStubPosition(), ShortStubLength()))
    rate_config = CompoundRateConfig(ACT365(), LinearRate(), TimeShift(Day(0)), compound_schedule, MarginOnUnderlying(AdditiveMargin(0)), CompoundedRate())
    calculated_forward = forward_rate(schedules, rate_market_data, rate_config)[1]

    @test calculated_forward ≈ 0.05
end

@testitem "compounded forward rates with non-zero margin on underlying with different rate conventions between curve and product" begin
    # create rate curve
    using Dates
    rate_curve = FlatRateCurve("FlatCurve", Date(1999,12,31), 0.05, ACT365(), Exponential())
    pay_dates = [Date(2001,1,1)]

    accrual_dates = [Date(2000,1,1), Date(2000,2,1), Date(2000,3,1)]
    fixing_dates = accrual_dates[1:end-1]
    discount_start_dates = fixing_dates
    discount_end_dates = accrual_dates[2:end]
    compounding_schedules = [SimpleRateSchedule(fixing_dates, discount_start_dates, discount_end_dates, accrual_dates, ACT365())]
    schedules = CompoundedRateSchedules(pay_dates, compounding_schedules)
    compound_schedule = ScheduleConfig(Month(1); stub_period=StubPeriod(UpfrontStubPosition(), ShortStubLength()))
    rate_config = CompoundRateConfig(ACT365(), LinearRate(), compound_schedule, margin=MarginOnUnderlying(AdditiveMargin(0.02)), compounding_style=Hedgehog.CompoundedRate())
    calculated_forward = forward_rate(schedules, RateMarketData(rate_curve), rate_config)[1]

    compounded_accrual = (exp(31/365 * 0.05) - 1 + 31/365 * 0.02) * (exp(29/365 * 0.05) + 0.02 * 29/365) + exp(29/365 * 0.05) - 1 + 29/365 * 0.02
    compounded_rate = (compounded_accrual) / 60 * 365
    @test calculated_forward ≈ compounded_rate
end

@testitem "average forward rates with non-zero margin on underlying with different rate conventions between curve and product" begin
    # create rate curve
    using Dates
    rate_curve = FlatRateCurve("FlatCurve", Date(2000,1,1), 0.05, ACT365(), Exponential())
    fixings = RateFixingTuples(Base.ImmutableDict(Date(2000,1,1) => 0.05))
    rate_market_data = RateMarketData(RateIndex("dummyRate"), rate_curve, fixings)
    pay_dates = [Date(2001,1,1)]

    accrual_dates = [Date(2000,1,1), Date(2000,2,1), Date(2000,3,1)]
    fixing_dates = accrual_dates[1:end-1]
    discount_start_dates = fixing_dates
    discount_end_dates = accrual_dates[2:end]
    compounding_schedules = [SimpleRateSchedule(fixing_dates, discount_start_dates, discount_end_dates, accrual_dates, ACT365())]
    schedules = CompoundedRateSchedules(pay_dates, compounding_schedules)
    compound_schedule = ScheduleConfig(Month(1); stub_period=StubPeriod(UpfrontStubPosition(), ShortStubLength()))
    rate_config = CompoundRateConfig(ACT365(), LinearRate(), compound_schedule, margin=MarginOnUnderlying(AdditiveMargin(0.02)), compounding_style=Hedgehog.AverageRate())
    calculated_forward = forward_rate(schedules, rate_market_data, rate_config)[1]

    rate_first = 0.05
    rate_second = (exp(29/365 * 0.05) - 1) / (29/365)
    average = (rate_first * 31 + rate_second * 29) / 60 + 0.02
    @test calculated_forward ≈ average
end

@testitem "Configured compounded forward rates with non-zero margin on underlying with different rate conventions between curve and product" begin
    # create rate curve
    using Dates
    start_date = Date(2000,1,1)
    end_date = Date(2000,3,1)
    fixings = RateFixingTuples(Base.ImmutableDict(Date(2000,1,1) => 0.05))
    # create rate curve
    rate_curve = FlatRateCurve("FlatCurve", start_date, 0.05, ACT365(), Exponential())
    rate_index = RateIndex("RateIndex")
    rate_market_data = RateMarketData(rate_index, rate_curve, fixings)
    # instrument rate definition
    margin = MarginOnUnderlying(AdditiveMargin(0.02))
    rate_config = CompoundRateConfig(ACT360(), LinearRate(), ScheduleConfig(Month(1)); fixing_shift=NoShift(false), margin=margin)
    instrument_rate = CompoundInstrumentRate(rate_index, rate_config)

    # instrument schedule definition
    schedule_config = ScheduleConfig(Month(2))
    instrument_schedule = InstrumentSchedule(start_date, end_date, schedule_config)

    # stream configuration
    stream_config = FloatStreamConfig(1, instrument_rate, instrument_schedule)
    
    # stream pre-computation (schedules and day-counts)
    stream = CompoundFloatRateStream(stream_config)

    calculated_forward = forward_rate(stream, rate_market_data)

    compounded_accrual = (31/360 * 0.07) * (exp(29/365 * 0.05) + 0.02 * 29/360) + exp(29/365 * 0.05) - 1 + 29/360 * 0.02
    compounded_rate = (compounded_accrual) / 60 * 360
    @test calculated_forward[1] ≈ compounded_rate
end

@testitem "Configured average forward rates with non-zero margin on underlying with different rate conventions between curve and product" begin
    # create rate curve
    using Dates
    start_date = Date(2000,1,1)
    end_date = Date(2000,3,1)
    fixings = RateFixingTuples(Base.ImmutableDict(Date(2000,1,1) => 0.05))
    # create rate curve
    rate_curve = FlatRateCurve("FlatCurve", start_date, 0.05, ACT365(), Exponential())
    rate_market_data = RateMarketData(RateIndex("dummyRate"), rate_curve, fixings)

    # instrument rate definition
    margin = MarginOnUnderlying(AdditiveMargin(0.02))
    rate_config = CompoundRateConfig(ACT360(), LinearRate(), ScheduleConfig(Month(1)); margin=margin, compounding_style=AverageRate())
    instrument_rate = CompoundInstrumentRate(RateIndex("RateIndex", Hedgehog.ForwardLooking(), Month(1), NoHolidays(), NoneBusinessDayConvention()), rate_config)

    # instrument schedule definition
    schedule_config = ScheduleConfig(Month(2))
    instrument_schedule = InstrumentSchedule(start_date, end_date, schedule_config)

    # stream configuration
    stream_config = FloatStreamConfig(1, instrument_rate, instrument_schedule)
    
    # stream pre-computation (schedules and day-counts)
    stream = CompoundFloatRateStream(stream_config)

    calculated_forward = forward_rate(stream, rate_market_data)[1]

    rate_first = 0.05 * 365/360
    rate_second = (exp(29/365 * 0.05) - 1) / (29/365)
    # here the averaging is done on the rate converted to the ACT360 convention
    average = ((rate_first * 31 + rate_second * 29)) * 360 / 365 / 60 + 0.02 
    @test calculated_forward ≈ average
end

@testitem "Checking convergence of daily compounding with margin on underlying and continuous compounding with margin" begin
    # create rate curve
    using Dates
    rate_curve = FlatRateCurve("FlatCurve", Date(1999,1,1), 0.05, ACT365(), Exponential())

    pay_dates = [Date(2001,1,1)]

    start_date = Date(2000,1,1)
    end_date = Date(2100,1,1)
    accrual_dates = collect(start_date:Day(1):end_date)
    fixing_dates = accrual_dates[1:end-1]
    discount_start_dates = fixing_dates
    discount_end_dates = accrual_dates[2:end]
    compounding_schedules = [SimpleRateSchedule(fixing_dates, discount_start_dates, discount_end_dates, accrual_dates, ACT365())]
    schedules = CompoundedRateSchedules(pay_dates, compounding_schedules)
    compound_schedule = ScheduleConfig(Month(1); stub_period=StubPeriod(UpfrontStubPosition(), ShortStubLength()))
    rate_config = CompoundRateConfig(ACT365(), LinearRate(), compound_schedule; margin=MarginOnUnderlying(AdditiveMargin(0.02)))
    
    calculated_forward = forward_rate(schedules, RateMarketData(rate_curve), rate_config)[1]
    total_day_count = day_count_fraction(start_date, end_date, ACT365())
    total_accrual = 1 + calculated_forward * total_day_count
    
    @test log(total_accrual) / total_day_count ≈ 0.07 atol = 1E-5
end

@testitem "Past Cash Rate Conversion" begin
    using Dates
    using BusinessDays

    # market data objects
    present_date = Date(2000,1,1)
    tenor = Month(3)
    calendar = WeekendsOnly()
    business_day_convention = NoneBusinessDayConvention()
    rate_index = RateIndex("MyRate", Hedgehog.ForwardLooking(), tenor, calendar, business_day_convention, LinearRate(), ACT365())
    rate_curve = FlatRateCurve("FlatCurve", present_date, 0.05, ACT365(), Exponential())
    fixings = RateFixingTuples(Base.ImmutableDict(Date(2000,1,1) => 0.05))
    rate_market_data = RateMarketData(rate_index, rate_curve, fixings)

    # trade specifics
    principal = 1E6
    rate_config = SimpleRateConfig(ACT365(), LinearRate(), NoShift(false), AdditiveMargin(0))
    rate = SimpleInstrumentRate(rate_index, rate_config)
    start_date = Date(2000,1,1)
    end_date = Date(2000,4,1)
    schedule_config = ScheduleConfig(tenor)
    schedule = InstrumentSchedule(start_date, end_date, schedule_config, NoShift(false))
    float_stream_config = FloatStreamConfig(principal, rate, schedule)
    schedules = SimpleRateSchedule(float_stream_config)
    forward_rate_values = forward_rate(schedules, rate_market_data, rate_config)
    
    @test forward_rate_values[1] == 0.05
end