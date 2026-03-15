using Printf
using Plots

struct SnapshotMeta
    index::Int
    time::Float64
    dt::Float64
    step::Int
    mode::String
    endian::String
    vars::Vector{String}
end

function parse_grid(grid_path::AbstractString)
    raw_lines = readlines(grid_path)
    lines = filter(line -> !isempty(strip(line)) && !startswith(strip(line), "#"), raw_lines)

    pos = 1
    centers = Vector{Vector{Float64}}()
    widths = Vector{Vector{Float64}}()
    for _ in 1:3
        n = parse(Int, strip(lines[pos]))
        pos += 1
        xc = Vector{Float64}(undef, n)
        dx = Vector{Float64}(undef, n)
        for i in 1:n
            cols = split(strip(lines[pos]))
            xl = parse(Float64, cols[2])
            xr = parse(Float64, cols[3])
            xc[i] = 0.5 * (xl + xr)
            dx[i] = xr - xl
            pos += 1
        end
        push!(centers, xc)
        push!(widths, dx)
    end

    return centers[1], centers[2], centers[3], widths[1], widths[2], widths[3]
end

function parse_dbl_out(dbl_out_path::AbstractString)
    metas = SnapshotMeta[]
    for line in eachline(dbl_out_path)
        s = strip(line)
        isempty(s) && continue
        cols = split(s)
        length(cols) < 7 && continue
        push!(metas, SnapshotMeta(
            parse(Int, cols[1]),
            parse(Float64, cols[2]),
            parse(Float64, cols[3]),
            parse(Int, cols[4]),
            cols[5],
            cols[6],
            cols[7:end],
        ))
    end
    return metas
end

function read_snapshot_var(data_path::AbstractString, meta::SnapshotMeta, var_name::AbstractString, nx::Int, ny::Int, nz::Int)
    var_index = findfirst(==(var_name), meta.vars)
    var_index === nothing && error("$(var_name) not found in $(basename(data_path)) metadata")

    ncell = nx * ny * nz
    values = Vector{Float64}(undef, ncell * length(meta.vars))
    open(data_path, "r") do io
        read!(io, values)
    end

    if meta.endian == "big"
        values .= reinterpret(Float64, bswap.(reinterpret(UInt64, values)))
    elseif meta.endian != "little"
        error("Unsupported endian flag: $(meta.endian)")
    end

    offset = (var_index - 1) * ncell
    field = reshape(@view(values[offset + 1:offset + ncell]), nx, ny, nz)
    return Array(@view(field[:, :, 1]))
end

function parse_key_value_file(path::AbstractString)
    data = Dict{String, String}()
    for line in eachline(path)
        s = strip(line)
        isempty(s) && continue
        occursin("=", s) || continue
        key, value = split(s, "=", limit = 2)
        data[strip(key)] = strip(value)
    end
    return data
end

function parse_pluto_ini_params(path::AbstractString)
    params = Dict{String, Float64}()
    in_params = false
    for line in eachline(path)
        s = strip(line)
        isempty(s) && continue
        if startswith(s, "[")
            in_params = s == "[Parameters]"
            continue
        end
        in_params || continue
        cols = split(s)
        length(cols) >= 2 || continue
        try
            params[cols[1]] = parse(Float64, cols[2])
        catch
        end
    end
    return params
end

function get_run_params(run_dir::AbstractString)
    summary_path = joinpath(run_dir, "run_summary.txt")
    ini_path = joinpath(run_dir, "pluto.ini")

    summary = isfile(summary_path) ? parse_key_value_file(summary_path) : Dict{String, String}()
    ini = isfile(ini_path) ? parse_pluto_ini_params(ini_path) : Dict{String, Float64}()

    function getf(key::String, ini_key::String = uppercase(key))
        if haskey(summary, key)
            return parse(Float64, summary[key])
        elseif haskey(ini, ini_key)
            return ini[ini_key]
        else
            error("Missing parameter $(key) in $(run_dir)")
        end
    end

    return (
        mach = getf("mach", "MACH"),
        mp = getf("mp", "MPERT"),
        rbhl = getf("rbhl", "RBHL"),
        cs0 = getf("cs0", "CS0"),
        x1p = haskey(summary, "x1p") ? parse(Float64, summary["x1p"]) : get(ini, "X1P", 0.0),
        x2p = haskey(summary, "x2p") ? parse(Float64, summary["x2p"]) : get(ini, "X2P", 0.0),
        log_lambda_max = getf("log_lambda_max", "LOG_LAMBDA_MAX"),
    )
end

function compute_force(rho::AbstractMatrix, x::AbstractVector, y::AbstractVector, dx::AbstractVector, dy::AbstractVector;
                       mp::Float64, xp::Float64, yp::Float64, rcut::Float64)
    fx = 0.0
    fy = 0.0
    for j in eachindex(y), i in eachindex(x)
        rx = x[i] - xp
        ry = y[j] - yp
        r2 = rx * rx + ry * ry
        r = sqrt(r2)
        if r < rcut || r == 0.0
            continue
        end
        cell_mass = rho[i, j] * dx[i] * dy[j]
        inv_r3 = 1.0 / (r2 * r)
        fx += mp * cell_mass * rx * inv_r3
        fy += mp * cell_mass * ry * inv_r3
    end
    return fx, fy
end

function nearest_snapshot(metas::Vector{SnapshotMeta}, target_log_lambda::Float64, rbhl::Float64, cs0::Float64)
    valid = [meta for meta in metas if meta.time > 0.0]
    isempty(valid) && error("No positive-time snapshots available")
    deltas = [abs(log(meta.time * cs0 / rbhl) - target_log_lambda) for meta in valid]
    return valid[argmin(deltas)]
end

function compute_run_force(run_dir::AbstractString, target_log_lambda::Float64)
    output_dir = joinpath(run_dir, "output")
    grid_path = joinpath(output_dir, "grid.out")
    dbl_out_path = joinpath(output_dir, "dbl.out")
    isfile(grid_path) || error("Missing $(grid_path)")
    isfile(dbl_out_path) || error("Missing $(dbl_out_path)")

    params = get_run_params(run_dir)
    x, y, z, dx, dy, dz = parse_grid(grid_path)
    metas = parse_dbl_out(dbl_out_path)
    meta = nearest_snapshot(metas, target_log_lambda, params.rbhl, params.cs0)

    nx, ny, nz = length(x), length(y), length(z)
    data_path = joinpath(output_dir, @sprintf("data.%04d.dbl", meta.index))
    isfile(data_path) || error("Missing $(data_path)")
    rho = read_snapshot_var(data_path, meta, "rho", nx, ny, nz)
    fx, fy = compute_force(rho, x, y, dx, dy; mp = params.mp, xp = params.x1p, yp = params.x2p, rcut = params.rbhl)
    log_lambda = log(meta.time * params.cs0 / params.rbhl)

    return (
        mach = params.mach,
        fx = fx,
        fy = fy,
        fdf = -fx,
        log_lambda = log_lambda,
        snapshot = meta.index,
        run_dir = run_dir,
    )
end

function main()
    if isempty(ARGS)
        error("Usage: julia sweep_force_plot.jl RUNS_DIR [TARGET_LOG_LAMBDA] [OUTPUT_PREFIX]")
    end

    runs_dir = abspath(ARGS[1])
    target_log_lambda = length(ARGS) >= 2 ? parse(Float64, ARGS[2]) : 2.0
    output_prefix = length(ARGS) >= 3 ? abspath(ARGS[3]) : joinpath(runs_dir, "force_summary")

    run_dirs = sort(filter(path -> isdir(path) && basename(path) != "output", readdir(runs_dir; join = true)))
    isempty(run_dirs) && error("No run directories found in $(runs_dir)")

    results = NamedTuple[]
    for run_dir in run_dirs
        try
            push!(results, compute_run_force(run_dir, target_log_lambda))
        catch err
            @warn "Skipping run" run_dir err
        end
    end
    isempty(results) && error("No usable runs found in $(runs_dir)")

    results = sort(results, by = r -> r.mach)

    table_path = output_prefix * ".dat"
    open(table_path, "w") do io
        println(io, "# Mach log_lambda snapshot Fx Fy Fdf run_dir")
        for r in results
            @printf(io, "%.8f %.8f %d %.12e %.12e %.12e %s\n",
                    r.mach, r.log_lambda, r.snapshot, r.fx, r.fy, r.fdf, r.run_dir)
        end
    end

    plt = plot(
        [r.mach for r in results],
        [r.fdf for r in results],
        marker = :circle,
        xlabel = "Mach",
        ylabel = "Fdf",
        title = @sprintf("Fdf vs Mach at log Lambda ~= %.3f", target_log_lambda),
        legend = false,
    )
    png(plt, output_prefix * ".png")

    println("Wrote $(table_path)")
    println("Wrote $(output_prefix * ".png")")
end

main()
