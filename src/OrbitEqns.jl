#===
    Full orbit and gyrocenter equations
===#


#===
    METHODS FOR SOLVING PARTICLES
===#
function analytic_solve(p::particle,Bfield;crossing=true,eventfn=nothing)
    # Method for taking in a particle and returning the analytic solve
    x₀ = p.x[:,1]
    v₀ = p.v[:,1]
    t = p.t
    lvol = p.lvol[1]
    crossing != diff(p.lvol .== 0)
    # Compute the analytic solution based on the simulation
    pe = analytic_solve(p.x₀,v₀,t,Bfield,crossing=crossing,eventfn=eventfn,lvol=lvol)
    return pe
end

function analytic_solve(simulation::sim,Bfield;crossing=true,eventfn=nothing,gc_init=true)
    # Method for taking in a simulation
    asym = analytic_sim(simulation.nparts)
    # Loop over simulations and compute analytic simulations
    for i = 1:simulation.nparts
        x₀ = simulation.sp[i].x₀
        v₀ = simulation.sp[i].v[:,1]
        t = simulation.sp[i].t
        lvol = simulation.sp[i].lvol[1]
        # Check if there are crossings
        crossing != diff(simulation.sp[i].lvol .== 0)

        asym.sp[i] = analytic_solve(x₀,v₀,t,Bfield,crossing=crossing,eventfn=eventfn,lvol=1)
    end
    return asym
end

#===
    ANALYTIC SOLUTIONS FOR ORBITS
===#
function analytic_solve(x₀::Vector{Float64},v₀::Vector{Float64},t::Vector{Float64},Bfield::Union{Function,Array{Function}};crossing=true,eventfn=nothing,lvol=1::Int64)
    # Works for static fields
    if typeof(Bfield) <: Function
        Bf = Bfield
    elseif typeof(Bfield) <: Array
        Bf = Bfield[lvol]
    end

    ω = abs(q)/m * norm(Bf(x₀))
    x = x_b = x₀ - guiding_center(x₀,v₀,Bf)
    v = v_b = v₀

    # Crossing time
    τ_b = Vector{Float64}(undef,0)

    if !crossing
        # If there are no crossings then solve the entire system at once
        B = Bf(x₀)
        b = magcoords(v₀,B)
        x = exact_x(v₀,x₀,b,t,ω)
        v = exact_v(v₀,b,t,ω)
    end
    
    while crossing
        # If there are crossings solve per region
        B = Bfield[lvol](x_b[:,end])
        b = magcoords(v₀,B)
        ω = abs(q)/m * norm(B)
        τ = bound_time(ω,b) #Compute crossing time
        println("yes")
        println(lvol)
        if τ != 0 & (τ < t[end])
            # If crossing time found store it
            append!(τ_b,τ)
            #Get all values of t in this section
            tᵢ = findall(x->sum(τ_b[1:end-1])<=x<=sum(τ_b),t)
            t_f = t[tᵢ[end]] #For exit condition
            # zero the crossing time
            tᵢ = t[tᵢ] .- sum(τ_b[1:end-1])
            # Eqns of motion
            xᵢ = exact_x(v₀,x₀,b,tᵢ,ω)
            vᵢ = exact_v(v₀,b,tᵢ,ω)
            # Positions at boundary
            x_b = hcat(x_b,exact_x(v₀,x₀,b,τ,ω))
            v_b = hcat(v_b,exact_v(v₀,b,τ,ω))
            # Store positions for returning
            x = hcat(x,xᵢ,x_b[:,end])
            v = hcat(x,vᵢ,v_b[:,end])
            # Update the field to use
            lvol = lvol + Int(sign(v_b[3,end]))
        else
            # If crossing time cannot be computed then iterate
            if length(τ_b) == 0
                tᵢ = t
            else
                # If happens after a crossing zero the time
                tᵢ = t - τ_b
                tᵢ = tᵢ[tᵢ .<= 0]
            end
            i = 2
            while (t[i] < t[end])
                # Loop over timesteps until boundary crossing
                x = hcat(x,exact_x(v₀,x₀,b,tᵢ[i],ω))
                v = hcat(v,exact_v(v₀,b,tᵢ[i],ω))
                chk = eventfn(x[:,end-1:end])
                if chk < 0.
                    # If crossing detected comput the exact position
                    ex(t) = exact_x(v₀,x₀,b,t,ω)[3]
                    τ = find_zero(ex,(tᵢ[i-1],tᵢ[i+1]),Bisection(),atol=1.e-15)
                    x_b = hcat(x_b,exact_x(v₀,x₀,b,τ,ω))
                    v_b = hcat(v_b,exact_v(v₀,b,τ,ω))
                    x = hcat(x,x_b[:,end])
                    v = hcat(v,v_b[:,end])
                    append!(τ_b,τ)
                    lvol = lvol + Int(sign(v_b[3,end]))
                    t_f = τ #For exit condition
                    break
                end
                i += 1
            end
        end
        # Set all params for next phase
        v₀ = v_b[:,end]
        println(x_b[:,end])
        println(v₀)
        x₀ = gc(x_b[:,end],v₀,Bfield[lvol](x_b[:,end]))
        if t_f >= t[end]
            # If finished
            break
        end

    end
    return exact_particle(x,v,x_b,v_b,t,τ_b)
end

#===
    Supporting functions
===#
function exact_x(v₀,X₀,b,tᵢ,ω) #position
    x = v_para(v₀,b)*tᵢ' + 1/ω * norm(v₀)*(-b[3] * sin.(ω*tᵢ)' + b[2] * cos.(ω*tᵢ)') .+ X₀
    return x
end
function exact_v(v₀,b,tᵢ,ω)
    v = v_para(v₀,b) .- norm(v₀)*(b[3] * cos.(ω*tᵢ)' + b[2] * sin.(ω*tᵢ)')
    return v
end
function v_para(v₀,b) #parallel velocity
    return dot(v₀,b[1])*b[1]
end
function gc(x₀,v₀,B) #GC position
    return x₀ + cross(v₀,B)/norm(B,2)^2
end

### Functions for computing the average drift ###
function x_bar(v₀,b,τ)
    # ONLY WORKS SINCE ω=1
    x_bar = dot(v₀,b[1])*b[1]*τ + 2*dot(v₀,[0,0,1])*cross([0,0,1],b[1])
    return x_bar
end

function average_orbit(x_bp,x_bm,τ_p,τ_m)
    # Adds the average drift to the original position for adding to plots
    x_bar = (x_bp + x_bm)/(τ_p + τ_m)
    return x_bar
end

function magcoords(v,B)
    # Compute the field aligned coordinates
    B_0     = norm(B,2)
    b1      = B/B_0
    b2      = cross(b1,v)/norm(v,2)
    b3      = cross(b1,b2)
    return [b1,b2,b3]
end

function bound_time(ω,b)
    # Compute the boundary crossing time
    τ = 2/ω * acot(-b[2][3]/b[3][3])
    if τ < 0
        τ += 2*pi
    end
    return τ
end

