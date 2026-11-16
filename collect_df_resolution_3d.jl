module DFResolution3D

using Printf

# Import the existing readers/integral without running their CLI or loading plots.
module OneCase
include(joinpath(@__DIR__, "force_from_run.jl"))
end

const USAGE = "julia collect_df_resolution_3d.jl RUNS_DIR LOG_LAMBDA [--output PATH] [--force|-f]"
const MATCH_RTOL = 1e-10
const GRID_RTOL = 1e-8
# dbl.out writes times with limited precision (typically %.6e).
const TIME_ATOL = 1e-6
same(a, b) = isapprox(a, b; rtol=MATCH_RTOL, atol=0)

function number(summary, key; positive=true)
    haskey(summary, key) || error("Missing run_summary.txt key: $key")
    value = tryparse(Float64, summary[key])
    value !== nothing && isfinite(value) && (positive ? value > 0 : value >= 0) ||
        error("$key must be a finite $(positive ? "positive" : "nonnegative") number")
    return value
end

function read_case(path)
    summary_path = joinpath(path, "run_summary.txt")
    isfile(summary_path) || error("Missing $summary_path")
    summary = Dict{String,String}()
    for (line_number, line) in enumerate(eachline(summary_path))
        s = strip(line)
        (isempty(s) || startswith(s, '#')) && continue
        occursin('=', s) || error("Malformed $summary_path line $line_number")
        key, value = strip.(split(s, '='; limit=2))
        !isempty(key) && !haskey(summary, key) || error("Empty or duplicate summary key: $key")
        summary[key] = value
    end
    get(summary, "dimension", "") == "3" || error("Only 3D cases are supported: $path")
    mach = number(summary, "mach"; positive=false)
    a_soft = number(summary, "a_soft")
    target_resolution = number(summary, "cells_per_rbhl_target")
    resolution = number(summary, "cells_per_rbhl_x")
    rbhl, mp, cs0, rho0 = (number(summary, k) for k in ("rbhl", "mp", "cs0", "rho0"))
    origin = ntuple(3) do axis
        key = "x$(axis)p"
        value = tryparse(Float64, get(summary, key, ""))
        value !== nothing && isfinite(value) || error("Missing or invalid $key")
        value
    end
    if haskey(summary, "dx_actual")
        same(resolution, rbhl / number(summary, "dx_actual")) ||
            error("cells_per_rbhl_x disagrees with rbhl/dx_actual: $path")
    end
    norm = 4π * rho0 * mp^2 / cs0^2
    isfinite(norm) && norm > 0 || error("Invalid DF normalization: $path")
    return (; path, summary, mach, a_soft, target_resolution, resolution,
            rbhl, mp, cs0, rho0, origin, norm)
end

function discover(root)
    isdir(root) || error("Not a directory: $root")
    paths = filter(readdir(root; join=true)) do path
        isdir(path) && (isfile(joinpath(path, "run_summary.txt")) ||
                       isfile(joinpath(path, "pluto.ini")))
    end
    isempty(paths) && error("No cases found directly under $root")
    return map(sort(paths)) do path
        try
            read_case(path)
        catch err
            err isa InterruptException && rethrow()
            error("Case $path: $(sprint(showerror, err))")
        end
    end
end

function read_snapshots(path)
    metas = OneCase.SnapshotMeta[]
    indices = Set{Int}()
    for (line_number, line) in enumerate(eachline(path))
        s = strip(line)
        (isempty(s) || startswith(s, '#')) && continue
        cols = split(s)
        length(cols) >= 7 || error("Malformed $path line $line_number")
        idx, t, dt, step = parse(Int, cols[1]), parse(Float64, cols[2]),
                           parse(Float64, cols[3]), parse(Int, cols[4])
        idx >= 0 && !(idx in indices) || error("Invalid or duplicate snapshot index in $path")
        isfinite(t) && t >= 0 && isfinite(dt) && dt >= 0 && step >= 0 ||
            error("Invalid snapshot time/step in $path")
        length(unique(cols[7:end])) == length(cols[7:end]) ||
            error("Duplicate variable names in $path")
        push!(indices, idx)
        push!(metas, OneCase.SnapshotMeta(idx, t, dt, step, cols[5], cols[6], cols[7:end]))
    end
    return metas
end

log_time(meta, case) = log(meta.time) + log(case.cs0) - log(case.rbhl)

function load_force(case, target)
    # Empty output directories are normal for cases that have not started yet.
    subdir = get(case.summary, "output_subdir", "export")
    candidates = unique([subdir, "export", "output"])
    output = nothing
    for name in candidates
        dir = joinpath(case.path, name)
        has_grid, has_dbl = isfile(joinpath(dir, "grid.out")), isfile(joinpath(dir, "dbl.out"))
        has_grid == has_dbl || error("Incomplete grid.out/dbl.out pair: $dir")
        if has_grid
            output = dir
            break
        end
    end
    output === nothing && return nothing
    metas = read_snapshots(joinpath(output, "dbl.out"))
    valid = filter(m -> m.time > 0, metas)
    isempty(valid) && return nothing
    times = log_time.(valid, Ref(case))
    maximum(times) + TIME_ATOL >= target || return nothing
    meta = valid[argmin(abs.(times .- target))]
    meta.mode == "single_file" || error("Only single_file double output is supported")
    meta.endian in ("little", "big") || error("Unsupported endian flag: $(meta.endian)")
    "rho" in meta.vars || error("rho missing from snapshot metadata")
    x, y, z, dx, dy, dz = OneCase.parse_grid(joinpath(output, "grid.out"))
    length(z) > 1 || error("Expected a 3D grid")
    for (centers, widths) in ((x, dx), (y, dy), (z, dz))
        all(isfinite, centers) && all(v -> isfinite(v) && v > 0, widths) ||
            error("Invalid grid centers or cell widths")
        issorted(centers; lt=<=) || error("Grid centers must increase strictly")
    end
    expected_dx = case.rbhl / case.resolution
    all(v -> isapprox(v, expected_dx; rtol=GRID_RTOL, atol=0), dx) ||
        error("grid.out x spacing disagrees with cells_per_rbhl_x")
    data = joinpath(output, @sprintf("data.%04d.dbl", meta.index))
    expected_bytes = 8 * length(x) * length(y) * length(z) * length(meta.vars)
    isfile(data) && filesize(data) == expected_bytes ||
        error("Missing or incorrectly sized snapshot: $data (expected $expected_bytes bytes)")
    rho = OneCase.read_snapshot_var(data, meta, "rho", length(x), length(y), length(z))
    all(v -> isfinite(v) && v >= 0, rho) || error("Nonfinite or negative density in $data")
    fx, _, _ = OneCase.compute_force_3d(rho, x, y, z, dx, dy, dz;
        mp=case.mp, rho0=case.rho0, xp=case.origin[1], yp=case.origin[2],
        zp=case.origin[3], rcut=case.rbhl)
    df = fx / case.norm
    isfinite(df) || error("Nonfinite normalized DF: $data")
    return (; df, fx, meta, actual=log_time(meta, case))
end

function distinct_sorted(values)
    result = Float64[]
    for v in sort(collect(values))
        (isempty(result) || !same(v, last(result))) && push!(result, v)
    end
    return result
end

function collect_table(root, target)
    isfinite(target) || error("LOG_LAMBDA must be finite")
    cases = discover(root)
    all(c -> same(c.mach, first(cases).mach), cases) || error("Mach differs between cases")
    targets = distinct_sorted(c.target_resolution for c in cases)
    a_values = distinct_sorted(c.a_soft for c in cases)
    resolutions = fill(NaN, length(targets))
    cells = Dict{Tuple{Int,Int},Int}()
    for (idx, c) in enumerate(cases)
        i = findfirst(v -> same(v, c.target_resolution), targets)
        j = findfirst(v -> same(v, c.a_soft), a_values)
        haskey(cells, (i,j)) && error("Duplicate resolution/A_soft: $(cases[cells[(i,j)]].path) and $(c.path)")
        cells[(i,j)] = idx
        if isnan(resolutions[i])
            resolutions[i] = c.resolution
        elseif !same(resolutions[i], c.resolution)
            error("Actual R_BHL/dx differs across A_soft at target resolution $(targets[i])")
        end
    end
    length(distinct_sorted(resolutions)) == length(resolutions) ||
        error("Different target resolutions produce the same actual R_BHL/dx")
    values = fill(NaN, length(targets), length(a_values))
    records = NamedTuple[]
    for (i,j) in sort(collect(keys(cells)))
        c = cases[cells[(i,j)]]
        result = try
            load_force(c, target)
        catch err
            err isa InterruptException && rethrow()
            error("Case $(c.path): $(sprint(showerror, err))")
        end
        if result !== nothing
            values[i,j] = result.df
        end
        push!(records, (; case=c, result))
    end
    rows = [i for i in sortperm(resolutions) if any(isfinite, values[i,:])]
    isempty(rows) && error("No cases have reached log Lambda = $target; no table written")
    return (; cases, targets, a_values, resolutions, values, records, rows, target)
end

function render_table(table)
    io = IOBuffer()
    println(io, "# Normalized DF versus actual x resolution (3D)")
    println(io, "# Mach = ", first(table.cases).mach)
    println(io, "# target_log_lambda = ", table.target)
    println(io, "# DF = Fx / [4*pi*rho0*(G*mp)^2/cs0^2]; G=1; delta_rho=rho-rho0")
    println(io, "# point kernel; r_cut=R_BHL; include cells at r=R_BHL; Fdf=Fx for +x flow")
    println(io, "# A_soft=R_B/r_soft; x=R_BHL/dx_actual; rows sorted by x; columns sorted by A_soft")
    println(io, "# NaN=unavailable (absent combination or target not reached); no time interpolation")
    println(io, "# reach_tolerance_log_lambda = ", TIME_ATOL)
    println(io, "# R_BHL_over_dx ", join(["DF_A$(a)" for a in table.a_values], ' '))
    for i in table.rows
        println(io, join(string.([table.resolutions[i]; table.values[i,:]]), ' '))
    end
    println(io, "# Per-case provenance (paths are Julia-quoted; comment lines are not data rows)")
    for record in table.records
        c, result = record.case, record.result
        print(io, "# case target_resolution=$(c.target_resolution) actual_resolution=$(c.resolution) A_soft=$(c.a_soft)")
        if result === nothing
            print(io, " status=not_reached")
        else
            print(io, " snapshot=$(result.meta.index) time=$(result.meta.time) actual_log_lambda=$(result.actual)",
                      " Fx=$(result.fx) normalization=$(c.norm)")
        end
        println(io, " rho0=$(c.rho0) cs0=$(c.cs0) mp=$(c.mp) gamma=$(get(c.summary, "gamma", "unavailable")) run_dir=", repr(c.path))
    end
    return String(take!(io))
end

function check_destination(path, force)
    endswith(lowercase(path), ".dat") || error("Output must have a .dat extension")
    isdir(dirname(path)) || error("Output parent directory does not exist: $(dirname(path))")
    islink(path) && error("Refusing a symbolic-link output: $path")
    if ispath(path)
        isfile(path) || error("Output is not a regular file: $path")
        force || error("Output exists: $path; use --force or -f to overwrite")
    end
end

function write_table(path, content, force)
    check_destination(path, force)
    # Exclusive creation also protects against a destination appearing during analysis.
    flags = Base.JL_O_WRONLY | Base.JL_O_CREAT | (force ? Base.JL_O_TRUNC : Base.JL_O_EXCL)
    file = Base.Filesystem.open(path, flags, 0o666)
    try
        write(file, content)
    finally
        close(file)
    end
end

function parse_cli(args)
    positionals = String[]
    output, force = nothing, false
    i = 1
    while i <= length(args)
        arg = args[i]
        if arg in ("--force", "-f")
            force = true
        elseif arg == "--output"
            i < length(args) || error("Missing PATH after --output")
            output === nothing || error("--output supplied more than once")
            i += 1
            output = args[i]
        elseif startswith(arg, "--output=")
            output === nothing || error("--output supplied more than once")
            output = split(arg, '='; limit=2)[2]
        elseif startswith(arg, '-') && tryparse(Float64, arg) === nothing
            error("Unknown option: $arg")
        else
            push!(positionals, arg)
        end
        i += 1
    end
    length(positionals) == 2 || error("Usage: $USAGE")
    target = tryparse(Float64, positionals[2])
    target !== nothing && isfinite(target) || error("LOG_LAMBDA must be finite")
    root = abspath(positionals[1])
    default_name = "df_resolution_loglambda_$(target).dat"
    path = output === nothing ? joinpath(root, default_name) : abspath(output)
    return (; root, target, path, force)
end

function main(args=ARGS)
    if args == ["--help"] || args == ["-h"]
        println("Usage: $USAGE\nRead immediate case directories; write a normalized DF .dat table only.")
        return 0
    end
    try
        opts = parse_cli(args)
        check_destination(opts.path, opts.force) # Before expensive snapshot reads.
        table = collect_table(opts.root, opts.target)
        write_table(opts.path, render_table(table), opts.force)
        println("Wrote $(opts.path)")
        return 0
    catch err
        err isa InterruptException && rethrow()
        println(stderr, "ERROR: ", sprint(showerror, err))
        return 1
    end
end

end # module DFResolution3D

if abspath(PROGRAM_FILE) == @__FILE__
    exit(DFResolution3D.main())
end
