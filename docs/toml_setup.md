# TOML Case Setup

## Agreed interface (2026-11-05)

- Scope: 3D single cases and one-parameter Mach or softening sweeps. Preparation only; existing execution and Slurm scripts remain independent.
- Entry point: `bash scripts/prepare_from_toml.sh SETUP.toml`, backed by Julia's standard-library `TOML`.
- Tables: `physics` (mach, gamma, mass, density, sound_speed), `softening` (a_soft or rsoft_frac), `grid` (cells_per_rbhl, margin_up, margin_down, margin_y, upstream_min), `time` (log_lambda_max, cfl), `output` (count, runs_dir, subdir), `limits` (warn_cells, hard_cells, min_cells_per_rsoft, min_boundary_over_rsoft), and `diagnostics` (sound_speed_threshold, sound_speed_every_steps, mach_threshold, mach_every_steps).
- `schema_version = 1` is required. Other settings may be omitted and use recorded defaults. Softening defaults to legacy rsoft_frac=0.25 when neither interface is selected.
- Optional `sweep`: `parameter = "physics.mach"` or `"softening.a_soft"`, and a nonempty numeric `values` list. Reject duplicates and conflicts with fixed values; no Cartesian product or range syntax in this version.
- TOML values override defaults. Inherited simulation environment variables never override TOML; the old environment-variable interface remains available separately. No per-key CLI overrides in this version.
- Resolve relative output paths against the TOML directory. Shared examples live in `configs/examples/`; personal files in ignored `configs/local/`.
- Calculate Bondi/BHL/softening scales, grid sizes, duration and output intervals rather than accepting derived values as input. Save the original TOML, effective input/defaults, derived metadata and code revision in every generated case.
- Reject unknown tables/keys, invalid types/ranges, sink options, conflicting softening inputs and existing case destinations. Validate/stage all cases before publishing; write a manifest for sweeps.
- Sound-speed threshold defaults to 1e-6, Mach threshold to 0 (disabled), both repeat intervals to 1. Zero thresholds disable the corresponding alerts. Existing runtime diagnostic implementation is retained.
- CFL defaults to 0.333, matching the user's change. Cell limits default to 2,000,000 warning and 8,000,000 hard limit; softening resolution/boundary warnings remain 2 and 4. The TOML interface exposes these controls without submitting jobs.
- Build architecture, PLUTO location, MPI resources/launcher and Slurm settings are outside the case TOML. No physics or velocity-gradient changes are included.

## Verification plan

Compare generated inputs with equivalent legacy settings; test single cases, both sweeps, defaults, hostile inherited environment, relative paths, original/effective records, invalid input and overwrite protection. Run existing generator/Julia tests and a short serial PLUTO run with configured diagnostics. Remote/MPI and physical convergence remain separate work.

## Usage and records

```bash
bash scripts/prepare_from_toml.sh configs/examples/single.toml
bash scripts/prepare_from_toml.sh configs/examples/mach_sweep.toml
bash scripts/prepare_from_toml.sh configs/examples/softening_sweep.toml
```

See the full [single-case example](../configs/examples/single.toml). The two
sweep examples omit the fixed value being swept and add a `sweep` table:

```toml
[sweep]
parameter = "physics.mach"
values = [0.1, 0.3, 0.5]
```

For softening use `parameter = "softening.a_soft"` and omit both fixed
softening keys. Sweep values may be integers or floats; all members use the
same defaults. Gamma defaults to 1.6666 for both TOML single cases and sweeps,
unlike the legacy Mach wrapper's historical default of 1.0001.

The complete example lists all settings and defaults except that it chooses
mach=0.5, a_soft=4, cells_per_rbhl=8 and log_lambda_max=1. Omitted fields default
to mach=0.1, rsoft_frac=0.25, cells_per_rbhl=2, log_lambda_max=2. `runs_dir`
defaults to `../../runs_3d` relative to the source TOML directory. Subdir must
be a relative path without parent traversal or whitespace. CFL must satisfy
`0 < cfl < 1/3`; gamma must exceed 1. Positive integer output counts, diagnostic
intervals and cell limits are required. Zero thresholds disable alerts;
negative thresholds, unknown keys and removed sink keys are rejected.

`setup.original.toml` is an exact copy of the input. `setup.effective.toml`
contains resolved per-case inputs (including defaults and an absolute output
root), provenance (source path, Git revision and dirty-worktree flag), and a
`derived` table containing the original string values from `run_summary.txt`
to preserve their precision. The effective file is an archival record, not an
input file: remove the provenance/derived tables before reusing it as input.
A dirty flag is a warning that the revision alone does not reproduce uncommitted
source changes; it does not archive those changes.

All members are validated and generated in temporary staging directories
before any case is published. Rounded case-name collisions are rejected.
Publication reserves each destination with exclusive mkdir; a filesystem or
concurrency failure during copying can leave a partial directory. Inspect
such a directory rather than rerunning over it. Sweep manifests retain the
successfully published cases. Source configuration is never read at execution
time, so individual cases can be rerun/submitted independently.

```bash
julia --startup-file=no tests/test_toml_setup.jl
```

## Julia implementation and readable verification (2026-11-05)

The preparation implementation and its new tests have been rewritten in Julia.
`scripts/prepare_from_toml.jl` uses the standard `TOML` library; the shell entry
point invokes Julia with `--startup-file=no`. No Python is needed for this
interface. The existing older `tests/test_softening_generation.py` is separate
historical code and was not rewritten in this step.

The Julia test suite prints what each scenario checks and its PASS/FAIL result,
and saves [a Markdown report](test_reports/toml_setup_julia.md) by default.
The report includes the execution time, Julia version, Git revision, dirty-state
flag, scenario descriptions and any failure details. It is written on assertion
failures too; a failing suite exits nonzero. The default report is replaced on
each run, so use a different path when preserving multiple executions:

```bash
julia --startup-file=no tests/test_toml_setup.jl --report /tmp/toml-check.md
```

The suite checks generation and validation, not PLUTO physics. Serial smoke
verification is recorded separately in the session handoff and the runtime
report. The existing numerical Julia suites retain their normal Test summaries;
[the numerical verification record](test_reports/toml_julia_runtime.md) explains
what was run. AGENTS.md policy changes are deferred to a later task.
