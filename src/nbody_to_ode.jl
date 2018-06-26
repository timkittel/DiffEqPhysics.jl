function gather_bodies_initial_coordinates(system::NBodySystem)
    bodies = system.bodies;
    n = length(bodies)
    u0 = zeros(3, n)
    v0 = zeros(3, n)

    for i = 1:n
        u0[:, i] = bodies[i].r 
        v0[:, i] = bodies[i].v
    end 

    (u0, v0, n)
end

function gather_bodies_initial_coordinates(system::WaterSPCFw)
    molecules = system.bodies;
    n = length(molecules)
    u0 = zeros(3, 3 * n)
    v0 = zeros(3, 3 * n)

    for i = 1:n
        p = system.scpfw_parameters
        indO, indH1, indH2 = 3 * (i - 1) + 1, 3 * (i - 1) + 2, 3 * (i - 1) + 3
        u0[:, indO] = molecules[i].r 
        u0[:, indH1] = molecules[i].r .+ [p.rOH, 0.0, 0.0]
        u0[:, indH2] = molecules[i].r .+ [cos(p.aHOH) * p.rOH, 0.0, sin(p.aHOH) * p.rOH]
        v0[:, indO] = molecules[i].v
        v0[:, indH1] = molecules[i].v
        v0[:, indH2] = molecules[i].v
    end 

    (u0, v0, n)
end

function gather_accelerations_for_potentials(simulation::NBodySimulation{CustomAccelerationSystem})
    acceleration_functions = []
    push!(acceleration_functions, simulation.system.acceleration)
    acceleration_functions
end

function gather_accelerations_for_potentials(simulation::NBodySimulation{<:PotentialNBodySystem})
    acceleration_functions = []
    
    for (potential, parameters) in simulation.system.potentials
        push!(acceleration_functions, get_accelerating_function(parameters, simulation))
    end

    acceleration_functions
end

function gather_group_accelerations(simulation::NBodySimulation{<:WaterSPCFw})
    acelerations = []
    push!(acelerations, get_group_accelerating_function(simulation.system.scpfw_parameters, simulation))
    acelerations    
end

function get_accelerating_function(parameters::LennardJonesParameters, simulation::NBodySimulation)
    (ms, indxs) = obtain_data_for_lennard_jones_interaction(simulation.system)
    (dv, u, v, t, i) -> pairwise_lennard_jones_acceleration!(dv, u, i, indxs, ms, parameters, simulation.boundary_conditions)
end

function get_accelerating_function(parameters::ElectrostaticParameters, simulation::NBodySimulation)
    (qs, ms, indxs, exclude) = obtain_data_for_electrostatic_interaction(simulation.system)
    (dv, u, v, t, i) -> pairwise_electrostatic_acceleration!(dv, u, i, length(indxs), qs, ms, exclude, parameters, simulation.boundary_conditions)
end

function get_accelerating_function(parameters::SPCFwParameters, simulation::NBodySimulation)
    (ms, neighbouhood) = obtain_data_for_harmonic_bond_interaction(simulation.system, parameters)
    (dv, u, v, t, i) -> harmonic_bond_potential_acceleration!(dv, u, i, ms, neighbouhood, parameters)
end

function get_accelerating_function(parameters::GravitationalParameters, simulation::NBodySimulation)
    (dv, u, v, t, i) -> gravitational_acceleration!(dv, u, i, length(simulation.system.bodies), simulation.system.bodies, parameters)
end

function get_accelerating_function(parameters::MagnetostaticParameters, simulation::NBodySimulation)
    (dv, u, v, t, i) -> magnetostatic_dipdip_acceleration!(dv, u, i, length(simulation.system.bodies), simulation.system.bodies, parameters)
end

function get_group_accelerating_function(parameters::PotentialParameters, simulation::NBodySimulation{<:WaterSPCFw})
    (ms, indxs) = obtain_data_for_lennard_jones_interaction(simulation.system)
    (dv, u, v, t, i) -> valence_angle_potential_acceleration!(dv, u, 3 * (i - 1) + 2, 3 * (i - 1) + 1, 3 * (i - 1) + 3, ms, parameters)
end

function obtain_data_for_harmonic_bond_interaction(system::WaterSPCFw, p::SPCFwParameters)
    neighbouhoods = Dict{Int, Vector{Tuple{Int,Float64}}}()
    n = length(system.bodies)
    ms = zeros(3 * n)
    for i in 1:n
        indO, indH1, indH2 = 3 * (i - 1) + 1, 3 * (i - 1) + 2, 3 * (i - 1) + 3
        ms[indO] = system.mO
        ms[indH1] = system.mH
        ms[indH2] = system.mH

        neighbours_o = Vector{Tuple{Int,Float64}}()
        push!(neighbours_o, (indH1, p.kb))
        push!(neighbours_o, (indH2, p.kb))
        neighbours_h1 = Vector{Tuple{Int,Float64}}()
        push!(neighbours_h1, (indO, p.kb))
        neighbours_h2 = Vector{Tuple{Int,Float64}}()
        push!(neighbours_h2, (indO, p.kb))

        neighbouhoods[indO] = neighbours_o
        neighbouhoods[indH1] = neighbours_h1
        neighbouhoods[indH2] = neighbours_h2
    end
    
    (ms, neighbouhoods)
end

function obtain_data_for_lennard_jones_interaction(system::PotentialNBodySystem)
    bodies = system.bodies
    n = length(bodies)
    ms = zeros(Real, n)
    indxs = zeros(Integer, n)
    for i = 1:n
        ms[i] = bodies[i].m
        indxs[i] = i
    end 
    return (ms, indxs)
end

function obtain_data_for_lennard_jones_interaction(system::WaterSPCFw)
    bodies = system.bodies
    n = length(bodies)
    ms = zeros(Real, 3 * n)
    indxs = zeros(Integer, n)
    for i = 1:n
        indxs[i] = 3 * (i - 1) + 1
        ms[3 * (i - 1) + 1] = system.mO
        ms[3 * (i - 1) + 2] = system.mH
        ms[3 * (i - 1) + 3] = system.mH
    end 
    return (ms, indxs)
end

function obtain_data_for_electrostatic_interaction(system::PotentialNBodySystem)
    bodies = system.bodies
    n = length(bodies)
    qs = zeros(Real, n)
    ms = zeros(Real, n)
    indxs = collect(1:n)
    exclude = Dict{Int, Vector{Int}}()
    for i = 1:n
        qs[i] = bodies[i].q
        ms[i] = bodies[i].m
        exclude[i] = [i]
    end 
    return (qs, ms, indxs, exclude)
end

function obtain_data_for_electrostatic_interaction(system::WaterSPCFw)
    bodies = system.bodies
    n = length(bodies)
    qs = zeros(Real, 3 * n)
    ms = zeros(Real, 3 * n)
    indxs = collect(1:3*n)
    exclude = Dict{Int, Vector{Int}}()
    for i = 1:n
        Oind = 3 * (i - 1) + 1
        qs[Oind] = system.qO
        qs[Oind + 1] = system.qH
        qs[Oind + 2] = system.qH
        ms[Oind] = system.mO
        ms[Oind + 1] = system.mH
        ms[Oind + 2] = system.mH
        exclude[Oind] = [Oind, Oind+1, Oind+2]
        exclude[Oind+1] = [Oind, Oind+1, Oind+2]
        exclude[Oind+2] = [Oind, Oind+1, Oind+2]
    end 
    return (qs, ms, indxs, exclude)
end

function obtain_data_for_electrostatic_interaction(system::NBodySystem)
    bodies = system.bodies
    n = length(bodies)
    qs = zeros(Real, n)
    ms = zeros(Real, n)
    return (qs, ms)
end

function obtain_data_for_valence_angle_harmonic_interaction(system::WaterSPCFw)
    p = system.scpfw_parameters
    bonds = Vector{Tuple{Int, Int, Int, Float64, Float64}}()
    n = length(system.bodies)
    ms = zeros(Real, 3 * n)
    for i = 1:n
        indO, indH1, indH2 = 3 * (i - 1) + 1, 3 * (i - 1) + 2, 3 * (i - 1) + 3
        ms[indO] = system.mO
        ms[indH1] = system.mH
        ms[indH2] = system.mH
        push!(bonds, (indH1, indO, indH2, p.aHOH, p.ka))
    end 
    return (ms, bonds)
end

function DiffEqBase.ODEProblem(simulation::NBodySimulation{<:PotentialNBodySystem})
    (u0, v0, n) = gather_bodies_initial_coordinates(simulation.system)
    
    acceleration_functions = gather_accelerations_for_potentials(simulation)   

    function ode_system!(du, u, p, t)
        du[:, 1:n] = @view u[:, n + 1:2n];

        @inbounds for i = 1:n
            a = MVector(0.0, 0.0, 0.0)
            for acceleration! in acceleration_functions
                acceleration!(a, u[:, 1:n], u[:, n + 1:end], t, i);                
            end
            du[:, n + i] .= a
        end 
    end

    return ODEProblem(ode_system!, hcat(u0, v0), simulation.tspan)
end

function DiffEqBase.SecondOrderODEProblem(simulation::NBodySimulation{<:PotentialNBodySystem})
    
    (u0, v0, n) = gather_bodies_initial_coordinates(simulation.system)

    acceleration_functions = gather_accelerations_for_potentials(simulation)  

    function soode_system!(dv, v, u, p, t)
        @inbounds for i = 1:n
            a = MVector(0.0, 0.0, 0.0)
            for acceleration! in acceleration_functions
                acceleration!(a, u, v, t, i);    
            end
            dv[:, i] .= a
        end 
    end

    SecondOrderODEProblem(soode_system!, v0, u0, simulation.tspan)
end

function DiffEqBase.SecondOrderODEProblem(simulation::NBodySimulation{<:WaterSPCFw})
    
    (u0, v0, n) = gather_bodies_initial_coordinates(simulation.system)

    (o_acelerations, h_acelerations) = gather_accelerations_for_potentials(simulation)
    group_accelerations = gather_group_accelerations(simulation)   

    function soode_system!(dv, v, u, p, t)
        @inbounds for i = 1:n
            a = MVector(0.0, 0.0, 0.0)
            for acceleration! in o_acelerations
                acceleration!(a, u, v, t, 3 * (i - 1) + 1);    
            end
            dv[:, 3 * (i - 1) + 1]  .= a
        end
        @inbounds for i in 1:n, j in (2, 3)
            a = MVector(0.0, 0.0, 0.0)
            for acceleration! in h_acelerations
                acceleration!(a, u, v, t, 3 * (i - 1) + j);    
            end
            dv[:, 3 * (i - 1) + j]   .= a
        end 
        @inbounds for i = 1:n
            for acceleration! in group_accelerations
                acceleration!(dv, u, v, t, i);    
            end
        end
    end

    SecondOrderODEProblem(soode_system!, v0, u0, simulation.tspan)
end

function gather_accelerations_for_potentials(simulation::NBodySimulation{<:WaterSPCFw})
    o_acelerations = []
    h_acelerations = []
    
    push!(o_acelerations, get_accelerating_function(simulation.system.e_parameters, simulation))
    push!(o_acelerations, get_accelerating_function(simulation.system.scpfw_parameters, simulation))
    push!(o_acelerations, get_accelerating_function(simulation.system.lj_parameters, simulation))

    push!(h_acelerations, get_accelerating_function(simulation.system.e_parameters, simulation))
    push!(h_acelerations, get_accelerating_function(simulation.system.scpfw_parameters, simulation))

    (o_acelerations, h_acelerations)
end