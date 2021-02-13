module Langevin

# set number of threads to be used by BLAS to 1
using LinearAlgebra
BLAS.set_num_threads(1)

# setting number of threads used by FFTW to 1
using FFTW
FFTW.set_num_threads(1)

#######################
## INCLUDING MODULES ##
#######################

include("Utilities.jl")

include("UnitCells.jl")

include("Lattices.jl")

include("Checkerboard.jl")

include("IterativeSolvers.jl")

include("TimeFreqFFTs.jl")

include("Models.jl")

include("KPMPreconditioners.jl")

include("InitializePhonons.jl")

include("PhononAction.jl")

include("FourierAcceleration.jl")

include("LangevinDynamics.jl")

include("HMC.jl")

include("GreensFunctions.jl")

include("SimulationParams.jl")

include("Measurements.jl")

include("MuFinder.jl")

include("RunSimulation.jl")

include("SimulationSummary.jl")

include("ProcessInputFile.jl")

####################################
## DEFINING HIGHET LEVEL FUNCTION ##
##     TO RUN A SIMULATION        ##
####################################

using ..RunSimulation: run_simulation!
using ..ProcessInputFile: process_input_file, initialize_model
using ..Models: read_phonons!
using ..MuFinder: MuTuner, update_μ!
using ..SimulationSummary: write_simulation_summary!

export simulate, load_model

"""
Highest level function used to run a langevin simulation.
To run a simulation execute the following command:
`julia -O3 -e "using Langevin; simulate(ARGS)" -- input.toml`
"""
function simulate(args)

    ########################
    ## READING INPUT FILE ##
    ########################

    # getting iput filename
    input_file = args[1]

    # precoessing input file
    model, Gr, μ_tuner, sim_params, simulation_dynamics, burnin_dynamics, fourier_accelerator, preconditioner, input = process_input_file(input_file)

    ########################
    ## RUNNING SIMULATION ##
    ########################

    simulation_time, measurement_time, write_time, iters, acceptance_rate, container = run_simulation!(model, Gr, μ_tuner, sim_params, simulation_dynamics, burnin_dynamics, fourier_accelerator, input["measurements"], preconditioner)

    ###################################
    ## SUMARIZING SIMULATION RESULTS ##
    ###################################

    write_simulation_summary!(model, sim_params, μ_tuner, container, input, simulation_time, measurement_time, write_time, iters, acceptance_rate, 10)

end


"""
Pass this function a directory name generated by a simulation and it returns a HolsteinModel object
with the phonons intialized to the final phonon configuration sampled in the simulation.
"""
function load_model(dir::String)

    files = readdir(dir)
    config = findall(f -> endswith(f, r"\.toml|\.TOML"), files)
    phonon = findall(f -> endswith(f, "_config.out"), files)
    @assert length(config) == length(phonon) == 1
    config_file = joinpath(dir, files[config[1]])
    phonon_file = joinpath(dir, files[phonon[1]])
    
    model = initialize_model(config_file)
    read_phonons!(model, phonon_file)
    
    return model
end

end
