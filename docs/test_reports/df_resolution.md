# DF resolution table: Julia verification report

- Executed: 2026-11-16T18:52:58.380 (local time)
- Julia: 1.12.6
- Revision at execution: 0888070fc9e1cdfb8604199c673faee6bb3fdc8e
- Uncommitted changes at execution: true
- Command: `julia --startup-file=no scripts/verify_df_resolution.jl` (optional `--report PATH.md`)
- Result: 18 / 18 scenarios passed.

Synthetic Cartesian PLUTO grids, settings and binary snapshots test the real collector CLI and its integral against an analytic excess-cell force and the existing one-case CLI. The existing radial-force (69 assertions) and alpha-profile (51 assertions) suites are also executed as separate Julia processes. Temporary fixtures are removed after each scenario.

No PLUTO compilation/evolution, production-data analysis, remote command, MPI/Slurm run, plot rendering or physical-convergence check was performed. No drawing package, gnuplot or Python is required or executed.

| Result | What was checked |
| --- | --- |
| PASS | 単一過剰セルの解析解・符号・規格化、カットオフ境界と中心セル除外、既存CLIとの一致 |
| PASS | 一様密度のゼロDFと上流過剰密度の負DF、密度以外の非有限値は無関係 |
| PASS | 複数解像度・任意A_softを数値順に横持ち出力し、実際の解像度・時刻・パスを保持 |
| PASS | 初期出力のみ・未開始・未到達はNaNとし、全欠測行を省き、欠けた組合せも保持 |
| PASS | 保存時刻の丸めを許容して終端を採用し、到達後の最近傍log時刻を使う |
| PASS | 直下だけを探索し、manifest・無関係なディレクトリ・下位階層の異なるMachを無視 |
| PASS | Machは値を固定せず一致を要求し、不一致時は出力しない |
| PASS | 同じ解像度・A_softの重複を拒否し、未到達でも任意選択しない |
| PASS | 同じ目標解像度でA_soft間の実解像度が異なる場合と、目標だけ異なる重複を拒否 |
| PASS | 設定記録の欠落・破損・非有限値・非3D・解像度記録の不整合を拒否 |
| PASS | big endian・rhoが先頭でない出力を既存の密度読取処理で正しく集計 |
| PASS | 出力メタデータの破損・未対応形式・欠落ファイル・サイズ異常を未到達と混同しない |
| PASS | 選択した密度のNaN・無限値・負値を拒否 |
| PASS | 既存.datは解析前に保護し、--force/-fのみ上書き、集計失敗時は既存内容を保持 |
| PASS | 出力先はcwd基準で指定でき、解析中に出現した既存ファイルも排他作成で保護 |
| PASS | 不正CLI・全未到達・空入力・不正保存先では非ゼロ終了し、新規出力を作らない |
| PASS | 既存Julia数値回帰スイート：test_force_radial_profile_3d.jl |
| PASS | 既存Julia数値回帰スイート：test_alpha_profile_3d.jl |
