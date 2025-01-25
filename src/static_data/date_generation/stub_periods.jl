"""
    Abstract type representing the stub position in a schedule.
"""
abstract type StubPosition end

"""
    UpfrontStubPosition <: StubPosition

Represents the stub position at the start (upfront) of a schedule.
"""
struct UpfrontStubPosition <: StubPosition end

"""
    InArrearsStubPosition <: StubPosition

Represents the stub position at the end (in arrears) of a schedule.
"""
struct InArrearsStubPosition <: StubPosition end

"""
    Abstract type representing the stub length in a schedule.
"""
abstract type StubLength end

"""
    ShortStubLength <: StubLength

Represents a short stub length in a schedule.
"""
struct ShortStubLength <: StubLength end

"""
    LongStubLength <: StubLength

Represents a long stub length in a schedule.
"""
struct LongStubLength <: StubLength end

"""
    StubPeriod{P<:StubPosition, L<:StubLength}

Represents the stub period in a schedule, consisting of a position (`P`) and a length (`L`).

# Fields
- `position::P`: The position of the stub (e.g., upfront or in arrears).
- `length::L`: The length of the stub (e.g., short or long).
"""
struct StubPeriod{P<:StubPosition, L<:StubLength}
    position::P
    length::L
end

"""
    StubPeriod()

Creates a default `StubPeriod` with the position set to `InArrearsStubPosition` and length set to `ShortStubLength`.
"""
function StubPeriod()
    return StubPeriod(InArrearsStubPosition(), ShortStubLength())
end