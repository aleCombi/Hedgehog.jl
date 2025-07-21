using StochasticDiffEq, DiffEqNoiseProcess, BenchmarkTools, Profile, Random, SciMLBase

r, σ, t₀, S₀ = 0.02, 0.3, 0.0, 1.0
T = 1.0
tspan = (t₀, T)
noise = GeometricBrownianMotionProcess(r, σ, t₀, S₀)
noise_problem = NoiseProblem(noise, tspan)
ens_problem = EnsembleProblem(noise_problem)
ens_sol = StochasticDiffEq.solve(ens_problem; dt=T, trajectories=1000)

struct FakeSolution{T,U}
    t::Vector{T}
    u::Vector{U}
end

# Alias .W to .u
function Base.getproperty(sol::FakeSolution, name::Symbol)
    if name === :W
        return getfield(sol, :u)
    else
        return getfield(sol, name)
    end
end

struct FakeProblem{P<:NoiseProblem, F<:FakeSolution}
    base_prob::P         # shared setup (no duplication)
    solutions::Vector{F}  # precomputed or simulated paths
end

function simple_solve(noise_problem; steps)
    rng = Random.default_rng()
    T = noise_problem.tspan[end]
    gbm = noise_problem.noise
    ΔT = T / steps
    times = [0.0]
    values = [gbm.u[1]]
    sol = FakeSolution(times, values)
    ΔW = 0.0

    for i in 1:steps
        t_next = sol.t[end] + ΔT
        ΔW = gbm.dist(ΔW, sol, ΔT, sol, nothing, t_next, rng)
        push!(sol.t, t_next)
        push!(sol.u, sol.W[end] + ΔW)
    end

    return sol
end

function generate_ensemble_solution(r, σ, S₀, T, t₀, steps, Npaths)
    noise = GeometricBrownianMotionProcess(r, σ, t₀, S₀)
    noise_problem = NoiseProblem(noise, (t₀, T))
    paths = Vector{FakeSolution{Float64, Float64}}(undef, Npaths)
    for i in 1:Npaths
        paths[i] = simple_solve(noise_problem; steps=steps)
    end
    return SciMLBase.EnsembleSolution{FakeSolution{Float64, Float64}, 1, FakeProblem}(
        FakeProblem(noise_problem, paths), 1.0, true, nothing)
end

Base.length(v::FakeProblem) = Base.length(v.solutions)
Base.getindex(fp::FakeProblem, i::Int) = fp.solutions[i]
Base.iterate(fp::FakeProblem) = iterate(fp.solutions)
Base.iterate(fp::FakeProblem, state) = iterate(fp.solutions, state)

ens_sol = generate_ensemble_solution(r, σ, S₀, T,t₀, 10, 100000)

terminal_values = [el.u[end] for el in ens_sol.u]
mean_exp = mean(log.(terminal_values))
mean_an = r - σ^2 / 2

@show mean_an
@show mean_exp

display(@benchmark generate_ensemble_solution(r, σ, S₀, T,t₀, 1, 5000))