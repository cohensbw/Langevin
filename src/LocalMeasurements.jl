module LocalMeasurements

using Printf
using ..HolsteinModels: HolsteinModel, get_index, get_site, get_τ
using ..LangevinSimulationParameters: SimulationParameters
using ..GreensFunctions: EstimateGreensFunction, estimate

export make_local_measurements!
export construct_local_measurements_container
export process_local_measurements!
export reset_local_measurements!
export initialize_local_measurements_file
export write_local_measurements


function make_local_measurements!(container::Dict{String,Vector{T}}, holstein::HolsteinModel, Gr1::EstimateGreensFunction, Gr2::EstimateGreensFunction) where {T<:Number}
    
    # phonon fields
    ϕ = holstein.ϕ

    # phonon frequncies
    ω = holstein.ω

    # electron-phonon coupling
    λ = holstein.λ

    # getting number of orbitals
    norbits = holstein.lattice.norbits::Int

    # number of physical sites in lattice
    nsites = holstein.nsites::Int

    # length of imaginary time axis
    Lτ = holstein.Lτ::Int

    # for measuring phonon kinetic energy
    Δτ  = holstein.Δτ
    Δτ² = Δτ * Δτ

    # normalization
    normalization = div(nsites,norbits)*Lτ

    # iterating over orbital types
    @fastmath @inbounds for orbit in 1:norbits
        # iterating over orbits of the current type
        for site in orbit:norbits:nsites
            # iterating over time slices
            @simd for τ in 1:Lτ
                # getting current index
                index = get_index(τ,site,Lτ)
                # estimate ⟨cᵢ(τ)c⁺ᵢ(τ)⟩
                G1 = estimate(Gr1,site,site,τ,τ)
                G2 = estimate(Gr2,site,site,τ,τ)
                # measure density
                container["density"][orbit] += (2.0-G1-G2) / normalization
                # measure double occupancy
                container["double_occ"][orbit] += (1.0-G1)*(1.0-G2) / normalization
                # measuring phonon kinetic energy such that
                # ⟨KE⟩ = 1/(2Δτ) - ⟨[ϕᵢ(τ+1)-ϕᵢ(τ)]²/Δτ²⟩
                Δϕ = ϕ[get_index(τ%Lτ+1,site,Lτ)]-ϕ[index]
                container["phonon_kin"][orbit] += (0.5/Δτ-(Δϕ*Δϕ)/Δτ²/2) / normalization
                # measuring phonon potential energy
                container["phonon_pot"][orbit] += ω[site]*ω[site]*ϕ[index]*ϕ[index]/2.0 / normalization
                # measuring the electron phonon energy λ⟨ϕ⋅(n₊+n₋)⟩
                container["elph_energy"][orbit] += λ[site]*ϕ[index]*(2.0-G1-G2) / normalization
                # measure ⟨ϕ⟩
                container["phi"][orbit] += ϕ[index] / normalization
                # measure ⟨ϕ²⟩
                container["phi_squared"][orbit] += ϕ[index]*ϕ[index] / normalization
            end
        end
    end
end


"""
Construct a dictionary to hold local measurement data.
"""
function construct_local_measurements_container(holstein::HolsteinModel{T1,T2})::Dict{String,Vector{T1}} where {T1<:AbstractFloat,T2<:Number}

    local_meas_container = Dict()
    for meas in ("density", "double_occ", "phonon_kin", "phonon_pot", "elph_energy", "phi_squared", "phi")
        local_meas_container[meas] = zeros(T1,holstein.lattice.norbits)
    end
    return local_meas_container
end


"""
Process Local Measurements.
"""
function process_local_measurements!(container::Dict{String,Vector{T}}, sim_params::SimulationParameters{T}, holstein::HolsteinModel) where {T<:Number}

    for key in keys(container)
        container[key] ./= sim_params.bin_size
    end
    # @. container["phonon_kin"] = 0.5/holstein.Δτ - container["phonon_kin"]/2
end


"""
Reset the arrays that contain the measurements to all zeros.
"""
function reset_local_measurements!(container::Dict{String,Vector{T}}) where {T<:Number}

    for key in keys(container)
        container[key] .= 0.0
    end
end


"""
Initializes file that will contain local measurement data, with header included.
"""
function initialize_local_measurements_file(container::Dict{String,Vector{T}}, sim_params::SimulationParameters{T}) where {T<:Number}

    open(sim_params.datafolder*"local_measurements.out", "w") do file
        write(file, "orbit")
        for key in keys(container)
            write(file, ",", key)
        end
        write(file, "\n")
    end
    return nothing
end


"""
Write non-local measurements to file.
"""
function write_local_measurements(container::Dict{String,Vector{T}}, sim_params::SimulationParameters{T}, holstein::HolsteinModel) where {T<:Number}

    open(sim_params.datafolder*"local_measurements.out", "a") do file
        for orbit in 1:holstein.lattice.norbits
            write(file, string(orbit))
            for key in keys(container)
                write(file, @sprintf(",%.6f", container[key][orbit]))
            end
            write(file, "\n")
        end
    end
end

end