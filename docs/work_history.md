# Work History

## 2026-06-10 19:38 JST - Session Handoff

- Purpose: make PLUTO runtime/debug logs easier to find under each case directory and pause before redesigning the central sink model.
- Changes made: moved 3D runtime diagnostic `.dat` output paths from the case-directory root into `logs/`; changed `run_stage_3d.log` to `logs/run_stage_3d.log`; made 3D case generation and the local 3D runner create `case_dir/logs/`; added `logs/sink_boundary_3d.rankNNNN.dat` output whenever `UserDefBoundary(..., side == 0)` is called, including `step`, `time`, `dt`, sink parameters, and the number of cells inside the sink radius on that rank; documented the new log paths in `README.md`.
- Verification: ran shell syntax checks with `bash -n scripts/run_one_case_local_3d.sh scripts/prepare_one_case_3d.sh scripts/prepare_mach_sweep_3d.sh`; generated a small 3D test case under `/tmp/pluto_log_check` and confirmed `logs/` exists and copied `init.c` writes to `logs/...`; compiled that generated case locally with `make clean ARCH=Linux.gcc.defs && make ARCH=Linux.gcc.defs`; ran `./pluto -maxsteps 1` and confirmed `logs/sink_boundary_3d.rank0000.dat` is written, showing that `side == 0` is being reached in the serial test; temporarily raised `CS_ALERT_THRESHOLD` in the `/tmp` test case and confirmed `logs/diagnostics_cs_alert_3d.rank0000.dat` is written; ran `git diff --check`.
- Not verified: MPI compilation and MPI runtime behavior were not tested because `mpicc` is not available locally; the new log paths have not yet been verified on the remote Slurm system; `MACH_ALERT` was not separately forced in the smoke test, though its path change mirrors `CS_ALERT`.
- Incomplete or untouched: the worktree remains intentionally dirty with the current log-path/debug changes plus the pre-existing `docs/work_history.md` update; the physical sink formulation has not been changed yet; no pressure/internal-energy alert was added in this session.
- Sink redesign note: the current top-hat sink can create a discontinuity at `r_sink` because it directly relaxes density, velocity, and pressure inside the radius. The next proposed model is a smooth absorbing radial-velocity sponge: decompose velocity into radial and tangential components around the perturber, damp only the radial component with `v_r^(n+1) = (1 - alpha(r)) v_r^n`, then reconstruct `v = v_t + v_r^(n+1) e_r`. Use a smooth taper such as `q = max(0, 1 - r/r_sink)` and `alpha(r) = alpha0 q^p`, so `alpha(r_sink) = 0`; compute `alpha0 = 1 - exp(-dt/tau_sink)` to reduce timestep dependence. Start with an inflow-only option that damps only inward radial motion (`v_r < 0`) and leaves density and pressure unchanged.
- Recommended next steps: implement the radial-velocity sponge as a selectable sink mode rather than overwriting the legacy top-hat behavior; add parameters such as `SINK_MODE`, `SINK_TAPER_POWER`, and `SINK_INFLOW_ONLY` while reusing `SINK_RADIUS` and `SINK_TIMESCALE`; extend `logs/sink_boundary_3d.rankNNNN.dat` with `max_alpha`, `max_abs_vr_before`, and `max_abs_vr_after`; run matched no-sink, legacy top-hat, and radial-sponge cases at fixed Mach, `RSOFT_FRAC`, and resolution; inspect density, pressure, speed, local Mach, and force sensitivity before treating sink results as physical.

## 2026-06-09 21:13 JST - Session Handoff

- Purpose: pause the 3D central-sink investigation after finding that the original sink test was not actually exercising `UserDefBoundary(..., side == 0)` and after a corrected sink run exposed a likely sink-boundary instability.
- Changes made: inspected PLUTO's internal-boundary handling and found that `side == 0` is called only when `INTERNAL_BOUNDARY == YES`; added `INTERNAL_BOUNDARY YES` to `definitions_3d.h`; temporarily added a lightweight `log_sink` / `log_sink.rankNNNN` debug write at the start of `ApplyCentralSink()` to confirm sink calls; checked PLUTO documentation at `$PLUTO_DIR/Doc/userguide.pdf`, Section 5.3.1, for the `INTERNAL_BOUNDARY` / `side == 0` behavior; added a small throwaway `runs_logs/calcr.jl` helper to compute radii from manually supplied coordinates.
- Findings: before enabling `INTERNAL_BOUNDARY`, no `log_sink` file appeared, so the sink was not being called even when sink parameters were present in `pluto.ini`; after enabling the internal boundary, image output showed the sink region density being reset to the requested value, confirming the sink was active; however, PLUTO logs in `runs_logs/pluto.0.log` still show nonphysical states near `r_sink = 1.0`, with the first inspected bad coordinate around `r = 1.18` and other reported radii roughly `0.99` to `1.3`.
- Interpretation: the no-sink failure remains consistent with gas entering the deep potential, accelerating, losing effective pressure/internal energy support, and driving local sound speed toward zero; the active top-hat sink appears to introduce a new problem at or just outside the sink boundary, likely because the region inside `r_sink` is forced to low-density/ambient-like values while the exterior flow remains gravitationally compressed and accelerated. This can create a pressure/velocity/density discontinuity or rarefaction/shock structure near `r_sink`.
- Verification: confirmed by user inspection that the active sink sets density inside the chosen radius to `1`; computed one representative bad-coordinate radius as `1.1814688770957955`; no compile, full rerun, or automated plot generation was performed in this handoff step.
- Not verified: whether the instability disappears with a smaller `r_sink`, a smoother sink taper, a pressure/sound-speed floor, or a conservative sink formulation; whether modifying primitive variables directly is causing stage-to-stage inconsistency in RK2; whether `FLAG_INTERNAL_BOUNDARY` should be used to exclude the sink interior from updates rather than simply modifying primitive variables.
- Incomplete or untouched: docs/current status and next-actions were not updated for the revised conclusion; the temporary `log_sink` debug write may still exist in `init_3d.c` depending on the branch state used for the next run; `runs_logs/` appears untracked/ignored and should be treated as scratch evidence rather than durable project state.
- Next steps: decide the physical inner-boundary model before more implementation. The most plausible next experiment is a smooth absorbing sponge with a taper that goes to zero at `r_sink`, plus pressure/internal-energy or sound-speed flooring so the sink does not create a low-pressure hole. Compare against smaller `r_sink` values closer to `rsoft`, and consider applying the sink to conservative variables or adding `FLAG_INTERNAL_BOUNDARY` if the region should behave more like an absorbing inner boundary than an actively evolved fluid region.

## 2026-06-08 22:06 JST - CFL Collapse Investigation Summary

- Purpose: summarize the recent 3D numerical-failure investigation where a run stops after the maximum local Mach number diverges near the potential center.
- Changes made: added runtime diagnostics for low sound speed (`CS_ALERT_THRESHOLD`, `CS_ALERT_EVERY_STEPS`) and high local Mach number (`MACH_ALERT_THRESHOLD`, `MACH_ALERT_EVERY_STEPS`); made Mach alerts write rank-specific files with the local cell position, `rho`, `prs`, `cs`, velocity components, speed, and Mach; added Slurm run-stage logging through `run_stage_3d.log`; added `MPI_LAUNCHER=mpirun|srun` support and found that `MPI_LAUNCHER=srun` is needed on the tested Slurm environment; kept 3D plotting overlays hidden by default so the potential-center region can be inspected without the origin marker or softening/cutoff circles.
- Findings: in a failing no-sink run, no `CS_ALERT` was produced before the stop, but the PLUTO log showed local Mach values growing from order unity to extremely large values and then `inf`; the final MPI messages look like consequences of `MPI_Abort`, not the primary cause. Follow-up plots around the failure showed that for `gamma = 1.6666`, pressure becomes extremely small near the origin. Near-isothermal settings such as `gamma = 1.00001` did not show the same failure mode in the tested case.
- Interpretation: the most likely immediate path is local pressure/internal-energy depletion near the potential center, which drives `c_s = sqrt(gamma * p / rho)` downward and can make the local Mach number diverge. The difference between `gamma = 1.6666` and near-isothermal `gamma` suggests the failure is tied to the ideal-gas energy evolution rather than only to the Mach diagnostic itself.
- Verification: local serial compile passed after the PLUTO API and `gnu17` fixes; local diagnostic smoke tests confirmed `CS_ALERT` and `MACH_ALERT` output paths; shell syntax and fake-submit checks covered the Slurm wrapper changes; the remote run using `MPI_LAUNCHER=srun` compiled and launched; Julia diagnostic scripts loaded locally after the overlay change, and `--show-overlays` CLI parsing was checked.
- Not verified: the pressure/internal-energy depletion mechanism has not yet been captured by a dedicated pressure alert; MPI alert aggregation is still rank-local rather than a single global reduction; no physical fix has been selected; sink-enabled runs have not been used to interpret the failure.
- Next steps: add a pressure or internal-energy alert that logs the first cells where `prs` or `E - kinetic` falls below a chosen threshold; rerun the no-sink failing case with `MACH_ALERT_THRESHOLD` low enough to catch the onset; compare `gamma = 1.6666`, near-isothermal `gamma`, and any true isothermal PLUTO setup under otherwise identical conditions; inspect whether the pressure loss begins inside `rsoft`, near a boundary of the softened potential, or along a shock/rarefaction structure.

## 2026-06-08 16:25 JST - Max Mach Alert Diagnostic

- Purpose: extend the CFL-collapse diagnostics after a no-`CS_ALERT` failure showed Mach diverging to infinity while the sound-speed threshold was not crossed.
- Changes made: added 3D PLUTO user parameters `MACH_ALERT_THRESHOLD` and `MACH_ALERT_EVERY_STEPS`; updated `Analysis()` to track the maximum local Mach number and log the cell location plus local `rho`, `prs`, `cs`, velocity, and speed when the threshold is exceeded; wrote Mach alerts to rank-specific files named `diagnostics_mach_alert_3d.rankNNNN.dat` to avoid MPI write collisions; threaded the new parameters through one-case and sweep 3D generation; documented the diagnostic in `README.md`.
- Verification: local shell syntax, generated-parameter checks, serial PLUTO compile, and a forced low-threshold smoke run were performed after the change.
- Next steps: rerun the failing Mach 0.1 no-sink case with `MACH_ALERT_THRESHOLD=10.0` or lower and inspect the first `MACH_ALERT` rank file.

## 2026-06-08 15:48 JST - Slurm Run Stage Logging

- Purpose: make failed 3D Slurm jobs distinguish compile failures from MPI launch/runtime failures, and allow switching the MPI launcher on clusters where `srun` is required.
- Changes made: added stage markers to `scripts/run_one_case_local_3d.sh` before and after `make clean`, `make`, and PLUTO execution; wrote the same markers to `run_stage_3d.log` in the case directory; logged the last completed stage in the exit trap; added `MPI_LAUNCHER=mpirun|srun` support; resolved case paths to absolute paths in `scripts/submit_one_case_slurm_3d.sh`; passed `MPI_LAUNCHER` through the Slurm `--wrap` command; documented `MPI_LAUNCHER=srun` usage in `README.md`.
- Verification: shell syntax and fake-submit checks were run locally. Real Slurm execution and MPI launch behavior must be verified on the remote cluster.
- Next steps: resubmit the failing case with `MPI_TASKS=16 MPI_LAUNCHER=srun`; inspect both Slurm stdout/stderr and the case-local `run_stage_3d.log` if it fails again.

## 2026-06-08 14:23 JST - Sound-Speed Alert Diagnostic

- Purpose: add a first runtime diagnostic for the CFL-collapse investigation that works without enabling the central sink, focused specifically on detecting whether the local sound speed becomes abnormally small.
- Changes made: added 3D PLUTO user parameters `CS_ALERT_THRESHOLD` and `CS_ALERT_EVERY_STEPS`; enabled per-step `Analysis()` calls in generated 3D cases; implemented a `DOM_LOOP` scan in `Analysis()` that finds the minimum local sound speed from `sqrt(gamma * prs / rho)` for ideal-gas runs, treats non-positive `rho` or `prs` as invalid states, and logs the location plus local `rho`, `prs`, velocity, speed, and Mach number when the threshold is crossed; documented the diagnostic in `README.md`.
- Verification: ran `bash -n scripts/prepare_one_case_3d.sh scripts/prepare_mach_sweep_3d.sh`; generated a no-sink 3D case with `CS_ALERT_THRESHOLD=1.0e-6` and confirmed `pluto.ini` contains `analysis -1.0 1`, `SINK_RADIUS=0.0`, and the alert parameters; compiled that case with `make clean ARCH=Linux.gcc.defs && make ARCH=Linux.gcc.defs`; generated a tiny no-sink case with `CS_ALERT_THRESHOLD=2.0`, ran `./pluto -maxsteps 1`, and confirmed `CS_ALERT` lines are printed and `diagnostics_cs_alert_3d.dat` is written; ran the default-threshold no-sink case for `-maxsteps 1` and confirmed no alert file is created.
- Not verified: MPI behavior is not reduced to a single global minimum yet; `mpicc` is not available locally, so MPI compile and MPI alert logging were not tested; no failing production run has been rerun with the diagnostic.
- Next steps: run a failing no-sink 3D case with this diagnostic enabled, inspect the first `CS_ALERT` location and local `rho`/`prs`, and then add complementary max-speed or max-Mach diagnostics if the sound speed does not explain the failure.

## 2026-06-08 13:20 JST - Compile Fix

- Purpose: move the uncommitted configurable 3D sink velocity work onto `dev/3d-sink-velocity-factor` and verify that a generated 3D sink case compiles against the local PLUTO install.
- Changes made: fixed `ApplyCentralSink()` coordinate access from `grid[IDIR].x[i]`-style indexing to the PLUTO 4.4 `Grid *` API, `grid->x[IDIR][i]`; updated `local_make` to replace strict `-std=c17` with `-std=gnu17` so PLUTO's `drand48()`/`srand48()` usage is declared on the local glibc toolchain.
- Verification: regenerated a temporary 3D sink case at `runs_3d_timetest/mach0.500_mp1.000_ll0.100_rbhl1.0_3d_sink0.05_tau0.01`; ran `make clean ARCH=Linux.gcc.defs && make ARCH=Linux.gcc.defs` in that case; serial PLUTO compile completed successfully.
- Not verified: MPI compile was not run because `mpicc` was not found in the local environment; the generated `pluto` executable was not launched, so no simulation output or diagnostics were produced.
- Next steps: run the same generated-case compile with `ARCH=Linux.mpicc.defs` on an MPI-capable environment; then compare no-sink, `SINK_VELOCITY_FACTOR=1.0`, and `SINK_VELOCITY_FACTOR=0.0` runs at fixed Mach, `RSOFT_FRAC`, and resolution.

## 2026-05-28 18:33 JST - Session Handoff

- Purpose: make the 3D central sink velocity target configurable so sink runs can test both the previous ambient-inflow sponge behavior and a perturber-frame rest sink.
- Changes made: added the 3D PLUTO user parameter `SINK_VELOCITY_FACTOR`; increased `USER_DEF_PARAMETERS` from 12 to 13; changed `ApplyCentralSink()` so the sink-region target x-velocity is `SINK_VELOCITY_FACTOR * Mach * cs0` while the transverse target velocities remain zero; threaded `SINK_VELOCITY_FACTOR` through `scripts/prepare_one_case_3d.sh` and `scripts/prepare_mach_sweep_3d.sh`; wrote the value to generated `pluto.ini` and `run_summary.txt`; documented `SINK_VELOCITY_FACTOR=0.0` as the way to relax sink velocity toward rest while preserving `1.0` as the default old behavior.
- Verification: ran `bash -n scripts/prepare_one_case_3d.sh scripts/prepare_mach_sweep_3d.sh`; generated a temporary one-case 3D run with `SINK_VELOCITY_FACTOR=0.0` and confirmed `pluto.ini` and `run_summary.txt` include the value; generated a temporary one-Mach 3D sweep with `SINK_VELOCITY_FACTOR=0.25` and confirmed the generated case receives the value and the manifest is written; ran `git diff --check`.
- Not verified: PLUTO C compilation was not run because no local PLUTO source tree is installed yet; no remote compile or simulation was launched; no force, density, speed, or local-Mach diagnostics were generated for the new velocity-factor sink variants.
- Incomplete or untouched: the earlier likely const-correctness compile issue in `ApplyCentralSink(const Data *d, Grid *grid)` remains unresolved; the sink still modifies primitive variables directly rather than using a conservative source-term or mass-removal accounting path; no spatial taper has been added at `SINK_RADIUS`, so the sink is still top-hat in space.
- Next steps: install or copy a PLUTO source tree locally and compile a generated 3D case to catch `init.c`/PLUTO API errors quickly; compare no-sink, `SINK_VELOCITY_FACTOR=1.0`, and `SINK_VELOCITY_FACTOR=0.0` runs at fixed Mach, `RSOFT_FRAC`, and resolution; inspect density, speed, and local-Mach diagnostics before using any sink result in force interpretation.

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
