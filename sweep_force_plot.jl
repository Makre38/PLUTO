using Printf
using Plots

const DEFAULT_TARGET_LOG_LAMBDAS = [1.0, 1.5, 2.0]

struct SnapshotMeta
    index::Int
    time::Float64
    dt::Float64
    step::Int
    mode::String
    endian::String
    vars::Vector{String}
end

function resolve_output_dir(run_dir::AbstractString, summary::Dict{String, String})
    if haskey(summary, "output_subdir")
        candidate = joinpath(run_dir, summary["output_subdir"])
        isdir(candidate) && return candidate
    end
    for name in ("export", "output")
        candidate = joinpath(run_dir, name)
        isdir(candidate) && return candidate
    end
    error("Missing export/output directory under $(run_dir)")
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
        rho0 = getf("rho0", "RHO0"),
        x1p = haskey(summary, "x1p") ? parse(Float64, summary["x1p"]) : get(ini, "X1P", 0.0),
        x2p = haskey(summary, "x2p") ? parse(Float64, summary["x2p"]) : get(ini, "X2P", 0.0),
        log_lambda_max = getf("log_lambda_max", "LOG_LAMBDA_MAX"),
    )
end

function compute_force(rho::AbstractMatrix, x::AbstractVector, y::AbstractVector, dx::AbstractVector, dy::AbstractVector;
                       mp::Float64, rho0::Float64, xp::Float64, yp::Float64, rcut::Float64)
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
        delta_mass = (rho[i, j] - rho0) * dx[i] * dy[j]
        inv_r3 = 1.0 / (r2 * r)
        fx += mp * delta_mass * rx * inv_r3
        fy += mp * delta_mass * ry * inv_r3
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
    params = get_run_params(run_dir)
    summary_path = joinpath(run_dir, "run_summary.txt")
    summary = isfile(summary_path) ? parse_key_value_file(summary_path) : Dict{String, String}()
    output_dir = resolve_output_dir(run_dir, summary)
    grid_path = joinpath(output_dir, "grid.out")
    dbl_out_path = joinpath(output_dir, "dbl.out")
    isfile(grid_path) || error("Missing $(grid_path)")
    isfile(dbl_out_path) || error("Missing $(dbl_out_path)")
    x, y, z, dx, dy, dz = parse_grid(grid_path)
    metas = parse_dbl_out(dbl_out_path)
    meta = nearest_snapshot(metas, target_log_lambda, params.rbhl, params.cs0)

    nx, ny, nz = length(x), length(y), length(z)
    data_path = joinpath(output_dir, @sprintf("data.%04d.dbl", meta.index))
    isfile(data_path) || error("Missing $(data_path)")
    rho = read_snapshot_var(data_path, meta, "rho", nx, ny, nz)
    fx, fy = compute_force(rho, x, y, dx, dy; mp = params.mp, rho0 = params.rho0, xp = params.x1p, yp = params.x2p, rcut = params.rbhl)
    log_lambda = log(meta.time * params.cs0 / params.rbhl)

    return (
        mach = params.mach,
        target_log_lambda = target_log_lambda,
        fx = fx,
        fy = fy,
        fdf = fx,
        actual_log_lambda = log_lambda,
        snapshot = meta.index,
        run_dir = run_dir,
    )
end

function sanitize_log_lambda_label(value::Float64)
    text = @sprintf("%.3f", value)
    text = replace(text, "-" => "m")
    return replace(text, "." => "p")
end

function write_results_table(table_path::AbstractString, results)
    open(table_path, "w") do io
        println(io, "# Mach target_log_lambda actual_log_lambda snapshot Fx Fy Fdf run_dir")
        for r in results
            @printf(io, "%.8f %.8f %.8f %d %.12e %.12e %.12e %s\n",
                    r.mach, r.target_log_lambda, r.actual_log_lambda, r.snapshot, r.fx, r.fy, r.fdf, r.run_dir)
        end
    end
end

function parse_cli_targets_and_prefix(runs_dir::AbstractString, args::Vector{String})
    target_log_lambdas = DEFAULT_TARGET_LOG_LAMBDAS
    output_prefix = joinpath(runs_dir, "force_summary")

    if length(args) >= 1
        first_arg = args[1]
        parsed_target = tryparse(Float64, first_arg)
        if parsed_target === nothing
            output_prefix = abspath(first_arg)
        else
            target_log_lambdas = [parsed_target]
            if length(args) >= 2
                output_prefix = abspath(args[2])
            end
        end
    end

    return target_log_lambdas, output_prefix
end

function main()
    if isempty(ARGS)
        error("Usage: julia sweep_force_plot.jl RUNS_DIR [TARGET_LOG_LAMBDA|OUTPUT_PREFIX] [OUTPUT_PREFIX]")
    end

    runs_dir = abspath(ARGS[1])
    target_log_lambdas, output_prefix = parse_cli_targets_and_prefix(runs_dir, ARGS[2:end])

    run_dirs = sort(filter(path -> isdir(path) && basename(path) != "output", readdir(runs_dir; join = true)))
    isempty(run_dirs) && error("No run directories found in $(runs_dir)")

    results = NamedTuple[]
    for target_log_lambda in target_log_lambdas
        for run_dir in run_dirs
            try
                push!(results, compute_run_force(run_dir, target_log_lambda))
            catch err
                @warn "Skipping run" run_dir target_log_lambda err
            end
        end
    end
    isempty(results) && error("No usable runs found in $(runs_dir)")

    sort!(results, by = r -> (r.target_log_lambda, r.mach))

    for target_log_lambda in target_log_lambdas
        per_target = [r for r in results if r.target_log_lambda == target_log_lambda]
        isempty(per_target) && continue
        suffix = sanitize_log_lambda_label(target_log_lambda)
        table_path = output_prefix * "_loglambda_" * suffix * ".dat"
        write_results_table(table_path, per_target)
        println("Wrote $(table_path)")
    end

    plt = plot(xlabel = "Mach", ylabel = "Fdf", title = "Fdf vs Mach")
    for target_log_lambda in target_log_lambdas
        per_target = sort([r for r in results if r.target_log_lambda == target_log_lambda], by = r -> r.mach)
        isempty(per_target) && continue
        plot!(
            plt,
            [r.mach for r in per_target],
            [r.fdf for r in per_target],
            marker = :circle,
            label = @sprintf("log Lambda ~= %.3f", target_log_lambda),
        )
    end
    png(plt, output_prefix * ".png")

    println("Wrote $(output_prefix * ".png")")
end

main()
