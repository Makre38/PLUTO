module AlphaProfile3D

using Printf
include(joinpath(@__DIR__, "force_radial_profile_3d.jl"))
using .ForceRadialProfile3D: read_summary, read_grid, read_snapshots, positive

const USAGE = """
Usage: julia plot_alpha_profile_3d.jl RUN_DIR TARGET_LOG_LAMBDA [--output PATH.png]

Plot raw alpha = rho/rho0 - 1 along x at (y,z)=(y_p,z_p).
Choose the nearest positive-time snapshot in log Lambda = ln(t*cs0/r_BHL).
Interpolate between transverse cell centers; do not interpolate in time.
Write a PNG and a same-stem .dat table. Requires Plots for rendering.
"""

function parse_cli(args)
    positional = String[]
    output = nothing
    i = 1
    while i <= length(args)
        arg = args[i]
        if arg == "--output"
            i < length(args) || error("Missing value after --output")
            output = args[i+1]
            i += 2
        elseif startswith(arg, "--output=")
            output = split(arg, '='; limit=2)[2]
            i += 1
        elseif startswith(arg, "--")
            error("Unknown option: $arg")
        else
            push!(positional, arg)
            i += 1
        end
    end
    length(positional) == 2 || error(USAGE)
    target = parse(Float64, positional[2])
    isfinite(target) || error("Target log Lambda must be finite")
    if output !== nothing
        !isempty(output) && lowercase(splitext(output)[2]) == ".png" ||
            error("--output must name a .png file")
    end
    return (; run_dir=abspath(positional[1]), target, output)
end

"""Weights at a physical coordinate, using cell centers without extrapolation."""
function transverse_weights(coords, target)
    all(isfinite, coords) && !isempty(coords) && all(>(0), diff(coords)) ||
        error("Cell centers must be finite and strictly increasing")
    isfinite(target) || error("Perturber coordinates must be finite")
    first(coords) <= target <= last(coords) ||
        error("Axis position $target is outside the transverse cell-center range")
    hi = searchsortedfirst(coords, target)
    coords[hi] == target && return [(hi, 1.0)]
    lo = hi - 1
    w = (target - coords[lo]) / (coords[hi] - coords[lo])
    return [(lo, 1-w), (hi, w)]
end

log_lambda(time, cs0, rbhl) = log(time) + log(cs0) - log(rbhl)

function select_snapshot(metas, target, cs0, rbhl)
    isfinite(target) || error("Target log Lambda must be finite")
    positive("cs0", cs0)
    positive("rbhl", rbhl)
    valid = filter(m -> isfinite(m.time) && m.time > 0, metas)
    isempty(valid) && error("No positive-time snapshots available for log Lambda selection")
    # A tie uses the earlier entry in dbl.out.
    return valid[argmin([abs(log_lambda(m.time, cs0, rbhl)-target) for m in valid])]
end

"""Read at most four x rows from the rho block, using O(nx) working memory."""
function sample_axis(io, meta, dims, wy, wz)
    meta.mode == "single_file" || error("Only PLUTO single_file double output is supported")
    meta.endian in ("little", "big") || error("Unsupported byte order: $(meta.endian)")
    ivar = findfirst(==("rho"), meta.vars)
    ivar === nothing && error("Snapshot does not contain rho")
    nx, ny, nz = dims
    rho = zeros(nx)
    words = Vector{UInt64}(undef, nx)
    for (k, wk) in wz, (j, wj) in wy
        offset = (ivar-1)*nx*ny*nz + (k-1)*nx*ny + (j-1)*nx
        seek(io, 8*offset)
        read!(io, words)
        if meta.endian == "little"
            words .= ltoh.(words)
        else
            words .= ntoh.(words)
        end
        values = reinterpret(Float64, words)
        all(isfinite, values) || error("Nonfinite density in sampled row (j=$j, k=$k)")
        all(>=(0), values) || error("Negative density in sampled row (j=$j, k=$k)")
        rho .+= (wj*wk) .* values
    end
    return rho
end

function load_profile(run_dir, target)
    summary = read_summary(joinpath(run_dir, "run_summary.txt"))
    rho0 = positive("rho0", parse(Float64, summary["rho0"]))
    cs0 = positive("cs0", parse(Float64, summary["cs0"]))
    rbhl = positive("rbhl", parse(Float64, summary["rbhl"]))
    xp, yp, zp = (parse(Float64, get(summary, k, "0.0")) for k in ("x1p", "x2p", "x3p"))
    all(isfinite, (xp, yp, zp)) || error("Perturber coordinates must be finite")
    candidates = unique([get(summary, "output_subdir", "export"), "export", "output"])
    selected = findfirst(p -> isfile(joinpath(run_dir, p, "dbl.out")), candidates)
    selected === nothing && error("No export/output snapshot metadata found")
    output_dir = joinpath(run_dir, candidates[selected])
    centers, _ = read_grid(joinpath(output_dir, "grid.out"))
    x, y, z = centers
    dims = Tuple(length.(centers))
    get(summary, "dimension", "3") == "3" && all(>(1), dims) ||
        error("Expected a 3D grid with at least two cells per axis")
    all(isfinite, x) && all(>(0), diff(x)) || error("Invalid x cell centers")
    wy, wz = transverse_weights(y, yp), transverse_weights(z, zp)
    metas = read_snapshots(joinpath(output_dir, "dbl.out"))
    meta = select_snapshot(metas, target, cs0, rbhl)
    path = joinpath(output_dir, @sprintf("data.%04d.dbl", meta.index))
    filesize(path) == 8*prod(dims)*length(meta.vars) ||
        error("Snapshot size does not match metadata/grid")
    rho = open(path, "r") do io
        sample_axis(io, meta, dims, wy, wz)
    end
    alpha = rho ./ rho0 .- 1
    all(isfinite, alpha) || error("Nonfinite alpha after normalization")
    return (; x, rho, alpha, xp, yp, zp, rho0, cs0, rbhl, target, meta,
              actual=log_lambda(meta.time, cs0, rbhl),
              y_samples=[(index=j, coordinate=y[j], weight=w) for (j,w) in wy],
              z_samples=[(index=k, coordinate=z[k], weight=w) for (k,w) in wz])
end

function write_table(path, p; run_dir)
    open(path, "w") do io
        println(io, "# run_dir = $(abspath(run_dir))")
        println(io, "# snapshot = $(p.meta.index)")
        println(io, "# time = $(p.meta.time); requested_log_lambda = $(p.target); actual_log_lambda = $(p.actual)")
        println(io, "# rho0 = $(p.rho0); cs0 = $(p.cs0); rbhl = $(p.rbhl)")
        println(io, "# perturber = ($(p.xp), $(p.yp), $(p.zp)); axis = x")
        println(io, "# bilinear interpolation of cell-centered rho in y,z; exact centers used directly")
        println(io, "# y_samples (1-based index, coordinate, weight) = $(p.y_samples)")
        println(io, "# z_samples (1-based index, coordinate, weight) = $(p.z_samples)")
        println(io, "# Raw signed alpha; no log transform, clipping, spatial averaging along x, or time interpolation")
        println(io, "# x x_minus_xp rho alpha")
        for i in eachindex(p.x)
            @printf(io, "%.17e %.17e %.17e %.17e\n", p.x[i], p.x[i]-p.xp, p.rho[i], p.alpha[i])
        end
    end
end

function write_plot(path, p)
    title = @sprintf("snapshot %d: t=%.6g, log Lambda=%.6g (requested %.6g)\ny=%.6g, z=%.6g",
                     p.meta.index, p.meta.time, p.actual, p.target, p.yp, p.zp)
    plt = Plots.plot(p.x .- p.xp, p.alpha;
                     xlabel="x - x_p", ylabel="alpha = rho / rho0 - 1",
                     label="alpha", title, linewidth=2, size=(1000, 600),
                     left_margin=20*Plots.mm, bottom_margin=5*Plots.mm)
    Plots.hline!(plt, [0.0]; label="", color=:gray, linestyle=:dash)
    Plots.vline!(plt, [0.0]; label="perturber", color=:black, linestyle=:dot)
    Plots.savefig(plt, path)
end

function main(args=ARGS)
    if args == ["--help"]
        println(USAGE)
        return
    end
    opts = parse_cli(args)
    p = load_profile(opts.run_dir, opts.target)
    png = opts.output === nothing ?
        joinpath(opts.run_dir, @sprintf("alpha_profile_x.%04d.png", p.meta.index)) : abspath(opts.output)
    table = splitext(png)[1] * ".dat"
    # Numeric extraction/tests can use the module without loading a plotting backend.
    @eval import Plots
    mkpath(dirname(png))
    Base.invokelatest(write_plot, png, p)
    write_table(table, p; run_dir=opts.run_dir)
    @printf("Selected snapshot %d: t=%.8g, log Lambda=%.8g (requested %.8g)\n",
            p.meta.index, p.meta.time, p.actual, p.target)
    println("Wrote $png")
    println("Wrote $table")
    return p
end

end # module

if abspath(PROGRAM_FILE) == @__FILE__
    AlphaProfile3D.main()
end
