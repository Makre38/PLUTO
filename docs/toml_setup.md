# TOML Case Setup

## Agreed interface (2026-11-05)

- Scope: 3D single cases and one-parameter Mach or softening sweeps. Preparation only; existing execution and Slurm scripts remain independent.
- Entry point: `bash scripts/prepare_from_toml.sh SETUP.toml`, backed by Python 3.11+ standard-library `tomllib`.
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
