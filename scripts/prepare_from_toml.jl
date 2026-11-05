module TomlSetup

using TOML

const REPO = dirname(@__DIR__)
# Environment name, default and validation rule for each input.
const FIELDS = Dict(
    "physics" => Dict(
        "mach" => ("MACH", 0.1, :nonnegative), "gamma" => ("GAMMA", 1.6666, :gamma),
        "mass" => ("MP", 1.0, :positive), "density" => ("RHO0", 1.0, :positive),
        "sound_speed" => ("CS0", 1.0, :positive)),
    "softening" => Dict("a_soft" => ("A_SOFT", nothing, :positive),
                        "rsoft_frac" => ("RSOFT_FRAC", nothing, :positive)),
    "grid" => Dict("cells_per_rbhl" => ("CELLS_PER_RBHL", 2.0, :positive),
                   "margin_up" => ("MARGIN_UP", 1.2, :positive),
                   "margin_down" => ("MARGIN_DOWN", 1.3, :positive),
                   "margin_y" => ("MARGIN_Y", 1.3, :positive),
                   "upstream_min" => ("UPSTREAM_MIN", 5.0, :positive)),
    "time" => Dict("log_lambda_max" => ("LOG_LAMBDA_MAX", 2.0, :finite),
                   "cfl" => ("CFL", 0.333, :cfl)),
    "output" => Dict("count" => ("N_OUTPUT", 20, :integer),
                     "runs_dir" => ("RUNS_DIR", "../../runs_3d", :path),
                     "subdir" => ("EXPORT_SUBDIR", "export", :subdir)),
    "limits" => Dict("warn_cells" => ("WARN_CELLS", 2000000, :integer),
                     "hard_cells" => ("HARD_CELLS", 8000000, :integer),
                     "min_cells_per_rsoft" => ("MIN_CELLS_PER_RSOFT", 2.0, :positive),
                     "min_boundary_over_rsoft" => ("MIN_BOUNDARY_OVER_RSOFT", 4.0, :positive)),
    "diagnostics" => Dict("sound_speed_threshold" => ("CS_ALERT_THRESHOLD", 1e-6, :nonnegative),
                          "sound_speed_every_steps" => ("CS_ALERT_EVERY_STEPS", 1, :integer),
                          "mach_threshold" => ("MACH_ALERT_THRESHOLD", 0.0, :nonnegative),
                          "mach_every_steps" => ("MACH_ALERT_EVERY_STEPS", 1, :integer)))

function validate(name, value, rule)
    if rule in (:path, :subdir)
        value isa String && !isempty(value) && !occursin(r"[\x00\r\n]", value) ||
            error("$name must be a nonempty path string without control characters")
        if rule == :subdir
            occursin(r"^[A-Za-z0-9_./-]+$", value) && !isabspath(value) &&
                !(".." in split(value, '/')) && normpath(value) != "." ||
                error("$name must be a relative subdirectory without .. or whitespace")
        end
        return
    end
    value isa Real && !(value isa Bool) && isfinite(value) || error("$name must be a finite number")
    rule == :integer && (!(value isa Integer) || value <= 0) && error("$name must be a positive integer")
    rule == :positive && value <= 0 && error("$name must be positive")
    rule == :nonnegative && value < 0 && error("$name must be nonnegative")
    rule == :gamma && value <= 1 && error("$name must exceed 1 for the ideal-gas EOS")
    rule == :cfl && !(0 < value < 1/3) && error("$name must satisfy 0 < CFL < 1/3")
end

function resolve(raw, base)
    version = get(raw, "schema_version", nothing)
    version isa Integer && !(version isa Bool) && version == 1 || error("schema_version must be integer 1")
    unknown = setdiff(keys(raw), union(keys(FIELDS), ["schema_version", "sweep"]))
    isempty(unknown) || error("Unknown top-level keys: $(join(unknown, ", "))")
    resolved = Dict{String,Any}("schema_version" => 1)
    for (table, fields) in FIELDS
        supplied = get(raw, table, Dict())
        supplied isa AbstractDict && isempty(setdiff(keys(supplied), keys(fields))) ||
            error("Invalid or unknown keys in $table")
        resolved[table] = Dict{String,Any}()
        for (key, (_, default, rule)) in fields
            value = get(supplied, key, default)
            if value !== nothing
                validate("$table.$key", value, rule)
                resolved[table][key] = value
            end
        end
    end
    parameter, values = nothing, [nothing]
    if haskey(raw, "sweep")
        sweep = raw["sweep"]
        sweep isa AbstractDict && Set(keys(sweep)) == Set(["parameter", "values"]) ||
            error("sweep requires exactly parameter and values")
        parameter, values = sweep["parameter"], sweep["values"]
        parameter in ("physics.mach", "softening.a_soft") || error("Unsupported sweep parameter")
        values isa AbstractVector && !isempty(values) || error("sweep.values must be a nonempty list")
        table, key = split(parameter, '.')
        haskey(get(raw, table, Dict()), key) && error("$parameter cannot be both fixed and swept")
        for value in values
            validate(parameter, value, FIELDS[table][key][3])
        end
        # Numeric equality must also reject integer/float duplicates (1, 1.0).
        any(values[i] == values[j] for i in eachindex(values) for j in 1:i-1) && error("Duplicate sweep values")
    end
    cases = Dict{String,Any}[]
    for value in values
        case = deepcopy(resolved)
        if parameter !== nothing
            table, key = split(parameter, '.')
            case[table][key] = value
        end
        soft = case["softening"]
        length(soft) <= 1 || error("Specify a_soft or rsoft_frac, not both")
        isempty(soft) && (soft["rsoft_frac"] = 0.25)
        path = expanduser(case["output"]["runs_dir"])
        case["output"]["runs_dir"] = abspath(base, path)
        push!(cases, case)
    end
    return cases
end

function write_effective(path, case, summary, source, revision, dirty)
    record = deepcopy(case)
    record["provenance"] = Dict("source" => source, "revision" => revision, "dirty" => dirty)
    record["derived"] = summary # Preserve generator precision in its original strings.
    open(path, "w") do io
        TOML.print(io, record; sorted=true)
    end
end

function prepare(source)
    source = realpath(source)
    original = read(source, String)
    raw = TOML.parse(original)
    cases = resolve(raw, dirname(source))
    revision = strip(read(Cmd(`git rev-parse HEAD`; dir=REPO), String))
    dirty = !isempty(read(Cmd(`git status --porcelain`; dir=REPO), String))
    excluded = Set(field[1] for fields in values(FIELDS) for field in values(fields))
    env_base = Dict(k => v for (k,v) in ENV if !(k in excluded) && !startswith(k, "SINK_"))
    return mktempdir(; prefix="pluto-toml-") do tmp
        staged = Tuple{String,String}[]
        destinations = Set{String}()
        for (index, case) in enumerate(cases)
            env = copy(env_base)
            for (table, fields) in FIELDS, (key, (variable, _, _)) in fields
                haskey(case[table], key) && (env[variable] = string(case[table][key]))
            end
            env["RUNS_DIR"] = joinpath(tmp, string(index))
            out, err = IOBuffer(), IOBuffer()
            proc = run(pipeline(ignorestatus(setenv(`bash $(joinpath(REPO,"scripts/prepare_one_case_3d.sh"))`, env)), stdout=out, stderr=err))
            print(stderr, String(take!(err)))
            success(proc) || error("Case generation failed; no cases published")
            lines = split(String(take!(out)), '\n')
            line = findfirst(l -> startswith(l, "Prepared "), lines)
            line === nothing && error("Missing generated case path")
            stage = String(chopprefix(lines[line], "Prepared "))
            destination = joinpath(case["output"]["runs_dir"], basename(stage))
            (destination in destinations || ispath(destination) || islink(destination)) &&
                error("Refusing to overwrite or duplicate case: $destination")
            push!(destinations, destination)
            summary = Dict{String,String}()
            for line in eachline(joinpath(stage, "run_summary.txt"))
                key, value = split(line, " = "; limit=2)
                summary[key] = value
            end
            write(joinpath(stage, "setup.original.toml"), original)
            write_effective(joinpath(stage, "setup.effective.toml"), case, summary, source, revision, dirty)
            push!(staged, (stage, destination))
        end
        runs_dir = cases[1]["output"]["runs_dir"]
        mkpath(runs_dir)
        manifest = nothing
        if haskey(raw, "sweep")
            manifest_dir = mkpath(joinpath(runs_dir, "manifests"))
            manifest, io = mktemp(manifest_dir; cleanup=false)
            close(io)
        end
        published = String[]
        for (stage, destination) in staged
            mkdir(destination) # Exclusive reservation against concurrent generation.
            for name in readdir(stage)
                cp(joinpath(stage, name), joinpath(destination, name))
            end
            push!(published, destination)
            if manifest !== nothing
                open(manifest, "a") do io
                    println(io, destination)
                end
            end
            println("Prepared $destination")
        end
        manifest === nothing || println("Wrote manifest $manifest")
        published
    end
end

function main(args=ARGS)
    if args == ["--help"]
        println("Usage: bash scripts/prepare_from_toml.sh SETUP.toml\nPrepare 3D cases only; does not build, run or submit jobs.")
        return 0
    end
    if length(args) != 1
        println(stderr, "Usage: bash scripts/prepare_from_toml.sh SETUP.toml")
        return 1
    end
    try
        prepare(args[1])
        return 0
    catch err
        err isa InterruptException && rethrow()
        println(stderr, "Invalid setup: ", sprint(showerror, err))
        return 1
    end
end

end # module

if abspath(PROGRAM_FILE) == @__FILE__
    exit(TomlSetup.main())
end
