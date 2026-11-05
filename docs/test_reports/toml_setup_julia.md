# TOML setup: Julia test report

- Executed: 2026-11-05T15:29:05.372
- Julia: 1.12.6
- Revision at execution: ef57aa7f5272d637bfa950dfe59d70e38f1a2128
- Uncommitted changes at execution: true
- Command: `julia --startup-file=no tests/test_toml_setup.jl` (optional `--report PATH.md`)
- Result: 29 / 29 scenarios passed.

Each scenario below runs generation or validation checks. No simulation, compiler, MPI or physical-convergence test is run by this suite. Temporary fixtures are deleted after each scenario.

| Result | What was checked |
| --- | --- |
| PASS | 実際のシェル入口から、作業ディレクトリに依存せず単一ケースを生成する |
| PASS | 既定値・空白を含む相対パス・元TOMLの完全保存・実効設定・コード版を確認する |
| PASS | Mach のリスト掃引・manifest・CFL・診断設定を確認する（softening掃引では他の入力が同一） |
| PASS | softening のリスト掃引・manifest・CFL・診断設定を確認する（softening掃引では他の入力が同一） |
| PASS | 不正入力を拒否してケースを作らない：schema_versionのBool |
| PASS | 不正入力を拒否してケースを作らない：未対応schema_version |
| PASS | 不正入力を拒否してケースを作らない：未知のトップレベル項目 |
| PASS | 不正入力を拒否してケースを作らない：未知の物理パラメータ |
| PASS | 不正入力を拒否してケースを作らない：MachへのBool指定 |
| PASS | 不正入力を拒否してケースを作らない：gammaが1以下 |
| PASS | 不正入力を拒否してケースを作らない：質量の非有限値 |
| PASS | 不正入力を拒否してケースを作らない：CFLの上限超過 |
| PASS | 不正入力を拒否してケースを作らない：CFLがゼロ |
| PASS | 不正入力を拒否してケースを作らない：記録間隔が小数 |
| PASS | 不正入力を拒否してケースを作らない：音速閾値が負 |
| PASS | 不正入力を拒否してケースを作らない：softening指定の衝突 |
| PASS | 不正入力を拒否してケースを作らない：撤廃済みsink設定 |
| PASS | 不正入力を拒否してケースを作らない：空のsweepリスト |
| PASS | 不正入力を拒否してケースを作らない：重複sweep値（整数と小数） |
| PASS | 不正入力を拒否してケースを作らない：未対応のsweep軸 |
| PASS | 不正入力を拒否してケースを作らない：固定値とsweepの衝突 |
| PASS | 出力サブディレクトリを検証し拒否する：../escape |
| PASS | 出力サブディレクトリを検証し拒否する：/tmp/escape |
| PASS | 出力サブディレクトリを検証し拒否する：. |
| PASS | 出力サブディレクトリを検証し拒否する：with spaces |
| PASS | 後続sweepケースが生成失敗した場合、先行ケースも公開しない |
| PASS | 既存ケースを上書きせず、元の設定ファイルを保存する |
| PASS | 丸めたケース名が衝突するsweepを、公開前に拒否する |
| PASS | 共有TOML例3ファイルがすべて読み込み・設定解決できる |
