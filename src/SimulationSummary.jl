module SimulationSummary

using Statistics
using Printf
using Pkg.TOML

using ..SimulationParams: SimulationParameters
using ..HolsteinModels: HolsteinModel, write_phonons, write_M_matrix
using ..Lattices: Lattice

export write_simulation_summary


"""
Writes a simulation summary file after a simulation completes.
"""
function write_simulation_summary(holstein::HolsteinModel, input::Dict, sim_params::SimulationParameters,
                                  unequaltime_meas::AbstractVector{String}, equaltime_meas::AbstractVector{String},
                                  simulation_time::T, measurement_time::T, write_time::T, iters::T, acceptance_rate::T,
                                  nbins::Int=10) where {T<:Number}

    @assert sim_params.num_bins%nbins==0

    # getting name of output file
    outputfn = sim_params.foldername[1:end-1]*".out"

    # get list of all output files from simulation
    files = readdir(sim_params.datafolder)

    # getting info about size of lattice
    Lτ = holstein.Lτ
    L1 = holstein.lattice.L1
    L2 = holstein.lattice.L2
    L3 = holstein.lattice.L3
    norbits = holstein.lattice.norbits

    # write final phonon field configuration to file
    write_phonons(holstein,sim_params.datafolder*"phonon_config.out")

    # write M matrix to file
    if input["simulation"]["write_M_matrix"]
        write_M_matrix(holstein,sim_params.datafolder*"matrix.out")
    end

    ########################
    ## WRITE SUMMARY FILE ##
    ########################
    
    # writing summary file
    open(sim_params.datafolder*outputfn,"w") do outfile
        
        #################################
        ## COPY CONTENTS OF INPUT FILE ##
        #################################
        
        # copy contents of input file to output file
        write(outfile,"#########################\n")
        write(outfile,"## INPUT FILE CONTENTS ##\n")
        write(outfile,"#########################\n\n")
        
        TOML.print(outfile, input)
        
        ###########################
        ## WRITE SIMULATION INFO ##
        ###########################

        # total simulation time
        total_time = simulation_time + measurement_time + write_time
        
        write(outfile,"\n#####################\n")
        write(outfile,  "## SIMULATION INFO ##\n")
        write(outfile,  "#####################\n\n")
        
        write(outfile, "Simulation Time (min) = ",  @sprintf("%.4f",simulation_time), "\n")
        write(outfile, "Measurement Time (min) = ", @sprintf("%.4f",measurement_time), "\n")
        write(outfile, "Write Time (min) = ",       @sprintf("%.4f",write_time), "\n")
        write(outfile, "Total Time (min) = ",       @sprintf("%.4f",total_time), "\n")
        write(outfile, "Iterative Solver Steps = ", @sprintf("%.4f",iters), "\n")
        write(outfile, "Acceptance Rate = ", @sprintf("%.4f",acceptance_rate), "\n")
        
        ##################################
        ## WRITE LOCAL MEASUREMENT DATA ##
        ##################################
        
        write(outfile,"\n########################\n")
        write(outfile,  "## LOCAL MEASUREMENTS ##\n")
        write(outfile,  "########################\n\n")

        write_local_data(outfile, sim_params, holstein.lattice, nbins)
        
        ######################################
        ## WRITE NON-LOCAL MEASUREMENT DATA ##
        ######################################

        # container for storing non-local measurement data 
        unequaltime_container = zeros(T,nbins,Lτ,L1,L2,L3,norbits,norbits)
        equaltime_container   = zeros(T,nbins, 1,L1,L2,L3,norbits,norbits)
        
        # writing real-space non-local measurements
        write(outfile,"\n#######################################\n")
        write(outfile,  "## REAL-SPACE NON-LOCAL MEASUREMENTS ##\n")
        write(outfile,  "#######################################\n\n")

        for file in files
            # checking if real space measurement
            if endswith(file,"_r.out")
                # getting measurement
                measurement = split(file,"_")[1]
                # determine if equal time or unequal time measurement
                if measurement in unequaltime_meas
                    write_nonlocal_data(outfile, file, sim_params, unequaltime_container)
                else
                    write_nonlocal_data(outfile, file, sim_params, equaltime_container)
                end
            end
        end

        # writing momentum-space non-local measurements
        write(outfile,"\n###########################################\n")
        write(outfile,  "## MOMENTUM-SPACE NON-LOCAL MEASUREMENTS ##\n")
        write(outfile,  "###########################################\n\n")
        
        for file in files
            # checking if momentum space measurement
            if endswith(file,"_k.out")
                # getting measurement
                measurement = split(file,"_")[1]
                # determine if equal time or unequal time measurement
                if measurement in unequaltime_meas
                    write_nonlocal_data(outfile, file, sim_params, unequaltime_container)
                else
                    write_nonlocal_data(outfile, file, sim_params, equaltime_container)
                end
            end
        end

    end
end

####################
## HELPER METHODS ##
####################

"""
Write local measurements to file.
"""
function write_local_data(outfile, sim_params::SimulationParameters, lattice::Lattice{T}, nbins::Int) where {T<:Number}

    # num orbitals per unit cell
    norbits = lattice.norbits

    # data filename
    datafile = sim_params.datafolder*"local_measurements.out"

    # write local stats to own file as well
    statsfile = sim_params.datafolder*"local_measurements_stats.out"

    # open data file for local measurements
    open(datafile,"r") do fin
        open(statsfile,"w") do fout

            # write header associated with local data
            header = "measurement orbit avg std\n"
            write(outfile,header)
            write(fout,header)

            # declared array for calculating binned statistics
            bins = zeros(T,nbins)

            # get header line
            header = readline(fin)

            # get columns
            columns = split(header,",")

            # get measurements
            measurements = [String(columns[i]) for i in 2:length(columns)]

            # get number of unique measurements
            nmeasurements = length(measurements)

            # dictionary for containing data
            container = Dict( m => zeros(T,nbins,norbits) for m in measurements )

            # number of measurements per bin
            bin_size = div( sim_params.num_bins , nbins )

            # line counter
            line_count = 0

            # iterate over lines
            for line in eachline(fin)

                # split line apart
                atoms = split(line,",")

                # get orbit
                orbit = parse(Int,atoms[1])

                # getting current bin
                bin = div( line_count , norbits * bin_size ) + 1

                # iterate over measurements
                for i in 1:nmeasurements

                    # incrementing value in container
                    container[measurements[i]][bin,orbit] += parse(T,atoms[i+1]) / bin_size
                end

                # increment line count
                line_count += 1
            end

            # iterate over measurements
            for measurement in measurements

                # iterate over orbits
                for orbit in 1:norbits

                    # get data
                    data = @view container[measurement][:,orbit]

                    # calcualte average and standard deviation measreument
                    avg, sd = binned_statistics(data,bins)

                    # writing measurement to file
                    line = measurement*@sprintf(" %d  %.6f  %.6f\n",orbit,avg,sd)
                    write(outfile, line)
                    write(fout, line)
                end
            end
        end
    end

    return nothing
end

"""
Writes non-local measurement data to summary stats file.
"""
function write_nonlocal_data(outfile, datafile, sim_params, container::Array{T,7}) where {T<:Number}

    # getting measurement
    measurement = split(datafile,"_")[1]

    # getting info about size of data container
    nbins, Lτ, L1, L2, L3, norbits, norbits_copy = size(container)

    # caluculate number of measurments that go into each bin
    bin_size = div( sim_params.num_bins , nbins )

    # number of unique displacement vectors for which the measuremnt was made
    nvectors = Lτ*L1*L2*L3*norbits^2

    # empty container
    fill!(container,0.0)

    # read in data, and store in container
    open(sim_params.datafolder*datafile,"r") do fp

        # read in header
        header = readline(fp)

        # keeps track of the number of lines read in
        line_count = 0

        # iterate over lines of data
        for line in eachline(fp)

            # getting current bin
            bin = div( line_count , nvectors * bin_size ) + 1

            # split line into an array of strings where each index
            # corresponds to: [ orbit1 , orbit2 , dL1 , dL2 , dL3 , tau , data ]
            atoms = split(line,",")

            # extracting data
            o1   = parse(Int,atoms[1])
            o2   = parse(Int,atoms[2])
            dL1  = parse(Int,atoms[3])
            dL2  = parse(Int,atoms[4])
            dL3  = parse(Int,atoms[5])
            τ    = parse(Int,atoms[6])
            meas = parse(T,atoms[7])

            # record data
            container[bin,τ+1,dL1+1,dL2+1,dL3+1,o2,o1] += meas/bin_size

            # increment line_count
            line_count += 1
        end
    end

    # additionally, right measurement statistics to own file as well
    statsfilename = sim_params.datafolder*datafile[1:end-4]*"_stats.out"
    open(statsfilename,"w") do statsfile

        # write header for table
        header = "orbit1  orbit2  dL1  dL2  dL3  tau  "*measurement*"_avg  "*measurement*"_std\n"
        write(statsfile, header)
        write(outfile, header)

        # iterate over displacement vector
        for orbit1 in 1:norbits
            for orbit2 in 1:norbits
                for dL3 in 0:L3-1
                    for dL2 in 0:L2-1
                        for dL1 in 0:L1-1
                            for τ in 0:Lτ-1
                                data   = @view container[:,τ+1,dL1+1,dL2+1,dL3+1,orbit2,orbit1]
                                avg    = mean(data)
                                stddev = std(data)/sqrt(nbins)
                                if !iszero(avg)
                                    # write displacement info to file
                                    line = @sprintf("%d  %d  %d  %d  %d  %d  %.6f  %.6f\n",orbit1,orbit2,dL1,dL2,dL3,τ,avg,stddev)
                                    write(statsfile,line)
                                    write(outfile,line)
                                end
                            end
                        end
                    end
                end
            end
        end

        # add an additional line break
        write(outfile,"\n")

    end

    return nothing
end

"""
Calculates the average and binned standard deviation of a set of data.
The number of bins used is equal to the length of the preallocated `bins` vector
passed to the function.
"""
function binned_statistics(data::AbstractVector{T},bins::Vector{T})::Tuple{T,T} where {T<:Number}
    
    N = length(data)
    n = length(bins)
    @assert length(data)%length(bins)==0
    binsize = div(N,n)
    bins .= 0
    for bin in 1:n
        for i in 1:binsize
            bins[bin] += data[i+(bin-1)*binsize]
        end
        bins[bin] /= binsize
    end
    avg = mean(bins)
    return avg, std(bins,corrected=true,mean=avg)/sqrt(n)
end

end