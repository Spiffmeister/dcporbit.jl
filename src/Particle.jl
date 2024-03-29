#=
    Particle class and constants
=#
"""
    OrbitMode{T}
Either GuidingCentre or FullOrbit
"""
struct OrbitMode{T} end
const GuidingCentre = OrbitMode{:GuidingCentre}(); GC = GuidingCentre
const FullOrbit = OrbitMode{:FullOrbit}(); FO = FullOrbit



const q = m = 1.

VectorVector    = Union{Vector{Float64},Vector{Vector{Float64}}}
VectorFloat     = Union{Float64,Vector{Float64}}
ArrayFunction   = Union{Array{Function},Function}
# ArrayBool   = Union{Array{Bool},Bool}

"""
    forces

Sets up the equations of motion for a particle simulation.
    
By default uses [`MagneticForce`](@ref): ``\\frac{\\text{d}^2 x}{\\text{d} t^2} =q(v\\times B)``
"""
struct forces
    # Set up the ODEs for the problem
    # Set up the problem
    MagneticField   :: Union{Function,Vector{Function}}
    EOM             :: Function
    EOM_GC          :: Function
    event           :: Union{Function,Nothing}
    # Event function should return the index of the field to choose
    function forces(MagField;force=MagneticForce,event=nothing)
        new(MagField,force,MagneticForce_GC,event)
    end

end

Base.show(io::IO, F::forces) = print("Magnetic force function generated.")


"""
    particle
"""
mutable struct particle{T}
    # Position and time things
    x           :: Array{T} # x y z
    v           :: Array{T} # vx vy vz
    mode        :: OrbitMode # FullOrbit or GuidingCentre mode
    t           :: Array{T} # time
    Δt          :: T # timestep
    # Functions
    B           :: Array{T} # current magnetic field
    lvol        :: Vector{Int} # magnetic field region
    gc_init     :: Bool # was this initialised with guiding centre
    gc          :: Array{T} # gc position

    # Constructor to build easier
    function particle(x::Vector{T},v::Vector{T},mode::OrbitMode,Δt::T,Bfield::Union{Function,Vector{Function}};
            gc_initial=true,lvol::Int=1) where T
        
        # Check the magnetic field type
        if typeof(Bfield) <: Function
            B = Bfield
        elseif typeof(Bfield) <: Vector{Function}
            B = Bfield[lvol]
        end

        x₀ = x
        if gc_initial
            # Convert to FO position
            x = x - guiding_center(v,B(x,T(0)))
        else
            # Store the GC position
            x₀ = x₀ + guiding_center(v,B(x₀,T(0)))
        end
        # Create the particle object
        new{T}(x,v,mode,[0.],Δt,B(x,0),[lvol],gc_initial,x₀)
    end
end


#=  =#
# Base.getindex(p::particle,i) = p.x[:,i], p.v[:,i]
# particle(x::Vector,v::Vector,mode::OrbitMode,Δt::Real,Bfield;gc_initial=true,lvol=1) where {T<:Real} = 
#     particle(x,v,mode,Δt,Bfield,gc_initial,lvol)


Base.show(io::IO, P::particle) = print(io,"Single particle in ",P.mode," mode at x₀=",P.x," and v₀=",P.v)


"""
    sim
"""
struct sim
    # Vector that holds particle
    nparts  :: Int
    sp      :: Vector{particle}

    function sim(nparts::Int,x₀::Vector,v₀::Vector,mode::OrbitMode,Δt::VectorFloat,Bfield,lvol::Union{Int64,Vector{Int64}};gc_initial=true)
        
        if typeof(x₀) == Vector{Float64}
            # Ensure position can be read
            x₀ = [x₀ for i in 1:nparts]
        end
        if typeof(v₀) == Vector{Float64}
            # Ensure velocity can be read
            v₀ = [v₀ for i in 1:nparts]
        end
        if typeof(lvol) == Int64
            # Ensure lvol can be read
            lvol = [lvol for i in 1:nparts]
        end
        if typeof(Δt) == Float64
            Δt = zeros(nparts) .+ Δt
        end

        parts = Array{particle}(undef,nparts)
        for i = 1:nparts
            parts[i] = particle(x₀[i],v₀[i],mode,Δt[i],Bfield,lvol[i],gc_initial=gc_initial)
        end
        new(nparts,parts)
    end
end





#=====
    Particle based fns
=====#
"""
    guiding_center(p::particle)
"""
function guiding_center(p::particle)
    gc = zeros(length(p.t))
    for i = 1:length(p.t)
        gc[i] = guiding_center(p.v[:,i],p.B[i])
    end
    return gc
end
"""
    guiding_center(v::Vector,B::Vector)
"""
function guiding_center(v::Vector,B::Vector)
    return m/q * cross(v,B)/norm(B,2)^2
end
"""
    gyroradius
"""
function gyroradius(v::Vector,B::Vector)
    return m/q * norm(cross(v,B))/norm(B,2)
end
function gyroradius(v_perp::TT,B::Vector{TT}) where TT
    return m/q * v_perp/norm(B,2)
end

#====
    EQUATIONS OF MOTION
====#
"""
    MagneticForce_GC(xv::Vector{Float64},t::Float64,B::Array)
"""
function MagneticForce_GC(xv::Vector{Float64},t::Float64,B::Array)
    x = xv[1:3]
    v = xv[4:6]
    v = dot(v,B(x,t))/norm(B,2)^2 * B
    dvdt = zeros(3)
    xv = vcat(v,dvdt)
    return xv
end
"""
    MagneticForce(xv::Vector{Float64},t::Float64,B::Vector)
"""
function MagneticForce(xv::Vector{Float64},t::Float64,B::Vector)
    x = xv[1:3]
    v = xv[4:6]
    dvdt = q/m*cross(v,B)
    xv = vcat(v,dvdt)
    return xv
end


"""
    MagneticForce_GC!(xv::Vector,B::Array)
"""
function MagneticForce_GC!(xv::Vector,B::Array)
    xv[1:3] .= dot(xv,B)/norm(B,2)^2 * B
    xv[4:6] .= 0.0
    xv
end
"""
    MagneticForce!(xv::Vector,B::Vector)
"""
function MagneticForce!(xv::Vector,B::Vector)
    xv[1:3] .= q/m*cross(v,B)
    xv[4:6] .= 0.0
    xv
end



"""
    MagneticForce_Hamiltonian(qp::Vector{Float64},t::Float64,A::Function)
"""
function MagneticForce_Hamiltonian(qp::Vector{Float64},t::Float64,A::Function)
end