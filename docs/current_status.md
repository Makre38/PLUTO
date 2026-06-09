# Current Status

Last organized: 2026-06-08

## Project Aim

This repository prepares and runs PLUTO hydrodynamics simulations for dynamical friction by a softened point-mass potential in uniform gas, then post-processes PLUTO output in Julia.

The intended physical comparison is motivated by Ostriker (1999). The 2D workflow remains useful for setup and debugging, but the main quantitative comparison should be treated as a 3D problem.

## Implemented Workflows

- 2D Cartesian PLUTO setup:
  - uniform inflow
  - softened point-mass gravity
  - generated case directories under `runs/`
  - local and Slurm execution scripts under `scripts/`
- 3D Cartesian PLUTO setup:
  - separate `definitions_3d.h` and `init_3d.c`
  - generated case directories under `runs_3d/`
  - serial and MPI local execution through `MPI_TASKS`
  - Slurm submission scripts for one case, serial sweeps, and batched sweeps
- Julia post-processing:
  - `force_from_run.jl` is the preferred one-case force script for both 2D and 3D runs
  - `force_from_run_3d.jl` remains as a simple older 3D cross-check
  - `sweep_force_plot.jl` aggregates sweep results for 2D and 3D cases
  - `animate_density.jl` visualizes 2D density snapshots with optional log-density contours
  - `plot_3d_diagnostics.jl` visualizes 3D density, speed, Mach, and force-contribution slices
- 3D runtime diagnostics:
  - `CS_ALERT_THRESHOLD` logs cells where the local sound speed becomes too small
  - `MACH_ALERT_THRESHOLD` logs cells where the local Mach number becomes too large
  - `run_stage_3d.log` records prepare, build, and run stages for 3D local or Slurm execution
  - `MPI_LAUNCHER` selects `mpirun` or `srun` for MPI execution after compilation

## Current Analysis State

- The drag sign convention is currently:
  - `Fdf = -Fx`
  - this makes drag positive when the gas force is in the expected backward direction, i.e. `Fx < 0`
- `force_from_run.jl` supports:
  - `--dimension auto`
  - `--dimension 2`
  - `--dimension 3`
- `sweep_force_plot.jl` supports:
  - `--dimension auto|2|3`
  - `--force-mode auto|axisym|2d|3d`
- For 3D runs, the preferred force calculation is a true 3D volume integral.
- For 2D runs, the direct comparison to Ostriker (1999) is provisional because the simulation is not a true 3D setup.
- Recent failing 3D no-sink runs indicate that the final stop is caused by local Mach divergence near the potential center.
- No `CS_ALERT` appeared in the inspected failure, but later plots showed very small pressure near the origin for `gamma = 1.6666`.
- Near-isothermal settings such as `gamma = 1.00001` did not show the same pressure-collapse failure mode in the tested case.
- The current leading hypothesis is pressure or internal-energy depletion near the origin, followed by a small local sound speed and divergent local Mach number.

## Verification Status

Verified locally:

- `force_from_run.jl` loaded successfully in Julia with the final `main()` call suppressed.
- Synthetic 2D and 3D PLUTO-like output directories were generated under `/tmp`.
- `force_from_run.jl` was tested on both synthetic 2D and synthetic 3D data.
- For the synthetic 3D case, `force_from_run.jl` matched the older `force_from_run_3d.jl` value for `Fx`.
- `sweep_force_plot.jl` syntax-loaded locally with `Plots` and `LaTeXStrings` stubbed out.
- The sweep calculation path was tested on synthetic 2D and 3D cases.
- The sweep `main()` path was tested through table generation with plotting functions stubbed out.
- `animate_density.jl` loaded in Julia after the contour update, and a manual user check reported that the plotting behavior worked.
- A generated 3D sink case compiled locally after the PLUTO API and `gnu17` fixes.
- `CS_ALERT` and `MACH_ALERT` were smoke-tested locally with low thresholds.
- Slurm wrapper changes were syntax-checked locally, and a remote run using `MPI_LAUNCHER=srun` compiled and launched.
- Julia plotting scripts loaded locally after the origin-overlay cleanup, and `--show-overlays` parsing was checked.

Partially verified or not yet verified:

- Full PNG generation from `sweep_force_plot.jl` was not verified locally because the local Julia environment lacks `Plots`.
- Remote verification of updated 3D sweep plotting should be done after relevant jobs finish.
- `animate_density.jl` still visualizes a 2D slice and is not yet a mature 3D visualization workflow.
- Sensitivity of force results to the inner cutoff choice has not been measured.
- The full 3D Mach sweep comparison against the Ostriker model remains open.
- The pressure-collapse mechanism has not yet been captured by a dedicated pressure/internal-energy runtime alert.

## Known Issues And Risks

- The physical choice of inner cutoff is still effectively `rcut = rbhl`; this is a provisional analysis choice, not a validated physical conclusion.
- The 2D-to-3D axisymmetric reconstruction in sweep analysis is useful as a diagnostic but may not represent the physics assumed by Ostriker (1999).
- The old `problem.md` noted an inconsistency between `force_from_run.jl` and `sweep_force_plot.jl`; recent work reduced this by adding unified 2D/3D paths, but force-mode choices still need to be interpreted carefully.
- 3D density diagnostics show a suspicious low-density hole-like structure near the potential center. It appears numerical from the animation behavior, and at least one comparable-resolution 2D run did not show the same feature.
- Some 3D runs can collapse to extremely small CFL timesteps. The current best evidence points to pressure becoming extremely small near the origin for `gamma = 1.6666`, which then drives the local sound speed down and the local Mach number up to infinity.
- The same failure mode has not been seen so far in near-isothermal tests such as `gamma = 1.00001`, so EOS and energy evolution are central to the next diagnosis.
- Simply increasing `cells_per_rbhl` is expensive in 3D because the total cell count scales roughly as the cube of the linear resolution. AMR or another local-refinement strategy should be investigated before relying on brute-force uniform-grid convergence.
