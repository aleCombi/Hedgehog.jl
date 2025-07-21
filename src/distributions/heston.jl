"""
    LogHestonProblem(μ, κ, Θ, σ, ρ, u0, tspan; seed=UInt64(0), kwargs...)

Constructs an `SDEProblem` representing the Heston model dynamics using Euler-Maruyama.
Returns a `SDEProblem` with correlated Brownian motion and user-specified initial values.
"""
function LogHestonProblem(μ, κ, Θ, σ, ρ, u0, tspan; seed = UInt64(0), kwargs...)
    f = function (u, p, t)
        adj_var = max(u[2], 0)
        return [μ - 0.5 * adj_var, κ * (Θ - adj_var)]
    end

    g = function (u, p, t)
        adj_var = sqrt(max(u[2], 0))
        return [adj_var, σ * adj_var]
    end

    Γ = [1 ρ; ρ 1]

    noise = CorrelatedWienerProcess(Γ, tspan[1], zeros(2))

    sde_f = SDEFunction{false}(f, g)
    return SDEProblem(
        sde_f,
        u0,
        (tspan[1], tspan[2]),
        noise = noise,
        seed = seed,
        kwargs...,
    )
end

function LogGBMProblem(μ, σ, u0, tspan; seed = UInt64(0), kwargs...)
    f = function (u, p, t)
        return @. μ - 0.5 * σ^2  # Drift of log(S_t)
    end
    g = function (u, p, t)
        return @. σ  # Constant diffusion for log(S_t)
    end

    noise = WienerProcess(tspan[1], 0.0)

    sde_f = SDEFunction(f, g)
    return SDEProblem{false}(
        sde_f,
        u0,
        (tspan[1], tspan[2]),
        noise = noise,
        seed = seed,
        kwargs...,
    )
end

function LogGBMProblem!(μ, σ, u0, tspan; seed = UInt64(0), kwargs...)
    f! = function (du, u, p, t)
        @. du = μ - 0.5 * σ^2  # Drift of log(S_t)
    end
    g! = function (du, u, p, t)
        @. du = σ  # Constant diffusion
    end

    noise = WienerProcess(tspan[1], 0.0)

    sde_f = SDEFunction{true}(f!, g!)
    return SDEProblem(
        sde_f,
        u0,
        (tspan[1], tspan[2]),
        noise = noise,
        seed = seed,
        kwargs...,
    )
end


"""
    HestonNoise(μ, κ, θ, σ, ρ, t0, W0, Z0=nothing; kwargs...)

Constructs a custom `NoiseProcess` using the exact Heston distribution for the next increment.
Returns a `NoiseProcess` sampling from the Heston distribution at each timestep.
"""
function HestonNoise(μ, κ, θ, σ, ρ, t0, W0, Z0 = nothing; kwargs...)
    @inline function Heston_dist(DW, W, dt, u, p, t, rng) #dist
        S, V = exp(W[end][1]), W[end][2]
        heston_dist_at_t = LogHestonDistribution(S, V, κ, θ, σ, ρ, μ, dt)
        S1, V1 = @fastmath rand(rng, heston_dist_at_t; kwargs...)  # Calls exact Heston sampler
        return [S1 - W[end][1], V1 - W[end][2]]
    end

    return NoiseProcess{false}(t0, W0, Z0, Heston_dist, nothing)
end

"""
    LogHestonDistribution <: ContinuousMultivariateDistribution

Container type for Heston model parameters, used for exact sampling.
Fields:
- `S0`, `V0`: initial spot and variance
- `κ`, `θ`, `σ`, `ρ`: mean reversion, long-term variance, vol-of-vol, and correlation
- `r`, `T`: risk-free rate and maturity
"""
struct LogHestonDistribution{TS0,TV0,Tκ,Tθ,Tσ,Tρ,Tr,T} <: ContinuousMultivariateDistribution
    S0::TS0
    V0::TV0
    κ::Tκ
    θ::Tθ
    σ::Tσ
    ρ::Tρ
    r::Tr
    T::T
end


import Distributions: length

function Base.length(::LogHestonDistribution)
    return 2 # The Heston model is a 2-dimensional process (Asset Price, Variance)
end

"""
    sample_V_T(rng, d::LogHestonDistribution)

Samples the terminal variance `V_T` from the noncentral chi-squared distribution implied by the Heston model.
"""
function sample_V_T(rng::AbstractRNG, d::LogHestonDistribution)
    κ, θ, σ, V0, T = d.κ, d.θ, d.σ, d.V0, d.T

    d = 4 * κ * θ / σ^2  # Degrees of freedom
    λ = 4 * κ * exp(-κ * T) * V0 / (σ^2 * (-expm1(-κ * T)))  # Noncentrality parameter
    c = σ^2 * (-expm1(-κ * T)) / (4 * κ)  # Scaling factor
    V_T = c * Distributions.rand(rng, NoncentralChisq(d, λ))
    return V_T
end

"""
    sample_integral_V(VT, rng, dist::LogHestonDistribution; kwargs...)

Samples the integral ∫₀ᵗ V_s ds conditional on initial and terminal variance using the characteristic function method.
"""
function sample_integral_V(VT, rng, dist::LogHestonDistribution; kwargs...)
    ϕ = HestonCFIterator(VT, dist)
    return sample_from_cf(rng, ϕ; kwargs...)
end

"""
    HestonCFIterator

Precomputes constants for efficient evaluation of the characteristic function of ∫₀ᵗ V_s ds.
"""
struct HestonCFIterator{TVT, TDist<:LogHestonDistribution, TLogIκ, Tζκ, Tηκ, Tν}
    VT::TVT
    dist::TDist
    logIκ::TLogIκ
    ζκ::Tζκ
    ηκ::Tηκ
    ν::Tν
end


"""
    HestonCFIterator(VT, dist::LogHestonDistribution)

Constructs a `HestonCFIterator` used for evaluating the characteristic function of the integral of variance.
"""
function HestonCFIterator(VT, dist::LogHestonDistribution)
    κ, θ, σ, V0, T = dist.κ, dist.θ, dist.σ, dist.V0, dist.T
    d = 4 * κ * θ / σ^2
    ν = 0.5 * d - 1

    ζκ = (-expm1(-κ * T)) / κ
    ηκ = κ * (1 + exp(-κ * T)) / (-expm1(-κ * T))
    νκ = √(V0 * VT) * 4 * κ * exp(-0.5 * κ * T) / σ^2 / (-expm1(-κ * T))
    logIκ = log(besseli(ν, νκ))

    return HestonCFIterator(VT, dist, logIκ, ζκ, ηκ, ν)
end

"""
    evaluate_chf(iter::HestonCFIterator, a::Real, θ_prev)

Evaluates the characteristic function at point `a`, unwrapping the angle using `θ_prev` to ensure continuity.
Returns the characteristic function value and updated unwrapped angle.
"""
function evaluate_chf(iter::HestonCFIterator, a::Real, θ_prev::Tθ) where {Tθ}
    κ, θ, σ, V0, T = iter.dist.κ, iter.dist.θ, iter.dist.σ, iter.dist.V0, iter.dist.T
    ν = iter.ν
    ζκ, ηκ, logIκ = iter.ζκ, iter.ηκ, iter.logIκ
    VT = iter.VT

    γ = sqrt(κ^2 - 2 * σ^2 * a * im)
    ζγ = (1 - exp(-γ * T)) / γ
    ηγ = γ * (1 + exp(-γ * T)) / (1 - exp(-γ * T))
    νγ = √(V0 * VT) * 4 * γ * exp(-0.5 * γ * T) / σ^2 / (1 - exp(-γ * T))

    first_term = exp(-0.5 * (γ - κ) * T) * (ζκ / ζγ)
    second_term = exp((V0 + VT) / σ^2 * (ηκ - ηγ))

    θ = angle(νγ)
    θ_unwrapped = if isnan(θ_prev)
        θ
    else
        δ = θ - θ_prev
        δ -= 2π * round(δ / (2π))
        θ_prev + δ
    end
    νγ_unwrapped = abs(νγ) * cis(θ_unwrapped)
    logIγ = log(besseli(ν, νγ_unwrapped)) + im * ν * (θ_unwrapped - θ)
    bessel_ratio = exp(logIγ - logIκ)

    ϕ = first_term * second_term * bessel_ratio
    return ϕ, θ_unwrapped
end

"""
    log_besseli_corrected(ν, z, θ_ref)

Computes the logarithm of the modified Bessel function of the first kind, correcting angle discontinuities.
Used for numerical stability in CF evaluation.
"""
function log_besseli_corrected(ν, z::Complex, θ_ref::Ref{Float64})
    θ = angle(z)
    if isnan(θ_ref[])
        θ_ref[] = θ  # initialize
    end

    # unwrap angle relative to previous
    δ = θ - θ_ref[]
    if δ > π
        δ -= 2π
    elseif δ < -π
        δ += 2π
    end
    θ_unwrapped = θ_ref[] + δ
    θ_ref[] = θ_unwrapped

    z_unwrapped = abs(z) * cis(θ_unwrapped)
    return log(besseli(ν, z_unwrapped)) + im * ν * (θ_unwrapped - θ)
end

"""
    rand(rng, d::LogHestonDistribution; kwargs...)

Alternative sampling version returning `[log(S_T), V_T]` instead of `S_T`.
Useful for testing and diagnostics.
"""
function rand(rng::AbstractRNG, d::LogHestonDistribution; antithetic = false, kwargs...)
    d1 = LogHestonDistribution(d.S0, d.V0, d.κ, d.θ, d.σ, d.ρ, d.r, d.T)

    # Step 1: Sample V_T
    V_T = sample_V_T(rng, d1)

    # Step 2: Sample ∫ V_t dt, conditional V0 and VT
    integral_V = sample_integral_V(V_T, rng, d1; kwargs...)

    # Step 3: Sample log(S_T) with antithetic option
    log_S_T = sample_log_S_T(V_T, integral_V, rng, d1, antithetic = antithetic)

    return [log_S_T, V_T]
end

function Distributions.rand!(
    rng::AbstractRNG,
    d::LogHestonDistribution,
    x::AbstractVector{<:Real};
    antithetic = false,
    kwargs...
)
    # Call your allocating rand function
    sample = rand(rng, d; antithetic=antithetic, kwargs...)
    
    # Copy the result into the pre-allocated vector x
    x[1] = sample[1]
    x[2] = sample[2]
    
    return x
end

function sample_log_S_T(
    V_T,
    integral_V,
    rng::AbstractRNG,
    d::LogHestonDistribution;
    antithetic = false,
)
    κ, θ, σ, ρ, V0, T, S0, r = d.κ, d.θ, d.σ, d.ρ, d.V0, d.T, d.S0, d.r

    # Compute conditional mean
    mu =
        log(S0) + r * T - 0.5 * integral_V +
        (ρ / σ) * (V_T - V0 - κ * θ * T + κ * integral_V)

    # Compute conditional variance
    sigma2 = (1 - ρ^2) * integral_V

    # Generate random normal and apply antithetic if needed
    Z = randn(rng)
    log_S_T = mu + sqrt(sigma2) * (antithetic ? -Z : Z)

    return log_S_T
end

"""
    characteristic_function(d::LogHestonDistribution, u)

Computes the characteristic function of `log(S_T)` under the Heston model at complex value `u`.
"""
function cf(d::LogHestonDistribution, u)
    T, S0, V0, κ, θ, σ, ρ, r = d.T, d.S0, d.V0, d.κ, d.θ, d.σ, d.ρ, d.r

    d1 = sqrt((κ - ρ * σ * im * u)^2 + σ^2 * (im * u + u^2))
    g = (κ - ρ * σ * im * u - d1) / (κ - ρ * σ * im * u + d1)

    C =
        (κ * θ / σ^2) *
        ((κ - ρ * σ * im * u - d1) * T - 2 * log((1 - g * exp(-d1 * T)) / (1 - g)))
    D = ((κ - ρ * σ * im * u - d1) / σ^2) * ((1 - exp(-d1 * T)) / (1 - g * exp(-d1 * T)))

    return exp(C + D * V0 + im * u * log(S0) + im * u * r * T)
end
