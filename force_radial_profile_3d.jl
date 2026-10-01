module ForceRadialProfile3D

using Printf

const USAGE = "julia force_radial_profile_3d.jl RUN_DIR [TARGET_LOG_LAMBDA] [--snapshot INDEX] [--bins N | --r-cuts R0,R1,...] [--output PATH]"

function read_summary(path)
    result = Dict{String,String}()
    for line in eachline(path)
        s = strip(line)
        (startswith(s, "#") || !occursin('=', s)) && continue
        key, value = split(s, '='; limit=2)
        result[strip(key)] = strip(value)
    end
    return result
end

function read_grid(path)
    lines = filter(s -> !isempty(s) && !startswith(s, "#"), strip.(readlines(path)))
    pos = 1
    centers, widths = Vector{Float64}[], Vector{Float64}[]
    for _ in 1:3
        n = parse(Int, lines[pos])
        n > 0 || error("Grid dimensions must be positive")
        pos += 1
        coords, spacing = Float64[], Float64[]
        for _ in 1:n
            cols = split(lines[pos])
            lo, hi = parse(Float64, cols[2]), parse(Float64, cols[3])
            isfinite(lo) && isfinite(hi) && hi > lo || error("Invalid grid cell")
            push!(coords, (lo + hi) / 2)
            push!(spacing, hi - lo)
            pos += 1
        end
        push!(centers, coords)
        push!(widths, spacing)
    end
    return centers, widths
end

function read_snapshots(path)
    result = NamedTuple[]
    for line in eachline(path)
        s = strip(line)
        (isempty(s) || startswith(s, "#")) && continue
        cols = split(s)
        length(cols) >= 7 || error("Malformed dbl.out entry: $s")
        push!(result, (index=parse(Int, cols[1]), time=parse(Float64, cols[2]),
                       mode=cols[5], endian=cols[6], vars=cols[7:end]))
    end
    isempty(result) && error("No snapshots in $path")
    return result
end

function read_density(path, meta, dims)
    meta.mode == "single_file" || error("Only PLUTO single_file double output is supported")
    meta.endian in ("little", "big") || error("Unknown byte order: $(meta.endian)")
    var_index = findfirst(==("rho"), meta.vars)
    var_index === nothing && error("Snapshot does not contain rho")
    ncell = prod(dims)
    filesize(path) == 8 * ncell * length(meta.vars) || error("Snapshot size does not match metadata/grid")
    words = Vector{UInt64}(undef, ncell)
    open(path, "r") do io
        seek(io, 8 * ncell * (var_index - 1))
        read!(io, words)
    end
    words .= meta.endian == "little" ? ltoh.(words) : ntoh.(words)
    return reshape(copy(reinterpret(Float64, words)), dims)
end

function positive(name, value)
    isfinite(value) && value > 0 || error("$name must be finite and positive")
    return value
end

function validate_cuts(cuts)
    !isempty(cuts) && all(r -> isfinite(r) && r >= 0, cuts) ||
        error("r-cuts must be finite, nonnegative, and nonempty")
    all(>(0), diff(cuts)) || error("r-cuts must be strictly increasing")
    return cuts
end

"""
Bin each cell once, then accumulate from outside inward: O(Ncell log Ncut + Ncut).
Row i contains F(r > cuts[i]); shell i covers cuts[i] < r <= cuts[i+1].
The last shell includes all remaining cells in the finite domain. Coordinates
are relative to the perturber; delta_rho = rho-rho0, and forces act on it.
"""
function radial_profile(rho, centers, widths, cuts; mp, rho0, rsoft, origin=(0.0, 0.0, 0.0))
    validate_cuts(cuts)
    positive("mp", mp)
    positive("rho0", rho0)
    positive("rsoft", rsoft)
    length(centers) == length(widths) == length(origin) == 3 || error("Expected three axes")
    all(isfinite, origin) || error("Perturber coordinates must be finite")
    for axis in 1:3
        length(centers[axis]) == length(widths[axis]) == size(rho, axis) || error("Grid/data shape mismatch")
        all(isfinite, centers[axis]) || error("Nonfinite grid coordinates")
        all(w -> isfinite(w) && w > 0, widths[axis]) || error("Invalid cell widths")
    end
    # Columns: Fx_point, Fy_point, Fz_point, Fx_soft, Fy_soft, Fz_soft.
    shell = zeros(length(cuts), 6)
    x, y, z = centers
    dx, dy, dz = widths
    for k in eachindex(z), j in eachindex(y), i in eachindex(x)
        isfinite(rho[i,j,k]) || error("Nonfinite density at cell ($i, $j, $k)")
        rx, ry, rz = x[i]-origin[1], y[j]-origin[2], z[k]-origin[3]
        r = hypot(rx, ry, rz)
        # At the exact center the point kernel is undefined; exclude it, as
        # in existing analysis. Its softened vector contribution is zero.
        r == 0 && continue
        # searchsortedfirst implements strict r > r_cut, including exact edges.
        bin = searchsortedfirst(cuts, r) - 1
        bin == 0 && continue
        mass_factor = mp * (rho[i,j,k]-rho0) * dx[i] * dy[j] * dz[k]
        point = mass_factor / r^3
        soft = mass_factor / hypot(r, rsoft)^3
        for (axis, coord) in enumerate((rx, ry, rz))
            shell[bin, axis] += point * coord
            shell[bin, axis+3] += soft * coord
        end
    end
    cumulative = copy(shell)
    for i in (length(cuts)-1):-1:1
        cumulative[i,:] .+= cumulative[i+1,:]
    end
    return (cuts=cuts, cumulative=cumulative, shell=shell)
end

function parse_cli(args)
    isempty(args) && error(USAGE)
    run_dir = abspath(args[1])
    target, snapshot, cuts, output = nothing, nothing, nothing, nothing
    bins = 64
    bins_explicit = false
    i = 2
    while i <= length(args)
        arg = args[i]
        if arg in ("--snapshot", "--bins", "--r-cuts", "--output")
            i < length(args) || error("Missing value after $arg")
            value = args[i+1]
            if arg == "--snapshot"
                snapshot = parse(Int, value)
                snapshot >= 0 || error("snapshot must be nonnegative")
            elseif arg == "--bins"
                bins = parse(Int, value)
                bins > 0 || error("bins must be positive")
                bins_explicit = true
            elseif arg == "--r-cuts"
                cuts = validate_cuts(parse.(Float64, split(value, ',')))
            else
                output = abspath(value)
            end
            i += 2
        elseif startswith(arg, "--")
            error("Unknown option: $arg")
        elseif target === nothing
            target = parse(Float64, arg)
            isfinite(target) || error("TARGET_LOG_LAMBDA must be finite")
            i += 1
        else
            error("Unexpected argument: $arg")
        end
    end
    snapshot !== nothing && target !== nothing && error("Use --snapshot or TARGET_LOG_LAMBDA, not both")
    cuts !== nothing && bins_explicit && error("Use --bins or --r-cuts, not both")
    return (; run_dir, target, snapshot, cuts, output, bins)
end

function write_profile(path, profile; run_dir, meta, r_bondi, rbhl, rsoft, target)
    open(path, "w") do io
        println(io, "# run_dir = $run_dir")
        println(io, "# snapshot = $(meta.index); time = $(meta.time); target_log_lambda = $target")
        println(io, "# r_bondi = $r_bondi; rbhl = $rbhl; rsoft = $rsoft")
        println(io, "# delta_rho = rho-rho0; force on perturber; Fdf=Fx for +x ambient flow")
        println(io, "# F columns integrate r > r_cut; shells integrate r_cut < r <= r_shell_outer")
        println(io, "# Last shell extends to the finite domain edge (Inf means no further radial bound).")
        println(io, "# Kernels: point=r_vec/r^3; soft=r_vec/(r^2+rsoft^2)^(3/2); exact center excluded.")
        println(io, "# r_cut r_cut_over_rbondi r_cut_over_rbhl r_cut_over_rsoft r_shell_outer Fx_point Fy_point Fz_point Fx_soft Fy_soft Fz_soft dFx_point_shell dFy_point_shell dFz_point_shell dFx_soft_shell dFy_soft_shell dFz_soft_shell")
        for (i, rcut) in enumerate(profile.cuts)
            outer = i < length(profile.cuts) ? profile.cuts[i+1] : Inf
            row = [rcut, rcut/r_bondi, rcut/rbhl, rcut/rsoft, outer,
                   profile.cumulative[i,:]..., profile.shell[i,:]...]
            println(io, join((@sprintf("%.17e", v) for v in row), " "))
        end
    end
end

function main(args=ARGS)
    if args == ["--help"]
        println(USAGE)
        return
    end
    opts = parse_cli(args)
    summary = read_summary(joinpath(opts.run_dir, "run_summary.txt"))
    mp = positive("mp", parse(Float64, summary["mp"]))
    cs0 = positive("cs0", parse(Float64, summary["cs0"]))
    rho0 = positive("rho0", parse(Float64, summary["rho0"]))
    rsoft = positive("rsoft", parse(Float64, summary["rsoft"]))
    r_bondi = mp/cs0^2
    positive("r_bondi", r_bondi)
    rbhl = positive("rbhl", parse(Float64, summary["rbhl"]))
    if haskey(summary, "mach")
        expected = r_bondi/(1 + parse(Float64, summary["mach"])^2)
        isapprox(rbhl, expected; rtol=1e-10) || @warn "Stored rbhl differs from M_p/[cs0^2(1+Mach^2)]; preserving the run metadata" rbhl expected
    end
    origin = Tuple(parse(Float64, get(summary, key, "0.0")) for key in ("x1p", "x2p", "x3p"))
    candidates = unique([get(summary, "output_subdir", "export"), "export", "output"])
    pos = findfirst(name -> isfile(joinpath(opts.run_dir, name, "dbl.out")), candidates)
    pos === nothing && error("No export/output snapshot metadata found")
    output_dir = joinpath(opts.run_dir, candidates[pos])
    centers, widths = read_grid(joinpath(output_dir, "grid.out"))
    dims = Tuple(length.(centers))
    dims[3] > 1 && get(summary, "dimension", "3") == "3" || error("Expected a 3D case")
    metas = read_snapshots(joinpath(output_dir, "dbl.out"))
    target = opts.target === nothing ? parse(Float64, summary["log_lambda_max"]) : opts.target
    if opts.snapshot === nothing
        isfinite(target) || error("Target log Lambda must be finite")
        valid = filter(m -> isfinite(m.time) && m.time > 0, metas)
        isempty(valid) && error("No positive-time snapshots; select an initial dump with --snapshot")
        meta = valid[argmin([abs(log(m.time * cs0 / rbhl)-target) for m in valid])]
    else
        idx = findfirst(m -> m.index == opts.snapshot, metas)
        idx === nothing && error("Snapshot $(opts.snapshot) is not in dbl.out")
        meta = metas[idx]
        target = nothing
    end
    rho = read_density(joinpath(output_dir, @sprintf("data.%04d.dbl", meta.index)), meta, dims)
    rmax = hypot((maximum(abs.(centers[a] .- origin[a])) for a in 1:3)...)
    cuts = opts.cuts === nothing ? collect(range(0.0, nextfloat(rmax); length=opts.bins+1)) : opts.cuts
    profile = radial_profile(rho, centers, widths, cuts; mp, rho0, rsoft, origin)
    path = opts.output === nothing ? joinpath(opts.run_dir, @sprintf("force_radial_profile_3d.%04d.dat", meta.index)) : opts.output
    write_profile(path, profile; run_dir=opts.run_dir, meta, r_bondi, rbhl, rsoft, target)
    println("Wrote $path")
    return profile
end

end # module

if abspath(PROGRAM_FILE) == @__FILE__
    ForceRadialProfile3D.main()
end
