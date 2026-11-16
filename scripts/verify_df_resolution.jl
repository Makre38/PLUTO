# Standard-library-only scenarios; kept here because new tests/ files are ignored.
using Test, Printf, Dates
include(joinpath(@__DIR__, "..", "collect_df_resolution_3d.jl"))
const DF = DFResolution3D
const REPO = dirname(@__DIR__)
const SCRIPT = joinpath(REPO, "collect_df_resolution_3d.jl")
const RESULTS = NamedTuple[]

function verify(f, description)
    try
        @testset "$description" begin
            f()
        end
        push!(RESULTS, (; description, passed=true, detail=""))
        println("PASS: $description")
    catch err
        err isa InterruptException && rethrow()
        detail = sprint(showerror, err, catch_backtrace())
        push!(RESULTS, (; description, passed=false, detail))
        println("FAIL: $description — $detail")
    end
end

function fixture(root, name; nx=4, target=nx/4-0.1, a=1.0, mach=1.3,
                 logs=[-1.0, 0.0, 1.0], amplitude=1.0, side=:downstream,
                 endian="little", subdir="export")
    path = mkpath(joinpath(root, name))
    out = mkpath(joinpath(path, subdir))
    mp, cs0, rho0, rbhl = 10.76, 2.0, 3.0, 1.0
    write(joinpath(path, "run_summary.txt"), """
    dimension = 3
    mach = $mach
    a_soft = $a
    r_bondi = 2.69
    rsoft = $(2.69/a)
    rbhl = $rbhl
    mp = $mp
    cs0 = $cs0
    rho0 = $rho0
    gamma = 1.6666
    cells_per_rbhl_target = $target
    cells_per_rbhl_x = $(nx/4)
    dx_actual = $(4/nx)
    x1p = 0.5
    x2p = 0.5
    x3p = 0.5
    output_subdir = $subdir
    log_lambda_max = 1.0
    """)
    write(joinpath(path, "pluto.ini"), "# discovery marker\n")
    edges = [collect(range(-2.0, 2.0; length=nx+1)), [-1.0,0.0,1.0], [-1.0,0.0,1.0]]
    open(joinpath(out, "grid.out"), "w") do io
        println(io, "# synthetic 3D Cartesian grid")
        for axis in edges
            println(io, length(axis)-1)
            for i in 1:length(axis)-1
                println(io, "$i $(axis[i]) $(axis[i+1])")
            end
        end
    end
    # Independent analytic force: one excess cell, aligned with the perturber.
    bump = side == :downstream ? nx : 1
    rx = (edges[1][bump]+edges[1][bump+1])/2 - 0.5
    dx = 4/nx
    open(joinpath(out, "dbl.out"), "w") do io
        for (idx, log_value) in enumerate([nothing; logs])
            index = idx-1
            t = log_value === nothing ? 0.0 : exp(log_value)/cs0
            @printf(io, "%d %.6e 1.000000e-04 %d single_file %s vx1 rho prs\n",
                    index, t, index, endian)
            rho = fill(rho0, nx, 2, 2)
            rho[bump,2,2] += amplitude * index
            # At nx=4 this cell is exactly on the perturber: exclude it even
            # with a large density. The bump at +x is exactly on r_cut=1.
            nx == 4 && (rho[3,2,2] = 1000.0)
            words = reinterpret(UInt64, [fill(NaN, length(rho)); vec(rho); fill(Inf, length(rho))])
            convert = endian == "big" ? hton : htol
            write(joinpath(out, @sprintf("data.%04d.dbl", index)), convert.(words))
        end
    end
    expected_raw(index) = abs(rx) < rbhl ? 0.0 : mp*amplitude*index*dx*rx/abs(rx)^3
    return (; path, out, expected_raw, norm=4π*rho0*mp^2/cs0^2)
end

function replace_text(path, from, to)
    content = read(path, String)
    @assert occursin(from, content)
    write(path, replace(content, from=>to))
end

function rows(path)
    [parse.(Float64, split(line)) for line in eachline(path)
     if !isempty(strip(line)) && !startswith(strip(line), '#')]
end

function cli(args; script=SCRIPT)
    out, err = IOBuffer(), IOBuffer()
    process = run(pipeline(ignorestatus(`$(Base.julia_cmd()) --startup-file=no $script $args`),
                           stdout=out, stderr=err))
    return (; ok=success(process), stdout=String(take!(out)), stderr=String(take!(err)))
end

function failure(f, text)
    caught = try
        f()
        nothing
    catch err
        err
    end
    @test caught isa Exception
    caught === nothing || @test occursin(text, sprint(showerror, caught))
end

function scenarios()
    verify("単一過剰セルの解析解・符号・規格化、カットオフ境界と中心セル除外、既存CLIとの一致") do
        mktempdir() do root
            f = fixture(root, "case with spaces"; subdir="saved data")
            t = DF.collect_table(root, 0.7)
            record = only(t.records).result
            @test record.meta.index == 3
            @test record.fx ≈ f.expected_raw(3) rtol=1e-13
            @test record.df ≈ f.expected_raw(3)/f.norm rtol=1e-13
            @test t.resolutions == [1.0] # not target=0.9
            old = cli([f.path, "0.7"]; script=joinpath(REPO,"force_from_run.jl"))
            @test old.ok
            fx = parse(Float64, match(r"^Fdf = (\S+)"m, old.stdout).captures[1])
            @test record.fx ≈ fx rtol=1e-11
            @test !isdefined(DF, :Plots) && !isdefined(DF, :Makie)
        end
    end
    verify("一様密度のゼロDFと上流過剰密度の負DF、密度以外の非有限値は無関係") do
        mktempdir() do root
            fixture(root,"uniform"; nx=8, a=0.5, amplitude=0)
            f = fixture(root,"upstream"; nx=8, a=1.0, side=:upstream)
            t = DF.collect_table(root,0.0)
            @test t.values[1,1] == 0.0
            @test t.values[1,2] < 0
            @test t.values[1,2] ≈ f.expected_raw(2)/f.norm
        end
    end
    verify("複数解像度・任意A_softを数値順に横持ち出力し、実際の解像度・時刻・パスを保持") do
        mktempdir() do root
            for (name,nx,a) in (("z",8,2.0),("b",4,0.5),("a",8,0.5),("c",4,2.0))
                fixture(root,name; nx,a)
            end
            path = joinpath(root,"df_resolution_loglambda_0.0.dat")
            @test DF.main([root,"0"]) == 0
            data = rows(path)
            @test length(data) == 2
            @test first.(data) == [1.0,2.0]
            @test all(length(r)==3 for r in data)
            text = read(path,String)
            @test occursin("# R_BHL_over_dx DF_A0.5 DF_A2.0",text)
            @test occursin("actual_log_lambda=0.0",text)
            @test occursin("target_resolution=0.9 actual_resolution=1.0",text)
            @test occursin("run_dir=",text) && occursin("normalization=",text)
            @test Set(readdir(root)) == Set(["z","b","a","c",basename(path)])
        end
    end
    verify("初期出力のみ・未開始・未到達はNaNとし、全欠測行を省き、欠けた組合せも保持") do
        mktempdir() do root
            fixture(root,"ready"; a=0.5)
            fixture(root,"initial_only"; a=1.0, logs=Float64[])
            f = fixture(root,"not_started"; a=1.5)
            for file in readdir(f.out;join=true)
                rm(file)
            end
            fixture(root,"short"; nx=8,a=0.5,logs=[-2.0,-1.0])
            t = DF.collect_table(root,0.5)
            @test t.a_values == [0.5,1.0,1.5]
            @test t.rows == [1]
            @test isfinite(t.values[1,1])
            @test all(isnan,t.values[1,2:3])
            @test isnan(t.values[2,2]) # absent case
            @test occursin("NaN NaN",DF.render_table(t))
            @test count(r->r.result===nothing,t.records) == 3
        end
    end
    verify("保存時刻の丸めを許容して終端を採用し、到達後の最近傍log時刻を使う") do
        mktempdir() do root
            fixture(root,"case")
            @test only(DF.collect_table(root,1.0).records).result.meta.index == 3
            @test only(DF.collect_table(root,-0.8).records).result.meta.index == 1
            @test only(DF.collect_table(root,0.6).records).result.meta.index == 3
            failure(()->DF.collect_table(root,1.01),"No cases have reached")
        end
    end
    verify("直下だけを探索し、manifest・無関係なディレクトリ・下位階層の異なるMachを無視") do
        mktempdir() do root
            fixture(root,"direct")
            fixture(mkpath(joinpath(root,"nested")),"hidden";mach=9.0)
            mkpath(joinpath(root,"manifests"))
            @test length(DF.discover(root)) == 1
            @test DF.main([root,"0"]) == 0
        end
    end
    verify("Machは値を固定せず一致を要求し、不一致時は出力しない") do
        mktempdir() do root
            fixture(root,"one";a=0.5,mach=0.8)
            fixture(root,"two";a=1.0,mach=0.8)
            @test first(DF.collect_table(root,0.0).cases).mach == 0.8
            replace_text(joinpath(root,"two/run_summary.txt"),"mach = 0.8","mach = 1.3")
            failure(()->DF.collect_table(root,0.0),"Mach differs")
            @test DF.main([root,"0"]) == 1
            @test !isfile(joinpath(root,"df_resolution_loglambda_0.0.dat"))
        end
    end
    verify("同じ解像度・A_softの重複を拒否し、未到達でも任意選択しない") do
        mktempdir() do root
            fixture(root,"one")
            fixture(root,"two";logs=Float64[])
            failure(()->DF.collect_table(root,0.0),"Duplicate resolution/A_soft")
        end
    end
    verify("同じ目標解像度でA_soft間の実解像度が異なる場合と、目標だけ異なる重複を拒否") do
        mktempdir() do root
            fixture(root,"one";a=0.5)
            fixture(root,"two";a=1.0,nx=8,target=0.9)
            failure(()->DF.collect_table(root,0.0),"Actual R_BHL/dx differs")
        end
        mktempdir() do root
            fixture(root,"one";a=0.5)
            fixture(root,"two";a=1.0,target=0.8)
            failure(()->DF.collect_table(root,0.0),"same actual R_BHL/dx")
        end
    end
    verify("設定記録の欠落・破損・非有限値・非3D・解像度記録の不整合を拒否") do
        for (from,to,text) in (("a_soft = 1.0","other = 1.0","a_soft"),
                               ("mp = 10.76","mp = NaN","mp"),
                               ("dimension = 3","dimension = 2","Only 3D"),
                               ("dx_actual = 1.0","dx_actual = 2.0","disagrees"),
                               ("gamma = 1.6666","broken line","Malformed"),
                               ("gamma = 1.6666","mach = 1.3","duplicate"))
            mktempdir() do root
                f = fixture(root,"case")
                replace_text(joinpath(f.path,"run_summary.txt"),from,to)
                failure(()->DF.collect_table(root,0.0),text)
            end
        end
        mktempdir() do root
            f = fixture(root,"case")
            rm(joinpath(f.path,"run_summary.txt"))
            failure(()->DF.discover(root),"Missing")
        end
    end
    verify("big endian・rhoが先頭でない出力を既存の密度読取処理で正しく集計") do
        mktempdir() do root
            f = fixture(root,"case";endian="big")
            @test only(DF.collect_table(root,0.0).records).result.fx ≈ f.expected_raw(2)
        end
    end
    verify("出力メタデータの破損・未対応形式・欠落ファイル・サイズ異常を未到達と混同しない") do
        mutations = [
            f->replace_text(joinpath(f.out,"dbl.out"),"single_file","multiple_files"),
            f->replace_text(joinpath(f.out,"dbl.out"),"little","unknown"),
            f->replace_text(joinpath(f.out,"dbl.out"),"vx1 rho prs","vx1 vx2 prs"),
            f->write(joinpath(f.out,"dbl.out"),"invalid\n"),
            f->rm(joinpath(f.out,"grid.out")),
            f->rm(joinpath(f.out,"data.0002.dbl")),
            f->open(io->write(io,UInt8(0)),joinpath(f.out,"data.0002.dbl"),"a"),
            f->replace_text(joinpath(f.out,"grid.out"),"1 -2.0 -1.0","1 -2.0 -1.1"),
        ]
        for mutate in mutations
            mktempdir() do root
                f = fixture(root,"case")
                mutate(f)
                failure(()->DF.collect_table(root,0.0),"")
            end
        end
    end
    verify("選択した密度のNaN・無限値・負値を拒否") do
        for bad in (NaN,Inf,-1.0)
            mktempdir() do root
                f = fixture(root,"case")
                open(joinpath(f.out,"data.0002.dbl"),"r+") do io
                    seek(io,8*16) # skip vx1; first density cell
                    write(io,htol(reinterpret(UInt64,bad)))
                end
                failure(()->DF.collect_table(root,0.0),"density")
            end
        end
    end
    verify("既存.datは解析前に保護し、--force/-fのみ上書き、集計失敗時は既存内容を保持") do
        mktempdir() do root
            f = fixture(root,"case")
            output = joinpath(root,"existing table.dat")
            write(output,"sentinel\n")
            rm(joinpath(f.out,"data.0002.dbl"))
            result = cli([root,"0","--output",output])
            @test !result.ok && occursin("Output exists",result.stderr)
            @test read(output,String) == "sentinel\n"
            @test !cli([root,"0","--output",output,"-f"]).ok
            @test read(output,String) == "sentinel\n"
            fixture(root,"case")
            @test cli([root,"0","--output",output,"--force"]).ok
            @test length(rows(output)) == 1
            write(output,"sentinel again\n")
            @test cli([root,"0","--output",output,"-f"]).ok
            @test length(rows(output)) == 1
        end
    end
    verify("出力先はcwd基準で指定でき、解析中に出現した既存ファイルも排他作成で保護") do
        mktempdir() do root
            inputs = mkpath(joinpath(root,"inputs"))
            fixture(inputs,"case")
            cd(root) do
                @test DF.main(["inputs","-0.5","--output=relative.dat"]) == 0
                @test isfile(joinpath(root,"relative.dat"))
                @test !isfile(joinpath(inputs,"relative.dat"))
            end
            path = joinpath(root,"race.dat")
            DF.check_destination(path,false)
            write(path,"appeared during analysis")
            failure(()->DF.write_table(path,"replacement",false),"Output exists")
            @test read(path,String) == "appeared during analysis"
            link = joinpath(root,"link.dat")
            symlink(path,link)
            failure(()->DF.check_destination(link,true),"symbolic-link")
            @test read(path,String) == "appeared during analysis"
        end
    end
    verify("不正CLI・全未到達・空入力・不正保存先では非ゼロ終了し、新規出力を作らない") do
        for args in (String[],["run"],["run","NaN"],["run","Inf"],
                     ["run","0","--unknown"],["run","0","--output"],
                     ["run","0","--output","a.dat","--output=b.dat"])
            @test DF.main(args) == 1
        end
        @test cli(["--help"]).ok
        mktempdir() do root
            @test DF.main([root,"0"]) == 1
            fixture(root,"case";logs=[-1.0])
            @test !cli([root,"0"]).ok
            @test !isfile(joinpath(root,"df_resolution_loglambda_0.0.dat"))
            @test DF.main([root,"-1","--output",joinpath(root,"data.dbl")]) == 1
            @test DF.main([root,"-1","--output",joinpath(root,"missing","table.dat")]) == 1
        end
    end
    for file in ("test_force_radial_profile_3d.jl","test_alpha_profile_3d.jl")
        verify("既存Julia数値回帰スイート：$file") do
            result = cli(String[];script=joinpath(REPO,"tests",file))
            @test result.ok
            result.ok || error(result.stdout * result.stderr)
        end
    end
end

function main(args)
    report = joinpath(REPO,"docs/test_reports/df_resolution.md")
    if !isempty(args)
        length(args)==2 && args[1]=="--report" || error("Usage: julia scripts/verify_df_resolution.jl [--report PATH.md]")
        report = abspath(args[2])
    end
    started = now()
    scenarios()
    passed = count(r->r.passed,RESULTS)
    revision = try
        strip(read(Cmd(`git rev-parse HEAD`;dir=REPO),String))
    catch
        "unavailable"
    end
    dirty = try
        !isempty(read(Cmd(`git status --porcelain`;dir=REPO),String))
    catch
        "unknown"
    end
    mkpath(dirname(report))
    open(report,"w") do io
        println(io,"# DF resolution table: Julia verification report\n")
        println(io,"- Executed: $started (local time)\n- Julia: $VERSION\n- Revision at execution: $revision\n- Uncommitted changes at execution: $dirty")
        println(io,"- Command: `julia --startup-file=no scripts/verify_df_resolution.jl` (optional `--report PATH.md`)")
        println(io,"- Result: $passed / $(length(RESULTS)) scenarios passed.\n")
        println(io,"Synthetic Cartesian PLUTO grids, settings and binary snapshots test the real collector CLI and its integral against an analytic excess-cell force and the existing one-case CLI. The existing radial-force (69 assertions) and alpha-profile (51 assertions) suites are also executed as separate Julia processes. Temporary fixtures are removed after each scenario.\n")
        println(io,"No PLUTO compilation/evolution, production-data analysis, remote command, MPI/Slurm run, plot rendering or physical-convergence check was performed. No drawing package, gnuplot or Python is required or executed.\n")
        println(io,"| Result | What was checked |\n| --- | --- |")
        for r in RESULTS
            println(io,"| $(r.passed ? "PASS" : "FAIL") | $(r.description) |")
        end
        for r in RESULTS
            if !r.passed
                println(io,"\nFailure: $(r.description)\n\n```text\n$(r.detail)\n```")
            end
        end
    end
    println("$passed / $(length(RESULTS)) scenarios passed; report: $report")
    return passed == length(RESULTS) ? 0 : 1
end

exit(main(ARGS))
