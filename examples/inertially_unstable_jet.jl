using Oceananigans
using Oceananigans.Units: hours, days, seconds, meters, kilometers, minutes

using JLD2, Plots, Printf

   const Ly = 100kilometers
   const Lz = 3kilometers
    const D = Lz/2
const L_jet = Ly/10
const H_jet = Lz/10

grid = RegularRectilinearGrid(size=(128, 128), 
                                 y=(-Ly/2, Ly/2), z=(-Lz, 0),
                          topology=(Flat, Bounded, Bounded),
                             halo = (3, 3))

   coriolis = FPlane(0.73e-4)
   const N² = 1e-2
const U_max = 14.6 

B_func(x, y, z, t, N) = N² * (z + D)
                    N = sqrt(N²)
                    B = BackgroundField(B_func, parameters=N)

model = IncompressibleModel(
             grid = grid,
        advection = WENO5(),
      timestepper = :RungeKutta3,
         coriolis = coriolis,
          tracers = :b,
background_fields = (b=B,),
         buoyancy = BuoyancyTracer(),
          closure = AnisotropicDiffusivity(νh=0, νz=1.27e-2))

ū(x, y, z) =                                              U_max * sech(y/L_jet)^2 * exp( - (z + D)^2/H_jet^2 )
b̄(x, y, z) = 2 * coriolis.f * L_jet / H_jet^2 * (z + D) * U_max * tanh(y/L_jet)   * exp( - (z + D)^2/H_jet^2 )

perturbation(x, y, z) = randn() * sech(y/L_jet)^2 * exp( - (z + D)^2/H_jet^2 )
          uⁱ(x, y, z) = ū(x, y, z) + 1e-4 * perturbation(x, y, z)
          bⁱ(x, y, z) = b̄(x, y, z) + 1e-4 * perturbation(x, y, z)

set!(model, u = uⁱ, b = bⁱ)

u = model.velocities.u 
b = model.tracers.b

ũ = ComputedField(u - ū)
b̃ = ComputedField(b - b̄)

y, z = ynodes(model.velocities.u), znodes(model.velocities.u)

kwargs = (
            xlabel="y (km)", 
            ylabel="z (km)", 
         linewidth=0, 
          colorbar=true,
             xlims=(-Ly/2e3, Ly/2e3), 
             ylims=(-Lz/1e3,0)
         )

#wizard = TimeStepWizard(cfl=1.0, Δt=1minutes, max_change=1.1, max_Δt=2minutes)

progress(sim) = @printf("Iteration: %d, time: %s, Δt: %s\n",
                        sim.model.clock.iteration,
                        prettytime(sim.model.clock.time),
                        prettytime(sim.Δt))

simulation = Simulation(model, Δt=10, stop_time=2days,
                        iteration_interval=10, progress=progress)

simulation.output_writers[:fields] = JLD2OutputWriter(model, (u = ũ, b = b̃),
                                                       schedule = IterationInterval(60),
                                                         prefix = "inertial_instability",
                                                          force = true)

run!(simulation)

file = jldopen(simulation.output_writers[:fields].filepath)

iterations = parse.(Int, keys(file["timeseries/t"]))

using Plots

@info "Making a neat movie of zonal velocity and buoyancy..."

anim = @animate for (i, iteration) in enumerate(iterations)

   @info "Plotting frame $i from iteration $iteration..."

            t = file["timeseries/t/$iteration"]
   u_snapshot = file["timeseries/u/$iteration"][1, :, :]
   b_snapshot = file["timeseries/b/$iteration"][1, :, :]

   u_max = maximum(abs, u_snapshot)
   u_plot = contourf(y/1e3, z/1e3, u_snapshot',
                     title = @sprintf("ũ, at t = %.1f hours", t/hours),
                     color=:balance,
                     clim=(-u_max, u_max); 
                     kwargs...)

   b_max = maximum(abs, b_snapshot) 
   b_plot = contourf(y/1e3, z/1e3, b_snapshot',
                     title = @sprintf("b̃, at t = %.1f hours", t/hours),
                     color=:balance;
                     clim=(-b_max, b_max), 
                     kwargs...)

    plt = plot(u_plot, b_plot, layout=(1, 2), size=(1200, 500))
end

mp4(anim, "Inertial_Instability_2D.mp4", fps=15)

# To-Do
# 2. Try wizard
# 4. Do 2D and 3D simulations on cedar (cpu and then cpu)
# 5. Try MPI?