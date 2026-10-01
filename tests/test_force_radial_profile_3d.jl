using Test, Random, Printf
include(joinpath(@__DIR__, "..", "force_radial_profile_3d.jl"))
const RP = ForceRadialProfile3D

function read_table(path)
    rows = [parse.(Float64, split(line)) for line in eachline(path)
            if !isempty(strip(line)) && !startswith(line, "#")]
    return permutedims(hcat(rows...))
end

# Independent direct integration for each cutoff, deliberately not binned.
function brute_force(rho, centers, widths, cuts; mp, rho0, rsoft, origin)
    result = zeros(length(cuts), 6)
    for (n, cut) in enumerate(cuts), cell in CartesianIndices(rho)
        v = [centers[a][cell[a]] - origin[a] for a in 1:3]
        r = sqrt(sum(v.^2))
        r > cut || continue
        dm = (rho[cell] - rho0) * prod(widths[a][cell[a]] for a in 1:3)
        for a in 1:3
            result[n,a] += mp*dm*v[a]/r^3
            result[n,a+3] += mp*dm*v[a]/(r^2 + rsoft^2)^1.5
        end
    end
    result
end

@testset "Radial kernels and shell sums" begin
    centers = [[-2.0, -0.5, 0.0, 0.5, 2.0], [-0.5, 0.0, 0.5], [-1.0, 0.0, 1.0]]
    widths = [[0.4, 0.2, 0.1, 0.2, 0.4], [0.4, 0.1, 0.4], [0.8, 0.2, 0.8]]
    cuts = [0.0, 0.5, 1.0, 1.5, 2.0, 3.0]
    kwargs = (mp=1.2, rho0=1.0, rsoft=0.7, origin=(0.0, 0.0, 0.0))
    rho = ones(5, 3, 3)
    profile = RP.radial_profile(rho, centers, widths, cuts; kwargs...)
    @test all(iszero, profile.cumulative)
    @test all(iszero, profile.shell)

    # Analytic single-cell force at +x and strict exclusion of a cell on r_cut.
    rho[5,2,2] = 2
    p = RP.radial_profile(rho, centers, widths, cuts; kwargs...)
    dm = 0.4*0.1*0.2
    @test p.cumulative[1,1] ≈ 1.2*dm/4
    @test p.cumulative[1,4] ≈ 1.2*dm*2/(4 + 0.7^2)^1.5
    @test 0 < p.cumulative[1,4] < p.cumulative[1,1]
    @test all(iszero, p.cumulative[:,[2,3,5,6]])
    @test all(iszero, p.cumulative[5:end,:])
    rho[1,2,2] = 2
    @test all(iszero, RP.radial_profile(rho, centers, widths, cuts; kwargs...).cumulative)
    rho[5,2,2] = 1
    @test RP.radial_profile(rho, centers, widths, cuts; kwargs...).cumulative[1,1] < 0

    Random.seed!(42)
    rho .= 0.5 .+ rand(size(rho)...)
    for origin in ((0.0, 0.0, 0.0), (0.15, -0.2, 0.4)), rsoft in (0.02, 1.0, 10.0)
        args = merge(kwargs, (; origin, rsoft))
        p = RP.radial_profile(rho, centers, widths, cuts; args...)
        @test p.cumulative ≈ brute_force(rho, centers, widths, cuts; args...) atol=1e-14
        for i in eachindex(cuts)
            @test p.cumulative[i,:] ≈ vec(sum(p.shell[i:end,:]; dims=1)) atol=1e-14
        end
    end
    @test_throws ErrorException RP.validate_cuts([0.0, 0.0])
    @test_throws ErrorException RP.validate_cuts([1.0, 0.5])
    @test_throws ErrorException RP.validate_cuts([-1.0])
    @test_throws ErrorException RP.validate_cuts([Inf])
    @test_throws ErrorException RP.parse_cli(["run", "--bins", "2", "--r-cuts", "0,1"])
    @test_throws ErrorException RP.parse_cli(["run", "1", "--snapshot", "0"])
end

@testset "PLUTO input and radial table output" begin
    mktempdir() do dir
        out = joinpath(dir, "export")
        mkdir(out)
        write(joinpath(dir, "run_summary.txt"), "dimension = 3\nmp = 1\ncs0 = 1\nrho0 = 1\nrbhl = 0.8\nrsoft = 0.5\nmach = 0.5\nx1p = 0\nx2p = 0\nx3p = 0\nlog_lambda_max = 0\n")
        write(joinpath(out, "grid.out"), "# synthetic grid\n2\n1 -2.5 -1.5\n2 1.5 2.5\n2\n1 -1 0\n2 0 1\n2\n1 -1 0\n2 0 1\n")
        write(joinpath(out, "dbl.out"), "0 0 0.1 0 single_file little vx1 rho\n1 0.8 0.1 8 single_file big vx1 rho\n")
        rho = ones(2,2,2)
        rho[2,2,2] = 2
        data = [fill(9.0, 8); vec(rho)]  # density is not the first field
        for (idx, convert) in ((0, htol), (1, hton))
            write(joinpath(out, @sprintf("data.%04d.dbl", idx)), convert.(reinterpret(UInt64, data)))
        end
        p0 = RP.main([dir, "--snapshot", "0", "--r-cuts", "0,0.8,3"])
        p1 = RP.main([dir, "0", "--r-cuts", "0,0.8,3"])
        @test p0.cumulative == p1.cumulative
        table = read_table(joinpath(dir, "force_radial_profile_3d.0001.dat"))
        @test size(table) == (3, 17)
        @test table[:,1] == [0, 0.8, 3]
        @test table[:,2] == table[:,1]  # r_B = 1
        @test table[:,3] ≈ table[:,1]/0.8
        @test table[:,4] == table[:,1]/0.5
        @test table[:,6:11] == p1.cumulative
        @test table[:,12:17] == p1.shell
        # Compare the point kernel with the unchanged one-case CLI at r_cut=rbhl.
        old_script = joinpath(@__DIR__, "..", "force_from_run.jl")
        output = read(`$(Base.julia_cmd()) --startup-file=no $old_script $dir 0`, String)
        fx = parse(Float64, match(r"^Fx = (\S+)"m, output).captures[1])
        @test fx ≈ p1.cumulative[2,1] rtol=1e-11
        @test_throws ErrorException RP.main([dir, "--snapshot", "9"])
        @test length(RP.main([dir, "--snapshot", "0", "--bins", "4"]).cuts) == 5
        # Exercise the real new CLI entry point, not just the callable module.
        new_script = joinpath(@__DIR__, "..", "force_radial_profile_3d.jl")
        cli_output = joinpath(dir, "cli.dat")
        run(`$(Base.julia_cmd()) --startup-file=no $new_script $dir --snapshot 1 --r-cuts 0,0.8,3 --output $cli_output`)
        @test read_table(cli_output) == table
    end
end
