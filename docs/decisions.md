# Decisions

Last organized: 2026-05-07

## Physical Setup

- Use code units:
  - `rho0 = 1`
  - `cs = 1`
  - `G = 1`
- Use the perturber mass notation `M_p`, following Ostriker (1999).
- Define the Bondi-Hoyle-Lyttleton-like scale for the current workflow as:
  - `r_BHL = M_p / (1 + Mach^2)`
- Treat `r_BHL` as the physical inner scale used to organize force analysis.
- Treat `r_s` as the numerical softening length used to regularize the potential near the origin.

## Dimensional Strategy

- Use 2D simulations for setup, debugging, and qualitative diagnostics.
- Treat the main physical comparison to Ostriker (1999) as fundamentally 3D.
- Add and maintain a separate 3D Cartesian workflow rather than trying to make 2D results carry the final interpretation.

## Output And Analysis

- Use PLUTO `double` binary output for the current workflow.
- Reconsider HDF5 only if richer metadata, 3D production data sharing, or a longer-lived analysis pipeline requires it.
- Keep force calculation in Julia rather than PLUTO so diagnostics can be recomputed without rerunning simulations.
- Use `log_Lambda = ln(cs t / r_BHL)` as the main time-like comparison variable.
- Select snapshots nearest to requested `log_Lambda` values during post-processing.
- Use `Fdf = -Fx` for plotted drag.

## Force Calculation

- For true 3D runs, use the full 3D density field and volume element.
- For 2D runs, keep any 2D-to-3D reconstructed force interpretation clearly provisional.
- Keep `rcut = rbhl` as the current default inner cutoff, but treat this as an open analysis choice that needs sensitivity tests.
- Prefer `force_from_run.jl` as the unified one-case analysis entry point.
- Keep `force_from_run_3d.jl` only as a simple cross-check unless it becomes unnecessary.

## Run Generation

- Generate `pluto.ini` separately for each run.
- Control effective resolution by `cells_per_rbhl`, not directly by hand-written `Nx` and `Ny`.
- Compute `r_BHL`, box size, total runtime, and grid size from a small set of physical and numerical controls.
- Keep box-size margins in the run-generation scripts rather than hard-coding them as physical model parameters.
- Keep generated run directories under `runs/` and `runs_3d/`, both ignored by Git.

## Script Organization

- Keep hand-managed workflow scripts under `scripts/`.
- Use `one_case` naming for single-case scripts.
- Store generated sweep case lists as manifest files under generated run directories.
- Separate script responsibilities:
  - `prepare_*` generates case files and directories
  - `run_*` executes prepared cases locally
  - `submit_*` submits prepared cases to Slurm

