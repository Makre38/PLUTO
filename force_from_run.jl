using Printf

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

function parse_run_summary(summary_path::AbstractString)
    summary = Dict{String, String}()
    for line in eachline(summary_path)
        s = strip(line)
        isempty(s) && continue
        occursin("=", s) || continue
        key, value = split(s, "=", limit = 2)
        summary[strip(key)] = strip(value)
    end
    return summary
end

function compute_force(rho::AbstractMatrix, x::AbstractVector, y::AbstractVector, dx::AbstractVector, dy::AbstractVector;
                       mp::Float64, rho0::Float64, xp::Float64, yp::Float64, rcut::Float64)
    fx = 0.0
    fy = 0.0

    for j in eachindex(y)
        for i in eachindex(x)
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
    end

    return fx, fy
end

function nearest_snapshot(metas::Vector{SnapshotMeta}, target_log_lambda::Float64, rbhl::Float64, cs0::Float64)
    values = [abs(log(meta.time * cs0 / rbhl) - target_log_lambda) for meta in metas if meta.time > 0.0]
    valid = [meta for meta in metas if meta.time > 0.0]
    isempty(valid) && error("No positive-time snapshots available")
    return valid[argmin(values)]
end

function main()
    if isempty(ARGS)
        error("Usage: julia force_from_run.jl RUN_DIR [TARGET_LOG_LAMBDA]")
    end

    run_dir = abspath(ARGS[1])
    summary_path = joinpath(run_dir, "run_summary.txt")
    isfile(summary_path) || error("Missing $(summary_path)")
    summary = parse_run_summary(summary_path)
    output_dir = resolve_output_dir(run_dir, summary)

    grid_path = joinpath(output_dir, "grid.out")
    dbl_out_path = joinpath(output_dir, "dbl.out")
    isfile(grid_path) || error("Missing $(grid_path)")
    isfile(dbl_out_path) || error("Missing $(dbl_out_path)")

    x, y, z, dx, dy, dz = parse_grid(grid_path)
    metas = parse_dbl_out(dbl_out_path)

    nx, ny, nz = length(x), length(y), length(z)
    mp = parse(Float64, summary["mp"])
    rbhl = parse(Float64, summary["rbhl"])
    cs0 = parse(Float64, summary["cs0"])
    rho0 = parse(Float64, summary["rho0"])
    xp = parse(Float64, summary["x1p"])
    yp = parse(Float64, summary["x2p"])
    rcut = rbhl

    target_log_lambda = length(ARGS) >= 2 ? parse(Float64, ARGS[2]) : parse(Float64, summary["log_lambda_max"])
    meta = nearest_snapshot(metas, target_log_lambda, rbhl, cs0)

    data_path = joinpath(output_dir, @sprintf("data.%04d.dbl", meta.index))
    isfile(data_path) || error("Missing $(data_path)")

    rho = read_snapshot_var(data_path, meta, "rho", nx, ny, nz)
    fx, fy = compute_force(rho, x, y, dx, dy; mp = mp, rho0 = rho0, xp = xp, yp = yp, rcut = rcut)
    log_lambda = log(meta.time * cs0 / rbhl)

    println("# run_dir = $(run_dir)")
    println("# snapshot = $(meta.index)")
    @printf("# time = %.8e\n", meta.time)
    @printf("# log_lambda = %.8f\n", log_lambda)
    @printf("# rcut = %.8e\n", rcut)
    @printf("Fx = %.12e\n", fx)
    @printf("Fy = %.12e\n", fy)
    @printf("Fdf = %.12e\n", -fx)
end

main()
