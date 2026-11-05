# Standard-library-only integration checks with a persistent, readable report.
using TOML, Dates
include(joinpath(@__DIR__, "..", "scripts", "prepare_from_toml.jl"))
const TS = TomlSetup
const RESULTS = NamedTuple[]

function verify(f, description)
    started = time()
    try
        f()
        push!(RESULTS, (; description, passed=true, detail="", seconds=time()-started))
        println("PASS: ", description)
    catch err
        detail = sprint(showerror, err)
        push!(RESULTS, (; description, passed=false, detail, seconds=time()-started))
        println("FAIL: ", description, " — ", detail)
    end
end

base(extra="") = "schema_version = 1\n[output]\nruns_dir = \"runs with spaces\"\n" * extra

# Complete fixture with every common setting explicit, like a user's sweep file.
function full_sweep(body)
    raw = TOML.parse(body)
    table, key = split(raw["sweep"]["parameter"], '.')
    for (section, fields) in TS.FIELDS
        section == "softening" && continue
        settings = get!(raw, section, Dict{String,Any}())
        for (field, (_, default, _)) in fields
            section == table && field == key && continue
            get!(settings, field, default)
        end
    end
    if table != "softening"
        get!(raw, "softening", Dict("a_soft"=>1.0))
    end
    io = IOBuffer(); TOML.print(io, raw); return String(take!(io))
end

function run_config(root, body; ok=true, extra=Dict{String,String}(), repo=TS.REPO)
    source = joinpath(root, "input.toml")
    write(source, body)
    output, errorlog = joinpath(root, "stdout.txt"), joinpath(root, "stderr.txt")
    passed = true
    open(output, "w") do out
        open(errorlog, "w") do err
            redirect_stdout(out) do
                redirect_stderr(err) do
                    withenv(collect(pairs(extra))...) do
                        try
                            TS.prepare(source; repo)
                        catch exception
                            exception isa InterruptException && rethrow()
                            passed = false
                            println(stderr, sprint(showerror, exception))
                        end
                    end
                end
            end
        end
    end
    captured_output, captured_error = read(output, String), read(errorlog, String)
    @assert passed == ok "Unexpected generation status: $captured_error"
    cases = [String(chopprefix(l, "Prepared ")) for l in split(captured_output, '\n') if startswith(l, "Prepared ")]
    return (; stdout=captured_output, stderr=captured_error, cases)
end

function normalized_ini(path)
    [[something(tryparse(Float64, token), token) for token in split(line)] for line in readlines(path)]
end

function tests()
    for mode in (:no_checkout, :no_git, :git_failure)
        verify("Git情報がなくても直接生成でき、未取得と記録する：$mode") do
            mktempdir() do root
                repo = TS.REPO
                extra = Dict{String,String}()
                if mode == :no_checkout
                    repo = mkpath(joinpath(root,"copied-repo"))
                    mkpath(joinpath(repo,"scripts"))
                    for file in ("definitions_3d.h","init_3d.c","makefile","local_make","scripts/prepare_one_case_3d.sh")
                        cp(joinpath(TS.REPO,file),joinpath(repo,file))
                    end
                else
                    bin = mkpath(joinpath(root,"bin"))
                    for tool in ("bash","awk","mkdir","cp","dirname","cat")
                        symlink(Sys.which(tool),joinpath(bin,tool))
                    end
                    if mode == :git_failure
                        write(joinpath(bin,"git"),"#!/bin/sh\nexit 128\n")
                        chmod(joinpath(bin,"git"),0o755)
                    end
                    extra["PATH"] = bin
                end
                # If staging is accidentally reintroduced, this invalid TMPDIR fails.
                extra["TMPDIR"] = joinpath(root,"no-temporary-area")
                result = run_config(root,base("[time]\nlog_lambda_max = 0.1\n"); extra,repo)
                case = only(result.cases)
                @assert dirname(case) == joinpath(root,"runs with spaces")
                provenance = TOML.parsefile(joinpath(case,"setup.effective.toml"))["provenance"]
                @assert provenance["metadata_available"] == false
                @assert provenance["revision"] == "unavailable"
                @assert provenance["dirty"] == "unknown"
                @assert occursin("Git metadata unavailable",result.stderr)
            end
        end
    end
    verify("sweepの共通設定を一項目ずつ省略し、全項目が生成前に拒否されることを確認する") do
        mktempdir() do root
            complete = TOML.parse(full_sweep(base("[sweep]\nparameter = \"physics.mach\"\nvalues = [0.1, 0.5]")))
            for (section, fields) in TS.FIELDS, field in keys(fields)
                section == "softening" && continue
                section == "physics" && field == "mach" && continue
                raw = deepcopy(complete)
                delete!(raw[section],field)
                io=IOBuffer(); TOML.print(io,raw)
                result=run_config(root,String(take!(io));ok=false)
                @assert occursin("$section.$field",result.stderr)
                @assert !ispath(joinpath(root,"runs with spaces"))
            end
        end
    end
    verify("sweepの不足項目をまとめて表示し、softeningの片方指定を必須にする") do
        mktempdir() do root
            result=run_config(root,base("[sweep]\nparameter = \"physics.mach\"\nvalues = [0.1]");ok=false)
            for name in ("physics.gamma","output.count","grid.cells_per_rbhl","diagnostics.mach_threshold","softening.a_soft or softening.rsoft_frac")
                @assert occursin(name,result.stderr)
            end
            @assert !ispath(joinpath(root,"runs with spaces"))
            raw=TOML.parse(full_sweep(base("[sweep]\nparameter = \"physics.mach\"\nvalues = [0.1]")))
            raw["softening"]=Dict("rsoft_frac"=>0.25)
            io=IOBuffer();TOML.print(io,raw)
            @assert length(run_config(root,String(take!(io))).cases)==1
        end
    end
    verify("実際のシェル入口から、作業ディレクトリに依存せず単一ケースを生成する") do
        mktempdir() do root
            source = joinpath(root, "input.toml")
            write(source, base("[time]\nlog_lambda_max = 0.1\n"))
            cmd = Cmd(`bash $(joinpath(TS.REPO,"scripts/prepare_from_toml.sh")) $source`; dir="/tmp")
            out = read(cmd, String)
            @assert occursin("Prepared ", out)
            @assert isdir(joinpath(root, "runs with spaces"))
        end
    end
    verify("既定値・空白を含む相対パス・元TOMLの完全保存・実効設定・コード版を確認する") do
        mktempdir() do root
            body = base("[time]\nlog_lambda_max = 0.1\n")
            result = run_config(root, body; extra=Dict("MACH"=>"wrong", "A_SOFT"=>"wrong",
                "SINK_RADIUS"=>"9", "CFL"=>"9", "RUNS_DIR"=>"/not/used", "RSOFT_FRAC"=>"wrong"))
            case = only(result.cases)
            @assert dirname(case) == joinpath(root, "runs with spaces")
            @assert read(joinpath(case, "setup.original.toml"), String) == body
            effective = TOML.parsefile(joinpath(case, "setup.effective.toml"))
            @assert effective["physics"]["mach"] == 0.1
            @assert effective["softening"] == Dict("rsoft_frac"=>0.25)
            @assert effective["time"]["cfl"] == 0.333
            @assert effective["diagnostics"]["mach_threshold"] == 0
            @assert length(effective["provenance"]["revision"]) == 40
            @assert effective["provenance"]["dirty"] isa Bool
            @assert haskey(effective["derived"], "rbhl")
            @assert !haskey(effective["derived"], "sink_radius")
            # Compare full generated inputs numerically, ignoring float spelling.
            env = Dict(k=>v for (k,v) in ENV if k in ("PATH", "HOME"))
            env["RUNS_DIR"] = joinpath(root, "legacy")
            env["LOG_LAMBDA_MAX"] = "0.1"
            out = read(setenv(`bash $(joinpath(TS.REPO,"scripts/prepare_one_case_3d.sh"))`, env), String)
            legacy = strip(chopprefix(strip(out), "Prepared "))
            @assert normalized_ini(joinpath(case,"pluto.ini")) == normalized_ini(joinpath(legacy,"pluto.ini"))
        end
    end
    for (parameter, values, table, label) in [
        ("physics.mach", "[0.1, 0.5]", "[softening]\na_soft = 1.0\n", "Mach"),
        ("softening.a_soft", "[2.0, 1.0]", "[physics]\nmach = 0.5\n", "softening")]
        verify("$label のリスト掃引・manifest・CFL・診断設定を確認する（softening掃引では他の入力が同一）") do
            mktempdir() do root
                body = base("count = 3\n" * table * """
                [time]
                log_lambda_max = 0.1
                cfl = 0.2
                [diagnostics]
                sound_speed_threshold = 2.0
                sound_speed_every_steps = 3
                mach_threshold = 0.1
                mach_every_steps = 5
                [sweep]
                parameter = "$parameter"
                values = $values
                """)
                result = run_config(root, full_sweep(body))
                @assert length(result.cases) == 2
                manifest = only([chopprefix(l,"Wrote manifest ") for l in split(result.stdout,'\n') if startswith(l,"Wrote manifest ")])
                @assert readlines(manifest) == result.cases
                for case in result.cases
                    ini = read(joinpath(case,"pluto.ini"), String)
                    @assert occursin("CFL              0.2", ini)
                    @assert occursin("MACH_ALERT_EVERY_STEPS      5", ini)
                    @assert occursin("CS_ALERT_THRESHOLD          2.0", ini)
                end
                if label == "softening"
                    filtered(p) = filter(l -> !startswith(l,"RSOFT "), readlines(joinpath(p,"pluto.ini")))
                    @assert filtered(result.cases[1]) == filtered(result.cases[2])
                end
            end
        end
    end
    invalid = [
        "schema_versionのBool" => "schema_version = true",
        "未対応schema_version" => "schema_version = 2",
        "未知のトップレベル項目" => "schema_version = 1\nunknown = 2",
        "未知の物理パラメータ" => base("[physics]\nunknown = 2"),
        "MachへのBool指定" => base("[physics]\nmach = true"),
        "gammaが1以下" => base("[physics]\ngamma = 1.0"),
        "質量の非有限値" => base("[physics]\nmass = inf"),
        "CFLの上限超過" => base("[time]\ncfl = 0.4"),
        "CFLがゼロ" => base("[time]\ncfl = 0.0"),
        "記録間隔が小数" => base("[diagnostics]\nmach_every_steps = 1.5"),
        "音速閾値が負" => base("[diagnostics]\nsound_speed_threshold = -1.0"),
        "softening指定の衝突" => base("[softening]\na_soft = 1.0\nrsoft_frac = 0.25"),
        "撤廃済みsink設定" => base("[sink]\nradius = 0.0"),
        "空のsweepリスト" => base("[sweep]\nparameter = \"physics.mach\"\nvalues = []"),
        "重複sweep値（整数と小数）" => base("[sweep]\nparameter = \"physics.mach\"\nvalues = [1, 1.0]"),
        "未対応のsweep軸" => base("[sweep]\nparameter = \"physics.mass\"\nvalues = [1,2]"),
        "固定値とsweepの衝突" => base("[physics]\nmach = 0.5\n[sweep]\nparameter = \"physics.mach\"\nvalues = [0.1]"),
    ]
    for (description, body) in invalid
        verify("不正入力を拒否してケースを作らない：$description") do
            mktempdir() do root
                run_config(root, body; ok=false)
                @assert !ispath(joinpath(root, "runs with spaces"))
            end
        end
    end
    for subdir in ("../escape", "/tmp/escape", ".", "with spaces")
        verify("出力サブディレクトリを検証し拒否する：$subdir") do
            mktempdir() do root
                run_config(root, base("subdir = \"$subdir\""); ok=false)
                @assert !ispath(joinpath(root,"runs with spaces"))
            end
        end
    end
    verify("後続sweepの生成失敗でも、指定先の成功済みケースとmanifestを保持する") do
        mktempdir() do root
            body = full_sweep(base("[time]\nlog_lambda_max = 0.1\n[sweep]\nparameter = \"physics.mach\"\nvalues = [0.1, 1000000.0]"))
            result = run_config(root, body; ok=false)
            @assert length(result.cases) == 1
            @assert isfile(joinpath(only(result.cases),"setup.effective.toml"))
            manifest = only(readdir(joinpath(root,"runs with spaces/manifests"); join=true))
            @assert readlines(manifest) == result.cases
            @assert occursin("1 successful cases retained", result.stderr)
        end
    end
    verify("既存ケースを上書きせず、元の設定ファイルを保存する") do
        mktempdir() do root
            body = base("[time]\nlog_lambda_max = 0.1\n")
            case = only(run_config(root,body).cases)
            saved = read(joinpath(case,"setup.original.toml"))
            result = run_config(root,body; ok=false)
            @assert occursin("Refusing to overwrite", result.stderr)
            @assert read(joinpath(case,"setup.original.toml")) == saved
        end
    end
    verify("丸めたケース名の衝突時、先行ケースを上書きせずmanifestに保持する") do
        mktempdir() do root
            result = run_config(root,full_sweep(base("[time]\nlog_lambda_max = 0.1\n[sweep]\nparameter = \"physics.mach\"\nvalues = [0.10001, 0.10002]")); ok=false)
            @assert length(result.cases) == 1
            manifest = only(readdir(joinpath(root,"runs with spaces/manifests"); join=true))
            @assert readlines(manifest) == result.cases
        end
    end
    verify("共有TOML例3ファイルがすべて読み込み・設定解決できる") do
        paths = filter(p -> endswith(p,".toml"), readdir(joinpath(TS.REPO,"configs/examples");join=true))
        @assert length(paths) == 3
        for path in paths
            @assert !isempty(TS.resolve(TOML.parsefile(path), dirname(path)))
        end
    end
end

function main(args)
    report = joinpath(TS.REPO,"docs/test_reports/toml_setup_julia.md")
    if !isempty(args)
        length(args) == 2 && args[1] == "--report" || error("Usage: julia tests/test_toml_setup.jl [--report PATH.md]")
        report = abspath(args[2])
    end
    started = now()
    tests()
    passed = count(r -> r.passed, RESULTS)
    mkpath(dirname(report))
    open(report,"w") do io
        println(io,"# TOML setup: Julia test report\n")
        println(io,"- Executed: $started\n- Julia: $VERSION")
        provenance = TS.code_provenance()
        println(io,"- Revision at execution: ",provenance["revision"])
        println(io,"- Uncommitted changes at execution: ",provenance["dirty"])
        println(io,"- Command: `julia --startup-file=no tests/test_toml_setup.jl` (optional `--report PATH.md`)")
        println(io,"- Result: $passed / $(length(RESULTS)) scenarios passed.\n")
        println(io,"Each scenario below runs generation or validation checks. No simulation, compiler, MPI or physical-convergence test is run by this suite. Temporary fixtures are deleted after each scenario.\n")
        println(io,"| Result | What was checked |\n| --- | --- |")
        for result in RESULTS
            println(io,"| ",result.passed ? "PASS" : "FAIL"," | ",result.description," |")
            isempty(result.detail) || println(io,"\nFailure: ",strip(replace(result.detail,'\n'=>" ")),"\n")
        end
    end
    println("$passed / $(length(RESULTS)) scenarios passed; report: $report")
    return passed == length(RESULTS) ? 0 : 1
end

exit(main(ARGS))
