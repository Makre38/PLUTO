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

struct CliOptions
    run_dir::String
    target_log_lambda::Union{Nothing, Float64}
    output_path::Union{Nothing, String}
    quantity::String
    animate::Bool
    stride::Int
    max_frames::Int
end

const VALID_QUANTITIES = Set(["density", "dfx", "dfy", "dfdf"])

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
    return Array(field)
end

function nearest_index(values::AbstractVector{Float64}, target::Float64)
    return argmin(abs.(values .- target))
end

function nearest_snapshot(metas::Vector{SnapshotMeta}, target_log_lambda::Float64, rbhl::Float64, cs0::Float64)
    valid = [meta for meta in metas if meta.time > 0.0]
    isempty(valid) && error("No positive-time snapshots available")
    distances = [abs(log(meta.time * cs0 / rbhl) - target_log_lambda) for meta in valid]
    return valid[argmin(distances)]
end

function selected_animation_metas(metas::Vector{SnapshotMeta}, stride::Int, max_frames::Int)
    valid = metas[1:stride:end]
    max_frames > 0 && length(valid) > max_frames && (valid = valid[1:max_frames])
    return valid
end

function signed_log_fractional_density(rho, rho0::Float64)
    delta = (rho .- rho0) ./ rho0
    return sign.(delta) .* log10.(1.0 .+ abs.(delta))
end

function force_contribution(rho::Array{Float64, 3},
                            x::AbstractVector, y::AbstractVector, z::AbstractVector,
                            dx::AbstractVector, dy::AbstractVector, dz::AbstractVector;
                            quantity::AbstractString, mp::Float64, rho0::Float64,
                            xp::Float64, yp::Float64, zp::Float64, rcut::Float64)
    values = fill(NaN, size(rho))
    for k in eachindex(z), j in eachindex(y), i in eachindex(x)
        rx = x[i] - xp
        ry = y[j] - yp
        rz = z[k] - zp
        r2 = rx * rx + ry * ry + rz * rz
        r = sqrt(r2)
        if r < rcut || r == 0.0
            continue
        end
        dm = (rho[i, j, k] - rho0) * dx[i] * dy[j] * dz[k]
        common = mp * dm / (r2 * r)
        if quantity == "dfx"
            values[i, j, k] = common * rx
        elseif quantity == "dfy"
            values[i, j, k] = common * ry
        elseif quantity == "dfdf"
            values[i, j, k] = -common * rx
        else
            error("Unsupported force quantity: $(quantity)")
        end
    end
    return values
end

function finite_clims(arrays::AbstractVector; symmetric::Bool)
    vals = Float64[]
    for array in arrays
        append!(vals, filter(isfinite, vec(array)))
    end
    isempty(vals) && return (-1.0, 1.0)
    if symmetric
        vmax = maximum(abs.(vals))
        vmax == 0.0 && (vmax = 1.0)
        return (-vmax, vmax)
    end
    return (minimum(vals), maximum(vals))
end

function circle_xy(cx::Float64, cy::Float64, radius::Float64)
    theta = range(0.0, 2.0 * pi; length = 240)
    return cx .+ radius .* cos.(theta), cy .+ radius .* sin.(theta)
end

function overlay_radii!(plt, cx::Float64, cy::Float64, rsoft::Float64, rcut::Float64)
    xs, ys = circle_xy(cx, cy, rsoft)
    plot!(plt, xs, ys; color = :white, linewidth = 1.2, linestyle = :solid, label = "rsoft")
    xs, ys = circle_xy(cx, cy, rcut)
    plot!(plt, xs, ys; color = :black, linewidth = 1.1, linestyle = :dash, label = "rcut")
end

function quantity_label(quantity::AbstractString)
    quantity == "density" && return "sign(delta) log10(1 + |delta|)"
    quantity == "dfx" && return "dFx per cell"
    quantity == "dfy" && return "dFy per cell"
    quantity == "dfdf" && return "dFdf = -dFx per cell"
    error("Unsupported quantity: $(quantity)")
end

function plot_slices(x, y, z, xy_values, xz_values;
                     quantity::AbstractString, meta::SnapshotMeta, log_lambda::Float64,
                     xp::Float64, yp::Float64, zp::Float64, rsoft::Float64, rcut::Float64,
                     clims::Tuple{Float64, Float64})
    color = quantity == "density" ? :balance : :vik
    title_suffix = @sprintf("t = %.4g, logLambda = %.4f", meta.time, log_lambda)
    pxy = heatmap(
        x,
        y,
        permutedims(xy_values, (2, 1));
        xlabel = "x",
        ylabel = "y",
        title = "z = x3p slice, $(title_suffix)",
        colorbar_title = quantity_label(quantity),
        clims = clims,
        color = color,
        aspect_ratio = :equal,
    )
    overlay_radii!(pxy, xp, yp, rsoft, rcut)
    scatter!(pxy, [xp], [yp]; color = :white, markerstrokecolor = :black, label = "", markersize = 3)

    pxz = heatmap(
        x,
        z,
        permutedims(xz_values, (2, 1));
        xlabel = "x",
        ylabel = "z",
        title = "y = x2p slice, $(title_suffix)",
        colorbar_title = quantity_label(quantity),
        clims = clims,
        color = color,
        aspect_ratio = :equal,
    )
    overlay_radii!(pxz, xp, zp, rsoft, rcut)
    scatter!(pxz, [xp], [zp]; color = :white, markerstrokecolor = :black, label = "", markersize = 3)

    return plot(pxy, pxz; layout = (1, 2), size = (1400, 620))
end

function snapshot_values(rho::Array{Float64, 3}, quantity::AbstractString,
                         x, y, z, dx, dy, dz;
                         mp::Float64, rho0::Float64, xp::Float64, yp::Float64,
                         zp::Float64, rcut::Float64, iy0::Int, iz0::Int)
    values = if quantity == "density"
        signed_log_fractional_density(rho, rho0)
    else
        force_contribution(rho, x, y, z, dx, dy, dz; quantity = quantity, mp = mp, rho0 = rho0, xp = xp, yp = yp, zp = zp, rcut = rcut)
    end
    return Array(@view(values[:, :, iz0])), Array(@view(values[:, iy0, :]))
end

function parse_cli_args(args::Vector{String})
    isempty(args) && error("Usage: julia plot_3d_diagnostics.jl RUN_DIR [TARGET_LOG_LAMBDA] [--quantity density|dfx|dfy|dfdf] [--output PATH] [--animate] [--stride N] [--max-frames N]")

    run_dir = args[1]
    target_log_lambda = nothing
    output_path = nothing
    quantity = "density"
    animate = false
    stride = 1
    max_frames = 0

    i = 2
    while i <= length(args)
        arg = args[i]
        if arg == "--quantity"
            i == length(args) && error("Missing value after --quantity")
            quantity = args[i + 1]
            i += 2
        elseif startswith(arg, "--quantity=")
            quantity = split(arg, "=", limit = 2)[2]
            i += 1
        elseif arg == "--output"
            i == length(args) && error("Missing value after --output")
            output_path = args[i + 1]
            i += 2
        elseif startswith(arg, "--output=")
            output_path = split(arg, "=", limit = 2)[2]
            i += 1
        elseif arg == "--animate"
            animate = true
            i += 1
        elseif arg == "--stride"
            i == length(args) && error("Missing value after --stride")
            stride = parse(Int, args[i + 1])
            i += 2
        elseif startswith(arg, "--stride=")
            stride = parse(Int, split(arg, "=", limit = 2)[2])
            i += 1
        elseif arg == "--max-frames"
            i == length(args) && error("Missing value after --max-frames")
            max_frames = parse(Int, args[i + 1])
            i += 2
        elseif startswith(arg, "--max-frames=")
            max_frames = parse(Int, split(arg, "=", limit = 2)[2])
            i += 1
        elseif startswith(arg, "--")
            error("Unknown option: $(arg)")
        elseif target_log_lambda === nothing
            target_log_lambda = parse(Float64, arg)
            i += 1
        else
            error("Unexpected argument: $(arg)")
        end
    end

    quantity in VALID_QUANTITIES || error("Unsupported --quantity $(quantity). Use density, dfx, dfy, or dfdf.")
    stride >= 1 || error("--stride must be >= 1")
    max_frames >= 0 || error("--max-frames must be >= 0")
    if animate && quantity != "density"
        error("--animate currently supports --quantity density only")
    end

    return CliOptions(run_dir, target_log_lambda, output_path, quantity, animate, stride, max_frames)
end

function default_output_path(run_dir::AbstractString, quantity::AbstractString, target_log_lambda, animate::Bool)
    suffix = animate ? "html" : "png"
    target = target_log_lambda === nothing ? "final" : @sprintf("ll%.3f", target_log_lambda)
    return joinpath(run_dir, "diagnostic_$(quantity)_$(target).$(suffix)")
end

function html_escape(value::AbstractString)
    return replace(value, "&" => "&amp;", "<" => "&lt;", ">" => "&gt;", "\"" => "&quot;")
end

function write_html_animation(output_path::AbstractString, frame_paths::Vector{String}; title::AbstractString)
    rel_paths = [relpath(path, dirname(output_path)) for path in frame_paths]
    open(output_path, "w") do io
        println(io, "<!doctype html>")
        println(io, "<html><head><meta charset=\"utf-8\">")
        println(io, "<title>$(html_escape(title))</title>")
        println(io, "<style>")
        println(io, "body{font-family:sans-serif;margin:16px;background:#111;color:#eee}")
        println(io, "#frame{max-width:100%;height:auto;border:1px solid #444;background:#fff}")
        println(io, ".controls{display:flex;gap:12px;align-items:center;margin:12px 0}")
        println(io, "button{padding:6px 10px}")
        println(io, "input[type=range]{width:min(720px,70vw)}")
        println(io, "</style></head><body>")
        println(io, "<h1>$(html_escape(title))</h1>")
        println(io, "<img id=\"frame\" src=\"$(html_escape(first(rel_paths)))\" alt=\"diagnostic frame\">")
        println(io, "<div class=\"controls\"><button id=\"play\">Pause</button><input id=\"slider\" type=\"range\" min=\"0\" max=\"$(length(rel_paths) - 1)\" value=\"0\"><span id=\"label\">1 / $(length(rel_paths))</span></div>")
        print(io, "<script>const frames=[")
        for (i, path) in enumerate(rel_paths)
            i > 1 && print(io, ",")
            print(io, "\"", html_escape(path), "\"")
        end
        println(io, "];")
        println(io, "let i=0, playing=true; const img=document.getElementById('frame'), slider=document.getElementById('slider'), label=document.getElementById('label'), play=document.getElementById('play');")
        println(io, "function show(n){i=n; img.src=frames[i]; slider.value=i; label.textContent=(i+1)+' / '+frames.length;}")
        println(io, "slider.addEventListener('input',()=>{show(Number(slider.value));});")
        println(io, "play.addEventListener('click',()=>{playing=!playing; play.textContent=playing?'Pause':'Play';});")
        println(io, "setInterval(()=>{if(playing) show((i+1)%frames.length);}, 180);")
        println(io, "</script></body></html>")
    end
end

function main()
    opts = parse_cli_args(ARGS)
    run_dir = abspath(opts.run_dir)
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
    isempty(metas) && error("No snapshots found in $(dbl_out_path)")

    nx, ny, nz = length(x), length(y), length(z)
    nz > 1 || error("This diagnostic plotter expects a 3D run, but nz = $(nz)")

    mp = parse(Float64, summary["mp"])
    rbhl = parse(Float64, summary["rbhl"])
    rsoft = parse(Float64, summary["rsoft"])
    cs0 = parse(Float64, summary["cs0"])
    rho0 = parse(Float64, summary["rho0"])
    xp = parse(Float64, summary["x1p"])
    yp = parse(Float64, summary["x2p"])
    zp = parse(Float64, get(summary, "x3p", "0.0"))
    rcut = rbhl
    target_log_lambda = opts.target_log_lambda === nothing ? parse(Float64, summary["log_lambda_max"]) : opts.target_log_lambda
    iy0 = nearest_index(y, yp)
    iz0 = nearest_index(z, zp)
    output_path = opts.output_path === nothing ? default_output_path(run_dir, opts.quantity, opts.animate ? nothing : target_log_lambda, opts.animate) : abspath(opts.output_path)

    if opts.animate
        frame_metas = selected_animation_metas(metas, opts.stride, opts.max_frames)
        isempty(frame_metas) && error("No frames selected")
        frame_values = []
        for meta in frame_metas
            data_path = joinpath(output_dir, @sprintf("data.%04d.dbl", meta.index))
            isfile(data_path) || error("Missing $(data_path)")
            rho = read_snapshot_var(data_path, meta, "rho", nx, ny, nz)
            xy, xz = snapshot_values(rho, "density", x, y, z, dx, dy, dz; mp = mp, rho0 = rho0, xp = xp, yp = yp, zp = zp, rcut = rcut, iy0 = iy0, iz0 = iz0)
            push!(frame_values, (meta, xy, xz))
        end
        clims = finite_clims(vcat([item[2] for item in frame_values], [item[3] for item in frame_values]); symmetric = true)
        if lowercase(splitext(output_path)[2]) == ".gif"
            anim = @animate for (meta, xy, xz) in frame_values
                log_lambda = meta.time > 0.0 ? log(meta.time * cs0 / rbhl) : -Inf
                plot_slices(x, y, z, xy, xz; quantity = "density", meta = meta, log_lambda = log_lambda, xp = xp, yp = yp, zp = zp, rsoft = rsoft, rcut = rcut, clims = clims)
            end
            gif(anim, output_path, fps = min(length(frame_values), 12))
        else
            frame_dir = joinpath(dirname(output_path), splitext(basename(output_path))[1] * "_frames")
            mkpath(frame_dir)
            frame_paths = String[]
            for (iframe, (meta, xy, xz)) in enumerate(frame_values)
                log_lambda = meta.time > 0.0 ? log(meta.time * cs0 / rbhl) : -Inf
                plt = plot_slices(x, y, z, xy, xz; quantity = "density", meta = meta, log_lambda = log_lambda, xp = xp, yp = yp, zp = zp, rsoft = rsoft, rcut = rcut, clims = clims)
                frame_path = joinpath(frame_dir, @sprintf("frame_%04d.png", iframe))
                savefig(plt, frame_path)
                push!(frame_paths, frame_path)
            end
            write_html_animation(output_path, frame_paths; title = "3D density diagnostic")
        end
    else
        meta = nearest_snapshot(metas, target_log_lambda, rbhl, cs0)
        data_path = joinpath(output_dir, @sprintf("data.%04d.dbl", meta.index))
        isfile(data_path) || error("Missing $(data_path)")
        rho = read_snapshot_var(data_path, meta, "rho", nx, ny, nz)
        xy, xz = snapshot_values(rho, opts.quantity, x, y, z, dx, dy, dz; mp = mp, rho0 = rho0, xp = xp, yp = yp, zp = zp, rcut = rcut, iy0 = iy0, iz0 = iz0)
        clims = finite_clims([xy, xz]; symmetric = true)
        log_lambda = log(meta.time * cs0 / rbhl)
        plt = plot_slices(x, y, z, xy, xz; quantity = opts.quantity, meta = meta, log_lambda = log_lambda, xp = xp, yp = yp, zp = zp, rsoft = rsoft, rcut = rcut, clims = clims)
        savefig(plt, output_path)
    end

    println("Wrote $(output_path)")
end

main()
