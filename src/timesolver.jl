#=
    ORBIT SOLVER
=#
"""
    solve_orbit!(p::particle,ODE,t_f;method=:RK4,sample_factor=1)
Takes a particle object and evolves it in time
"""
function solve_orbit!(p::particle,ODE,t_f;method=:RK4,sample_factor=1)
    # Used as an iterator this will update the particle object provided

    # Set the integrator
    if method==:RK4
        integrator = RK4
    elseif method==:forward_eulers
        integrator = forward_eulers
    end
    
    # Set up event location related things
    typeof(ODE.event) <: Nothing ? discontinuity_present = false : discontinuity_present = true
    
    # Initial xv to be handed to integrator
    xv = vcat(p.x[:,1], p.v[:,1])
    
    # Set up the equations of motion
    Btype = typeof(ODE.MagneticField)
    if Btype <: Vector{Function}
        B = ODE.MagneticField[p.lvol[1]]
    else
        B = ODE.MagneticField
    end
    # fₓ(x,t) = ODE.EOM(x,t,B(x,t))

    sample = 0

    # Main time loop
    while p.t[end] < t_f
        tᵢ = [p.t[end], p.t[end]+p.Δt]
        
        # Integrate
        xv, t, Δt_tmp, k = integrator((x,t) -> ODE.EOM(x,t,B(x,t)),xv[:,end],tᵢ)
        
        if discontinuity_present
            # If the field is discontinuous (or if an event is being tracked)
            event_info = ODE.event(xv[:,1],xv[:,2])
            if (event_info == 0)
                # if the particle sat on the interface we need to check the previous state
                # if this tells us we crossed we should ignore the event call and continue
                # this avoids the particle landing on the boundary and reporting a new crossing
                event_info = ODE.event(vcat(p.x[:,end-1],p.v[:,end-1]),xv[:,2])
                event_info == -1 ? event_info = 1 : nothing
            elseif (event_info == -1)
                # if the particle switched region check it didn't just change volumes (temporary fix)
                # (fill fix requires change to data structure)
                # println("chattering ",event_info," ",p.x[3,end-1]," ",xv[3,1]," ",xv[3,2]," ",p.lvol[end-1]," ",p.lvol[end])
                p.lvol[end-1] != p.lvol[end] ? event_info = 1 : nothing 
            end
            if event_info == 1
                # If the particle does not cross
                # if mod(t[end],sample_factor*p.Δt) == 0
                p = storage(p,xv,t,B)
                # end
            else
                # println(event_info)
                # If the particle does cross
                # println("crossing")
                # println("t=",t[end]," ",xv[3,:]," lvol=",p.lvol[end])
                t, Δt, xv[:,2] = event_loc((x,t) -> ODE.EOM(x,t,B(x,t)),xv,k,Δt_tmp,t)
                p.lvol[end] == 1 ? lvol = 2 : lvol = 1
                # lvol = event_info
                p = storage(p,xv,t,B,lvol=lvol)
                B = ODE.MagneticField[lvol] #Update the field
                # println("t=",t[end]," ",xv[3,:]," lvol=",p.lvol[end])
                # fₓ(x,v,t) = ODE.EOM(x,t,B(x,v,t)) #Update forces
            end
        else
            # If the field is continuous
            # if mod(sample,sample_factor) == 0
                p = storage(p,xv,t,B)
            # end
            Δt = Δt_tmp
        end
        sample += 1
    end
    return p
end


"""
    storage(p::particle,xv,t,B;lvol=nothing)
"""
function storage(p::particle,xv,t,B;lvol=nothing)
    # Particle storage function, called whenever event triggered or sample_factor is
    p.x = hcat(p.x,xv[1:3,2])
    p.v = hcat(p.v,xv[4:6,2])
    p.t = vcat(p.t,t[2])
    p.B = hcat(p.B,B(xv[1:3,2],t[2]))
    p.gc = hcat(p.gc,xv[1:3,2]+guiding_center(xv[4:6,2],B(xv[1:3,2],t[2])))
    if lvol == nothing
        append!(p.lvol,p.lvol[end])
        return p
    else
        append!(p.lvol,lvol)
        return p
    end
end

"""
    run_sim!(f::sim,ODE,t_f;method=:RK4)
"""
function run_sim!(f::sim,ODE,t_f;method=:RK4)
    # INTERFACE FOR solving simulations
    for i = 1:f.nparts
        solve_orbit!(f.sp[i],ODE,t_f,method=method)
    end
    # return f
end

"""
    integrate!(ODE::Function,xv::Vector{Float64},t;eventfn=nothing,method=:RK4)
"""
function integrate!(ODE::Function,xv::Vector{Float64},t;eventfn=nothing,method=:RK4)
    # CURRENTLY NOT USED
    if method==:RK4
        integrator = RK4
    end

    # Turn event location on/off
    typeof(eventfn) <: Nothing ? dchk = false : dchk = true

    while i < m
        x, t, h, crossing = integrator(ODE,xv,t)

        if dchk
            event = eventfn(x[:,i:i+1])
            if event[1]
                t, h, xn = event_loc(fₓ,x[:,i:i+1],k,h,t)
                t[i+1] = t[i] + h
                x[:,i+1] = xn
                crossing = true
            elseif event == 0
                crossing = true
            end
        end
    end

    return x, t, Δt, crossing
end


#== INTEGRATORS ==#

"""
    eulers(fₓ::Function,x₀::Vector{T},t::Vector{T})
"""
function forward_eulers(fₓ::Function,x₀::Vector{T},t::Vector{T}) where T
    n = length(x₀)
    m = length(t)
    x = zeros(n,m)
    h = t[2]-t[1]

    x[:,1] = x₀
    
    i = 1
    while i < m
        x[:,i+1] = x[:,i] + h*fₓ(x[:,i],t[i])
        h = t[i+1] - t[i]
        i += 1
    end
    return x, t, h, 0.0
end


"""
    RK4(fₓ::Function,x₀::Vector{Float64},t::Vector{Float64})
Pushes the solution 1 time step using 4th order Runge-Kutta scheme
"""
function RK4(fₓ::Function,x₀::Vector{Float64},t::Vector{Float64})
    # Standard RK4

    s = 4 #Stages

    n = length(x₀)
    m = length(t)
    x = zeros(n,m)
    k = zeros(n,s)
    h = t[2] - t[1]
    x[:,1] = x₀

    aᵢⱼ = [[1/2.] , [0. , 1/2.] , [0. , 0. , 1.]]
    bᵢ = [1/6., 1/3., 1/3., 1/6.]
    cᵢ = [1/2., 1/2., 1.]

    i = 1

    while i < m
        # Integrate
        k[:,1] = fₓ(x[:,i],t[i])
        for j = 1:(s-1)
            k[:,j+1] = fₓ(x[:,i]+h*k[:,1:j]*aᵢⱼ[j],t[i]+h*cᵢ[j])
        end
        x[:,i+1] = x[:,i] + h*k*bᵢ
        h = t[i+1] - t[i]
        i += 1
    end
    return x, t, h, k
end


"""
    symplectic_euler(H::Function,x₀::Vector{Float64},t::Vector{Float64})
"""
function symplectic_euler(H::Function,x₀::Vector{Float64},t::Vector{Float64})
    # Implicit eulers function.

    n = length(x₀)
    m = length(t)
    x = zeros(n,m)
end