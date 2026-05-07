# Next Actions

Last organized: 2026-05-07

## Near-Term Implementation

### Run log timing

Goal:

- Make run logs easier to inspect after local or Slurm execution.

Current state:

- `scripts/run_one_case_local.sh` and `scripts/run_one_case_local_3d.sh` already print a start time and a finish time.
- The remaining cleanup is to decide the exact log format and whether elapsed time should also be printed.

Possible work:

- Standardize the finish label as `end:` if that is the desired convention.
- Print elapsed wall-clock seconds.
- Confirm that Slurm stdout/stderr paths keep these messages in the expected log files.

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

### Upstream low-density structure

Goal:

- Understand the origin of the upstream low-density hole near the potential center.

Possible work:

- Run controlled comparisons across EOS choices.
- Check whether the structure changes with resolution, softening length, and boundary placement.
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

