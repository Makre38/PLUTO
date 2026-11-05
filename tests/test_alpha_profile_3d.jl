using Test, Printf
include(joinpath(@__DIR__, "..", "plot_alpha_profile_3d.jl"))
const AP = AlphaProfile3D

# Count actual reads rather than infer efficiency from the output shape.
mutable struct CountingIO <: IO
    io::IOBuffer
    reads::Vector{Tuple{Int,Int}}
end
Base.seek(io::CountingIO, pos::Integer) = (seek(io.io, pos); io)
function Base.read!(io::CountingIO, words::Vector{UInt64})
    push!(io.reads, (position(io.io), 8*length(words)))
    return read!(io.io, words)
end

function fixture(dir; yp=0.25, zp=-0.4)
    out = joinpath(dir, "export")
    mkpath(out)
    write(joinpath(dir, "run_summary.txt"),
          "dimension = 3\nrho0 = 2\ncs0 = 2\nrbhl = 2\nx1p = 0.7\nx2p = $yp\nx3p = $zp\noutput_subdir = export\n")
    write(joinpath(out, "grid.out"),
          "4\n1 -3 -1\n2 -1 0\n3 0 2\n4 2 6\n2\n1 -2 0\n2 0 4\n2\n1 -3 -1\n2 -1 3\n")
    write(joinpath(out, "dbl.out"),
          "0 0 0.1 0 single_file little vx1 rho prs\n1 1 0.1 10 single_file little vx1 rho prs\n2 4 0.1 40 single_file big vx1 rho prs\n")
    x, y, z = [-2.0, -0.5, 1.0, 4.0], [-1.0, 2.0], [-2.0, 1.0]
    field = [2*(1 + 0.03*a + 0.05*b + 0.04*c + 0.01*b*c) for a in x, b in y, c in z]
    for (idx, rho, convert) in ((0, fill(2.0, size(field)), htol),
                                (1, field, htol), (2, 2 .* field, hton))
        # Non-density fields are deliberately invalid, and rho is not first.
        words = convert.(reinterpret(UInt64, [fill(NaN, length(field)); vec(rho); fill(Inf, length(field))]))
        write(joinpath(out, @sprintf("data.%04d.dbl", idx)), words)
    end
    return (; out, x, y, z, field)
end

@testset "Transverse geometry and time selection" begin
    @test AP.transverse_weights([-1.0, 1.0], 0.0) == [(1, 0.5), (2, 0.5)]
    @test AP.transverse_weights([-2.0, 0.0, 3.0], 0.0) == [(2, 1.0)]
    @test AP.transverse_weights([-2.0, 0.0, 3.0], 3.0) == [(3, 1.0)]
    @test AP.transverse_weights([-1.0, 3.0], 0.0) == [(1, 0.75), (2, 0.25)]
    for (coords, pos) in (([-1.0, 1.0], 2.0), ([1.0, -1.0], 0.0),
                          ([0.0, 0.0], 0.0), ([NaN, 1.0], 0.0), ([-1.0, 1.0], Inf))
        @test_throws ErrorException AP.transverse_weights(coords, pos)
    end
    # Nearest in log time differs from nearest in linear time here.
    metas = [(index=i, time=t) for (i,t) in enumerate([0.0, NaN, 1.0, 100.0])]
    @test AP.select_snapshot(metas, log(20.0), 1.0, 1.0).time == 100.0
    @test AP.select_snapshot(metas, -50.0, 1.0, 1.0).time == 1.0
    @test AP.select_snapshot(metas, log(20.0)+log(2.0), 2.0, 1.0).time == 100.0
    @test_throws ErrorException AP.select_snapshot(metas[1:2], 0.0, 1.0, 1.0)
    @test_throws ErrorException AP.select_snapshot(metas, Inf, 1.0, 1.0)
    @test AP.parse_cli(["case", "-2", "--output=a.png"]).target == -2
    @test_throws ErrorException AP.parse_cli(["case", "0", "--output", "data.dbl"])
    @test_throws ErrorException AP.parse_cli(["case", "NaN"])
    @test_throws ErrorException AP.parse_cli(["case", "0", "--axis", "y"])
end

@testset "Partial reads and signed density interpolation" begin
    mktempdir() do dir
        f = fixture(dir)
        expected = [0.03*x + 0.05*0.25 + 0.04*(-0.4) + 0.01*0.25*(-0.4) for x in f.x]
        p = AP.load_profile(dir, 0.05)
        @test p.meta.index == 1
        @test p.actual == 0
        @test p.target == 0.05
        @test p.alpha ≈ expected atol=1e-15
        @test p.x == f.x
        @test p.xp == 0.7
        @test first(p.alpha) < 0 < last(p.alpha)
        pbig = AP.load_profile(dir, 1.3)
        @test pbig.meta.index == 2
        @test pbig.alpha ≈ 2 .* (expected .+ 1) .- 1 atol=1e-15
        metas = AP.read_snapshots(joinpath(f.out, "dbl.out"))
        # Symmetric transverse grid: four-row average.
        bytes = read(joinpath(f.out, "data.0001.dbl"))
        io = CountingIO(IOBuffer(bytes), Tuple{Int,Int}[])
        rho = AP.sample_axis(io, metas[2], (4,2,2), [(1,0.5),(2,0.5)], [(1,0.5),(2,0.5)])
        expected_average = [sum(f.field[i,:,:])/4 for i in 1:4]
        @test rho ≈ expected_average
        @test sort(io.reads) == [(128,32), (160,32), (192,32), (224,32)]
        io = CountingIO(IOBuffer(bytes), Tuple{Int,Int}[])
        exact = AP.sample_axis(io, metas[2], (4,2,2), [(2,1.0)], [(1,1.0)])
        @test exact == f.field[:,2,1]
        @test io.reads == [(160,32)]
        # Uniform-density and vacuum limits preserve zero and negative alpha.
        uniform = AP.sample_axis(IOBuffer(read(joinpath(f.out, "data.0000.dbl"))),
                                 metas[1], (4,2,2), [(1,0.5),(2,0.5)], [(1,0.5),(2,0.5)])
        @test uniform ./ 2 .- 1 == zeros(4)
        zeros_io = IOBuffer(zeros(UInt8, 3*16*8))
        @test AP.sample_axis(zeros_io, metas[2], (4,2,2), [(1,1.0)], [(1,1.0)]) ./ 2 .- 1 == fill(-1.0,4)

        table = joinpath(dir, "profile.dat")
        AP.write_table(table, p; run_dir=dir)
        rows = [parse.(Float64, split(l)) for l in eachline(table) if !startswith(l, "#")]
        @test getindex.(rows, 1) == f.x
        @test getindex.(rows, 2) == f.x .- 0.7
        @test getindex.(rows, 3) == p.rho
        @test getindex.(rows, 4) == p.alpha
        @test occursin("requested_log_lambda = 0.05", read(table, String))
        @test occursin("y_samples", read(table, String))
        @test !isdefined(AP, :Plots) # numeric path has no plotting dependency
        @test_throws ErrorException AP.sample_axis(IOBuffer(bytes), merge(metas[2], (; mode="multiple_files")), (4,2,2), [(1,1.0)], [(1,1.0)])
        @test_throws ErrorException AP.sample_axis(IOBuffer(bytes), merge(metas[2], (; vars=["vx1","prs","vx2"])), (4,2,2), [(1,1.0)], [(1,1.0)])
        @test_throws ErrorException AP.sample_axis(IOBuffer(bytes), merge(metas[2], (; endian="unknown")), (4,2,2), [(1,1.0)], [(1,1.0)])
        for bad in (NaN, Inf, -1.0)
            badbytes = copy(bytes)
            badbytes[129:136] = reinterpret(UInt8, [htol(reinterpret(UInt64, bad))])
            @test_throws ErrorException AP.sample_axis(IOBuffer(badbytes), metas[2], (4,2,2), [(1,1.0)], [(1,1.0)])
        end
        open(joinpath(f.out, "data.0001.dbl"), "a") do io
            write(io, UInt8(0))
        end
        @test_throws ErrorException AP.load_profile(dir, 0.0)
    end
    mktempdir() do dir
        fixture(dir; yp=2.0, zp=-2.0)
        p = AP.load_profile(dir, 0.0)
        @test length(p.y_samples) == length(p.z_samples) == 1
        @test p.alpha ≈ [0.03*x + 0.05*2 - 0.04*2 - 0.01*4 for x in p.x] atol=1e-15
        fixture(dir; yp=10.0)
        @test_throws ErrorException AP.load_profile(dir, 0.0)
        fixture(dir)
        write(joinpath(dir, "run_summary.txt"), replace(read(joinpath(dir,"run_summary.txt"), String), "rho0 = 2" => "rho0 = 0"))
        @test_throws ErrorException AP.load_profile(dir, 0.0)
    end
end

# Optional end-to-end PNG check; use in a Julia environment with Plots installed.
if "--plot" in ARGS
    @testset "PNG CLI" begin
        mktempdir() do dir
            fixture(dir)
            output = joinpath(dir, "figure.png")
            script = joinpath(@__DIR__, "..", "plot_alpha_profile_3d.jl")
            run(`$(Base.julia_cmd()) --startup-file=no $script $dir 0.05 --output $output`)
            @test read(output)[1:8] == UInt8[0x89,0x50,0x4e,0x47,0x0d,0x0a,0x1a,0x0a]
            @test isfile(joinpath(dir, "figure.dat"))
        end
    end
end
