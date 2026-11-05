# TOML setup: Julia test report

- Executed: 2026-11-05T17:41:03.109
- Julia: 1.12.6
- Revision at execution: c21ec7fe48cc4ba76395027ea43df590608f4da2
- Uncommitted changes at execution: true
- Command: `julia --startup-file=no tests/test_toml_setup.jl` (optional `--report PATH.md`)
- Result: 34 / 34 scenarios passed.

Each scenario below runs generation or validation checks. No simulation, compiler, MPI or physical-convergence test is run by this suite. Temporary fixtures are deleted after each scenario.

| Result | What was checked |
| --- | --- |
| PASS | Git情報がなくても直接生成でき、未取得と記録する：no_checkout |
| PASS | Git情報がなくても直接生成でき、未取得と記録する：no_git |
| PASS | Git情報がなくても直接生成でき、未取得と記録する：git_failure |
| PASS | sweepの共通設定を一項目ずつ省略し、全項目が生成前に拒否されることを確認する |
| PASS | sweepの不足項目をまとめて表示し、softeningの片方指定を必須にする |
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
| PASS | 後続sweepの生成失敗でも、指定先の成功済みケースとmanifestを保持する |
| PASS | 既存ケースを上書きせず、元の設定ファイルを保存する |
| PASS | 丸めたケース名の衝突時、先行ケースを上書きせずmanifestに保持する |
| PASS | 共有TOML例3ファイルがすべて読み込み・設定解決できる |
