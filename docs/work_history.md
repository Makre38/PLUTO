# Work History

## 2026-05-27 23:22 JST - Session Handoff

- Purpose: resume the 3D numerical-failure investigation around the potential center and add a first implementation path for sink-like gas removal near the perturber.
- Changes made: added a `3D low-density hole` next-action item for a sink-like gas removal region near the potential center; added 3D PLUTO parameters `SINK_RADIUS`, `SINK_TIMESCALE`, and `SINK_RHO_FLOOR`; implemented a central sink sponge in `init_3d.c` through `UserDefBoundary(..., side == 0)`; the sink is disabled by default with `SINK_RADIUS=0.0`; when enabled, cells inside `SINK_RADIUS` relax density toward `SINK_RHO_FLOOR`, velocity toward the ambient inflow, and pressure toward `rho * cs0^2 / gamma`; threaded the sink parameters through `scripts/prepare_one_case_3d.sh` and `scripts/prepare_mach_sweep_3d.sh`; added sink suffixes to generated 3D case and manifest names when the sink is enabled; documented the basic 3D sink usage in `README.md`.
- Verification: ran `bash -n scripts/prepare_one_case_3d.sh scripts/prepare_mach_sweep_3d.sh`; generated a temporary 3D case with `SINK_RADIUS=0.05`, `SINK_TIMESCALE=0.01`, and `SINK_RHO_FLOOR=1.0e-6` and confirmed the case name, `pluto.ini`, and `run_summary.txt` include the sink settings; generated a default 3D case and confirmed the old no-sink case name is preserved; generated a one-Mach 3D sweep with sink enabled and confirmed the manifest and case names include sink suffixes; ran `git diff --check`.
- Not verified: PLUTO C compilation was not run because a local PLUTO source tree with `pluto.h` was not found during this session; no real 3D simulation was launched; no force, density, speed, or local-Mach diagnostic output was generated from the new sink runs.
- Incomplete or untouched: the sink has not yet been calibrated physically; no sink-radius or sink-timescale sensitivity study has been run; no mass-removal diagnostic or accretion-rate log was added; the implementation currently modifies primitive variables in the sink region rather than using a conservative source-term accounting path; true isothermal EOS support remains unimplemented; pre-existing uncommitted local-Mach diagnostic changes in `plot_3d_diagnostics.jl`, `README.md`, `scripts/prepare_one_case.sh`, and `scripts/prepare_one_case_3d.sh` remain part of the dirty worktree.
- Next steps: compile a generated 3D sink case on the PLUTO-capable machine; start with `SINK_RADIUS` comparable to or smaller than `rsoft` and compare against no-sink runs at the same Mach, `RSOFT_FRAC`, and resolution; inspect density, speed, and local-Mach animations to see whether the central runaway and CFL collapse are suppressed; measure sensitivity of drag to `SINK_RADIUS`, `SINK_TIMESCALE`, and `SINK_RHO_FLOOR` before treating sink results as physical.

## 2026-05-20 18:06 JST - Session Handoff

- Purpose: add a visual diagnostic path for 3D PLUTO runs so density-field failures, softening-length effects, and force-contribution structure can be inspected by eye.
- Changes made: added `plot_3d_diagnostics.jl`; it reads 3D PLUTO `double` output, selects the snapshot nearest a target `log_lambda`, plots `z = x3p` and `y = x2p` slices, uses signed-log fractional density perturbation `sign(delta) * log10(1 + abs(delta))`, overlays `rsoft` and `rcut = rbhl`, and supports `--quantity density|dfx|dfy|dfdf`; added density animation output through an HTML player plus PNG frames by default; documented the new script in `README.md`.
- Verification: loaded the new Julia script enough to confirm CLI parsing; generated synthetic 3D PLUTO-like output under `/tmp`; produced density, `dfx`, `dfy`, and `dfdf` PNG diagnostics from the synthetic data; produced an HTML density animation with PNG frames; visually checked generated density and force-contribution plots.
- Not verified: not yet run on real remote 3D PLUTO output in this local session; GIF animation output was not verified because the local NixOS environment could not execute the Julia/Plots ffmpeg artifact.
- Incomplete or untouched: animation currently supports density only; force-contribution animation is intentionally left for later; no common reader module was extracted from the existing Julia scripts; no analytic linear-density comparison was added.
- Next steps: run `plot_3d_diagnostics.jl` on remote 3D cases with different `RSOFT_FRAC` values, compare density slices and `dfdf` maps at the same target `log_lambda`, and add radial cumulative force diagnostics if the visual differences do not localize the softening sensitivity.

## 2026-05-07 19:38 JST - Session Handoff

- Purpose: reorganize scattered project logs into a human-readable `docs/` structure, improve runtime log tails, and add a 3D sweep submission mode with bounded concurrency.
- Changes made: consolidated old loose notes into `docs/current_status.md`, `docs/next_actions.md`, `docs/decisions.md`, `docs/work_history.md`, and `docs/archive/initial_setup_log.md`; removed superseded `log.md`, `change_log.md`, `problem.md`, and absorbed the untracked `todo.md` content; updated 2D and 3D local runners to print `end`, `elapsed_sec`, and `exit_status` via an `EXIT` trap; added `scripts/submit_sweep_windowed_3d.sh`; documented the 3D windowed submission workflow in `README.md`.
- Verification: checked shell syntax with `bash -n` for the changed runner scripts and the new windowed submitter; used fake `/tmp` cases to confirm runtime log tail output for success and failure paths; used a fake `sbatch` to confirm `MAX_CONCURRENT_JOBS` dependency windows and `MAX_TOTAL_TASKS / MPI_TASKS` concurrency calculation.
- Not verified: no real PLUTO run was launched; no real Slurm job was submitted; no Julia analysis or plotting was run.
- Incomplete or untouched: only the 3D windowed sweep submitter was added; no 2D equivalent was created; existing strict serial and batch submit scripts were left unchanged.
- Next steps: use `MPI_TASKS=8 MAX_CONCURRENT_JOBS=4` or `MPI_TASKS=8 MAX_TOTAL_TASKS=32` for a small 3D sweep trial, then inspect `slurm-*.out` tails for elapsed time and compare throughput before scaling up.

## 2026-05-07

### Topic

Documentation log restructuring.

### What changed

- Consolidated loose project notes into a `docs/` structure:
  - `current_status.md`
  - `next_actions.md`
  - `decisions.md`
  - `work_history.md`
  - `archive/initial_setup_log.md`
- Kept `README.md` as the command-level workflow entry point.
- Preserved useful uncommitted note content by folding it into the new documents.

## 2026-04-29

### Topic

3D force post-processing and sweep aggregation updates.

### Why this was done

The `dev/3d-mpi` branch already contained a 3D PLUTO workflow, and a remote one-case 3D run was confirmed to complete and produce force output.

The next need was to make the Julia post-processing usable for both existing 2D runs and new 3D runs without splitting the workflow into unrelated scripts.

The desired sign convention for plotted drag was also fixed:

- `Fdf = -Fx`
- this makes the drag quantity positive when the gas force is in the expected backward direction, i.e. `Fx < 0`

### What changed

- `force_from_run.jl` was updated to support both 2D and 3D one-case force calculations.
- The script now keeps loaded density as a 3D array internally.
- For 2D runs, it still computes force from the `z = 1` slice using the existing 2D area-element definition.
- For 3D runs, it computes `Fx`, `Fy`, and `Fz` using the full 3D volume element:
  - `dx * dy * dz`
- The one-case force script now accepts:
  - `--dimension auto`
  - `--dimension 2`
  - `--dimension 3`
- With `auto`, dimension is inferred from `run_summary.txt` when possible, otherwise from `nz`.
- `x3p` is read from `run_summary.txt` when available and defaults to `0.0`.
- `sweep_force_plot.jl` was updated to aggregate both 2D and 3D force results.
- The sweep script now supports:
  - `--dimension auto|2|3`
  - `--force-mode auto|axisym|2d|3d`
- The default `auto` mode keeps the old behavior for 2D-style runs by using the existing axisymmetric reconstruction.
- For 3D runs, `auto` uses the true 3D volume integral.
- A pure `2d` mode was added for the old area-element calculation when needed.
- The sweep output table now records:
  - `dimension`
  - `force_mode`
  - `Fz`
  - `Fdf_raw`
  - `Fdf_norm`
- `Fdf_raw` is now computed as `-Fx` in the sweep output.
- Non-case directories under a runs directory, such as `manifests/`, are skipped by requiring either `run_summary.txt` or `pluto.ini`.

### Verification

- See `docs/current_status.md` for the current verification summary.

### Remaining work

- Full PNG generation was not verified locally because the local Julia environment is missing `Plots`.
- Remote verification of updated 3D sweep plotting should be done after the running jobs finish.
- `animate_density.jl` still visualizes a 2D slice and has not yet been updated into a mature 3D visualization workflow.
- The old `force_from_run_3d.jl` still exists; it can remain as a simple cross-check.
- The physical choice of inner cutoff remains `rcut = rbhl`; sensitivity to this choice is still an open analysis item.
- The Ostriker comparison remains meaningful primarily for the true 3D workflow.

## 2026-04-20

### Topic

Initial 3D Cartesian workflow added alongside the existing 2D setup.

### Why this was done

The current 2D workflow is useful for setup and debugging, but it cannot fully answer whether drag behavior and wake structure are biased by dimensional reduction.

The immediate need was to launch small 3D smoke tests with the same overall physical picture:

- uniform inflow
- softened point-mass potential
- post-processed drag estimate

This first 3D step was intentionally static-grid and lightweight, without AMR.

### What changed

- Added `definitions_3d.h` and `init_3d.c` for a 3D Cartesian PLUTO problem with:
  - inflow at `X1-beg`
  - outflow elsewhere
  - softened point-mass gravity in all three directions
- Added `_3d` workflow scripts under `scripts/`:
  - `prepare_one_case_3d.sh`
  - `prepare_mach_sweep_3d.sh`
  - `run_one_case_local_3d.sh`
  - `submit_one_case_slurm_3d.sh`
  - `submit_sweep_serial_3d.sh`
  - `submit_sweep_batches_3d.sh`
- The 3D case generator now writes:
  - a separate `runs_3d/` case tree by default
  - a cubic cross-stream box with `y` and `z` spans matched
  - `run_summary.txt` entries for `nz`, `zmin`, `zmax`, and `x3p`
- Added `force_from_run_3d.jl` to compute `Fx` from a true 3D volume integral.
- Updated `README.md` with the 3D script names and a minimal smoke-test example.

## 2026-04-16

### Topic

Updates to `animate_density.jl` to overlay log-density contour lines on density snapshot plots.

### Why this was done

The density animation already showed the spatial structure of `log10 rho` as a heatmap, but color alone made subtle shape changes and wake geometry harder to read.

### What changed

- `animate_density.jl` now computes a shared set of contour levels from the global minimum and maximum of `log10 rho` across all snapshots.
- Each animation frame still draws the existing `log10 rho` heatmap and now overlays contour lines of the same field using `contour!`.
- Contour drawing parameters were added near the top of the script:
  - whether contour drawing is enabled
  - number of contour levels
  - contour color
  - contour line width
- Contour levels are fixed across the animation so each contour has the same meaning frame to frame.

### Verification

- The updated script loaded in Julia with the final `main()` call suppressed.
- A manual user check reported that the updated plotting behavior appeared to work.

## 2026-04-09

### Topic

Updates to `sweep_force_plot.jl` for multi-target force comparison and cleaner plotting output.

### Why this was done

The previous plotting script handled only one target `log Lambda` value at a time and wrote a single summary table and plot.

The workflow needed multiple `log Lambda` series on one figure and a provisional comparison against the Ostriker (1999) drag formula.

### What changed

- `sweep_force_plot.jl` now supports a default internal list of target `log Lambda` values.
- The script still supports the previous single-target mode when a numeric `log Lambda` is given on the command line.
- Output changed to:
  - one combined PNG with multiple `log Lambda` series overplotted
  - one `.dat` file per target `log Lambda`
- Drag sign convention in plot output was adjusted so plotted drag appears positive for the expected backward force.
- Plot legends now use `LaTeXStrings`.
- Plotted drag is normalized to:
  - `F_df / (4 pi rho0 (G M_p)^2 / cs0^2)`
- Output tables now store:
  - raw drag value
  - normalized drag value
  - normalization factor
- A plotting hook for an Ostriker (1999) model curve was added, with options for:
  - enabling or disabling the model overlay
  - fixed model `log Lambda`
  - Mach-number ranges that avoid the singular behavior near `Mach = 1`
  - sampling density for the theoretical curve
- The theoretical formula itself was intentionally left as a placeholder at that stage.

### Notes

- The comparison to Ostriker (1999) should be treated as provisional for 2D simulations.
- Matching the plotting normalization and model overlay machinery remains useful for later 3D runs.

## 2026-04-04

### Topic

Script layout reorganization for case preparation and execution workflow.

### Why this was done

The previous shell-script layout had become difficult to understand and operate, especially on a remote machine.

Main issues:

- generation scripts and Slurm submission flow were mixed together
- file names did not clearly indicate whether they handled one case or a sweep
- generated helper scripts under `runs/` made the execution path harder to follow
- local execution flow and Slurm-specific flow were mixed in a way that was difficult to inspect during testing

The immediate goal was infrastructure cleanup before further physics debugging.

### What changed

- The shell workflow was reorganized under `scripts/`.
- Old top-level scripts were removed:
  - `prepare_run.sh`
  - `sweep_mach.sh`
  - `run_all.sh`
  - `job.sh`
- Slurm submission now uses `sbatch --wrap` instead of copying a per-case `job.sh`.
- Sweep case lists are stored as manifest files under `runs/manifests/`.
- `README.md` was added to document script roles and typical command sequences.

### Follow-up ideas recorded at the time

- Investigate the origin of the upstream low-density hole near the potential center.
- Compare EOS choices.
- Consider using the Julia REPL for repeated calls to `animate_density.jl` if compilation time becomes important.
- Investigate whether small random perturbations can reduce realization-specific vortex-street imprint in high-Mach runs.
