using DelimitedFiles
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
    dims = Vector{Vector{Float64}}()
    for _ in 1:3
        n = parse(Int, strip(lines[pos]))
        pos += 1
        centers = Vector{Float64}(undef, n)
        for i in 1:n
            cols = split(strip(lines[pos]))
            xl = parse(Float64, cols[2])
            xr = parse(Float64, cols[3])
            centers[i] = 0.5 * (xl + xr)
            pos += 1
        end
        push!(dims, centers)
    end

    return dims[1], dims[2], dims[3]
end

function parse_dbl_out(dbl_out_path::AbstractString)
    metas = SnapshotMeta[]
    for line in eachline(dbl_out_path)
        s = strip(line)
        isempty(s) && continue
        cols = split(s)
        length(cols) < 6 && continue
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

function read_snapshot_density(data_path::AbstractString, meta::SnapshotMeta, nx::Int, ny::Int, nz::Int)
    rho_index = findfirst(==("rho"), meta.vars)
    rho_index === nothing && error("rho not found in $(basename(data_path)) metadata")

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

    offset = (rho_index - 1) * ncell
    rho = reshape(@view(values[offset + 1:offset + ncell]), nx, ny, nz)
    return Array(@view(rho[:, :, 1]))
end

function main()
    if isempty(ARGS)
        error("Usage: julia animate_density.jl RUN_DIR [OUTPUT_GIF]")
    end

    run_dir = abspath(ARGS[1])
    output_gif = length(ARGS) >= 2 ? abspath(ARGS[2]) : joinpath(run_dir, "density.gif")
    output_dir = joinpath(run_dir, "output")

    grid_path = joinpath(output_dir, "grid.out")
    dbl_out_path = joinpath(output_dir, "dbl.out")
    isfile(grid_path) || error("Missing $(grid_path)")
    isfile(dbl_out_path) || error("Missing $(dbl_out_path)")

    x, y, z = parse_grid(grid_path)
    metas = parse_dbl_out(dbl_out_path)
    isempty(metas) && error("No snapshots found in $(dbl_out_path)")

    nx, ny, nz = length(x), length(y), length(z)
    data_paths = [joinpath(output_dir, @sprintf("data.%04d.dbl", meta.index)) for meta in metas]
    missing_paths = filter(path -> !isfile(path), data_paths)
    isempty(missing_paths) || error("Missing data files, for example: $(first(missing_paths))")

    first_rho = read_snapshot_density(first(data_paths), first(metas), nx, ny, nz)
    rho_floor = max(eps(Float64), 1.0e-12)
    log_rho_min = minimum(log10.(max.(first_rho, rho_floor)))
    log_rho_max = maximum(log10.(max.(first_rho, rho_floor)))
    for (meta, path) in zip(metas[2:end], data_paths[2:end])
        rho = read_snapshot_density(path, meta, nx, ny, nz)
        log_rho = log10.(max.(rho, rho_floor))
        log_rho_min = min(log_rho_min, minimum(log_rho))
        log_rho_max = max(log_rho_max, maximum(log_rho))
    end

    anim = @animate for (meta, path) in zip(metas, data_paths)
        rho = read_snapshot_density(path, meta, nx, ny, nz)
        log_rho = log10.(max.(rho, rho_floor))
        heatmap(
            x,
            y,
            permutedims(log_rho, (2, 1)),
            xlabel = "x",
            ylabel = "y",
            title = @sprintf("log10 density, t = %.4f", meta.time),
            colorbar_title = "log10 rho",
            clims = (log_rho_min, log_rho_max),
            aspect_ratio = :equal,
        )
        scatter!([0.0], [0.0], color = :white, markerstrokecolor = :black, label = "", markersize = 3)
    end

    gif(anim, output_gif, fps = min(length(metas), 12))
    println("Wrote $(output_gif)")
end

main()
