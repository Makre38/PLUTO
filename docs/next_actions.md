# Next Actions

Last organized: 2026-06-08

## Near-Term Implementation

### Pressure-collapse diagnostic

Goal:

- Identify where and when pressure or internal energy first becomes too small near the potential center in failing 3D runs.

Current state:

- `CS_ALERT_THRESHOLD` and `MACH_ALERT_THRESHOLD` diagnostics exist.
- A failing no-sink run produced no `CS_ALERT`, but Mach still diverged to infinity.
- Post-failure plots suggest that for `gamma = 1.6666`, pressure becomes extremely small near the origin.
- Near-isothermal `gamma = 1.00001` tests did not show the same failure mode.

Possible work:

- Add a `PRS_ALERT_THRESHOLD` or internal-energy alert in `Analysis()`.
- Log rank, step, time, position, `rho`, `prs`, `cs`, velocity, kinetic energy, total energy, and internal energy for the first offending cells.
- Keep output rank-specific, following `diagnostics_mach_alert_3d.rankNNNN.dat`, to avoid MPI write collisions.
- Rerun the no-sink failing case and compare the first pressure alert with the first Mach alert and the last stable plotted snapshot.

### MPI run logging

Goal:

- Keep remote failures distinguishable between compile failure, MPI launch failure, and PLUTO runtime failure.

Current state:

- `scripts/run_one_case_local_3d.sh` writes stage markers to `run_stage_3d.log`.
- `MPI_LAUNCHER=mpirun|srun` is supported.
- The tested Slurm environment needs `MPI_LAUNCHER=srun` for successful MPI launch.

Possible work:

- Keep using `MPI_LAUNCHER=srun` on that remote cluster.
- When a job fails, inspect `run_stage_3d.log`, Slurm stdout, Slurm stderr, and PLUTO logs together.
- Consider making the Slurm submitter default to `srun` everywhere only if all target clusters behave consistently.

### 3D sweep plotting verification

Goal:

- Confirm that updated 3D sweep aggregation and plotting work on real remote output.

Possible work:

- Run `sweep_force_plot.jl` on completed `runs_3d/` output.
- Confirm PNG generation in an environment with `Plots` and `LaTeXStrings`.
- Compare generated tables against selected one-case `force_from_run.jl` results.

## Physics And Numerics Checks

### Inner cutoff sensitivity

Goal:

- Measure how strongly `Fdf` depends on the force-integration inner cutoff.

Possible work:

- Make `rcut` an explicit analysis parameter.
- Compare several values around `rbhl`, `rsoft`, and a few grid-cell widths.
- Record whether the Mach trend changes qualitatively.

### 3D low-density hole

Goal:

- Understand the origin of the suspicious low-density hole-like structure near the potential center in 3D density diagnostics.

Possible work:

- Compare otherwise matched 2D and 3D runs at the same `cells_per_rbhl`.
- Run controlled comparisons across EOS choices, especially `EOS IDEAL` with `gamma = 1.0001` versus a true isothermal setup if available.
- Check whether the structure changes with resolution, softening length, and boundary placement.
- Keep using the existing `CS_ALERT` and `MACH_ALERT` diagnostics to identify where CFL timestep collapse starts.
- Add pressure and internal-energy threshold diagnostics, since current evidence points to very small `prs` near the origin for `gamma = 1.6666`.
- Compare timestep-collapse cases against density-slice and local-Mach animations to see whether Mach divergence and the low-density hole are the same numerical failure.
- Compare `gamma = 1.6666`, near-isothermal `gamma = 1.00001`, and a true isothermal PLUTO setup if available.
- Investigate adding a sink-like gas removal region near the potential center. This may better approximate gas accretion onto a realistic black hole, and may also prevent the high-density central region from driving runaway local velocities or infinite Mach numbers that break the calculation.
- Investigate whether PLUTO AMR/Chombo or a static locally refined grid can resolve the near-perturber region without increasing the full 3D domain by the cube of the target resolution.
- Treat this as a physics and numerics check, not as a script-layout issue.

### Perturbed high-Mach runs

Goal:

- Test whether small random perturbations reduce realization-specific vortex-street imprint in high-Mach runs.

Possible work:

- Compare deterministic and perturbed runs.
- Ensemble-average drag and density structure.
- Decide whether perturbations should be added only to the initial condition or continuously through the inflow boundary.
- Measure sensitivity to perturbation amplitude and random seed.

## Documentation Maintenance

- Keep `README.md` focused on command-level workflow.
- Keep current project state in `docs/current_status.md`.
- Record dated work in `docs/work_history.md`.
- Record durable choices in `docs/decisions.md`.
- Move resolved TODO items out of `docs/next_actions.md` after they are completed and summarized in `docs/work_history.md`.
