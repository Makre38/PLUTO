# Change Log

## 2026-04-20

### Topic

Initial 3D Cartesian workflow added alongside the existing 2D setup.

### Why this was done

The current 2D workflow is useful for setup and debugging, but it cannot fully answer whether the drag behavior and wake structure are being biased by the dimensional reduction itself.

The immediate need is to launch small 3D smoke tests with the same overall physical picture:

- uniform inflow
- softened point-mass potential
- post-processed drag estimate

This first 3D step is intentionally static-grid and lightweight, without AMR yet.

### What was changed

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
- Added `force_from_run_3d.jl` to compute `Fx` from a true 3D volume integral instead of the previous 2D-to-3D reconstruction idea.
- Updated `README.md` with the 3D script names and a minimal smoke-test example.

### Notes

- The new 3D local run script supports both serial and MPI execution through `MPI_TASKS`.
- This is only the first 3D step; sweep aggregation and 3D visualization are still less mature than the existing 2D tooling.

## 2026-04-16

### Topic

Updates to `animate_density.jl` to overlay log-density contour lines on density snapshot plots.

### Why this was done

The density animation already showed the spatial structure of `log10 rho` as a heatmap, but it was harder to read subtle shape changes and wake geometry from color alone.

Adding contour lines on top of the same `log10 rho` field makes the density structure easier to inspect frame by frame without changing the existing plotting workflow.

### What was changed

- `animate_density.jl` now computes a shared set of contour levels from the global minimum and maximum of `log10 rho` across all snapshots.
- Each animation frame still draws the existing `log10 rho` heatmap, and now overlays contour lines of the same `log10 rho` field using `contour!`.
- Contour drawing parameters were added near the top of the script so the overlay can be adjusted easily:
  - whether contour drawing is enabled
  - the number of contour levels
  - contour color
  - contour line width
- The contour levels are kept fixed across the full animation so the visual meaning of each contour remains consistent from frame to frame.

### Verification

- The updated script was loaded in Julia with the final `main()` call suppressed, and the load completed successfully.
- A manual user check also reported that the updated plotting behavior appears to work.

## 2026-04-09

### Topic

Updates to `sweep_force_plot.jl` for multi-target force comparison and cleaner plotting output.

### Why this was done

The previous plotting script handled only one target `log Lambda` value at a time and wrote a single summary table and plot.

This made it inconvenient to compare drag estimates across multiple `log Lambda` choices on one figure, and the plot labels were still fairly plain.

There was also a need to prepare the plotting workflow for a provisional comparison against the Ostriker (1999) drag formula, while keeping in mind that the current simulation setup is still 2D.

### What was changed

- `sweep_force_plot.jl` now supports a default internal list of target `log Lambda` values, so multiple targets can be processed in one run.
- The script still supports the previous single-target mode when a numeric `log Lambda` is given on the command line.
- Output was changed to:
  - one combined PNG with multiple `log Lambda` series overplotted
  - one `.dat` file per target `log Lambda`
- The drag sign convention in the plot output was adjusted so that the plotted drag appears as a positive quantity for the expected backward force.
- Plot legends were updated to use `LaTeXStrings`, so `log Lambda` now appears in a cleaner mathematical style.
- The plotted drag was normalized to the Ostriker-style quantity
  - `F_df / (4 pi rho0 (G M_p)^2 / cs0^2)`
- The output tables now store both:
  - the raw drag value
  - the normalized drag value
  - the normalization factor used
- A plotting hook for an Ostriker (1999) model curve was added, with internal options for:
  - enabling or disabling the model overlay
  - setting a fixed model `log Lambda`
  - choosing Mach-number ranges that avoid the singular behavior near `Mach = 1`
  - setting the sampling density for the theoretical curve
- The theoretical formula itself is intentionally left as a placeholder to be filled in later.

### Notes

- The present comparison to Ostriker (1999) should be treated as provisional, because the current simulations are 2D while the Ostriker expression is a 3D result.
- Even so, matching the plotting normalization and preparing the overlay machinery is useful for qualitative comparison and for a smoother transition to later 3D runs.

## 2026-04-04

### Topic

Script layout reorganization for case preparation and execution workflow.

### Why this was done

The previous shell-script layout had become difficult to understand and operate, especially on a remote machine.

Main issues:

- generation scripts and Slurm submission flow were mixed together
- file names did not clearly indicate whether they handled one case or a sweep
- generated helper scripts under `runs/` made the execution path harder to follow
- the repository mixed local execution flow and Slurm-specific flow in a way that was difficult to inspect quickly during testing

The immediate goal of this reorganization was not to change the physics setup, but to make the execution workflow understandable and easier to use for future debugging of the density-structure problem.

### What was changed

The shell-script workflow was reorganized under `scripts/`.

Current roles:

- `scripts/prepare_one_case.sh`
  - generate one case directory
- `scripts/prepare_mach_sweep.sh`
  - generate a Mach sweep and write a manifest file
- `scripts/run_one_case_local.sh`
  - build and run one prepared case locally
- `scripts/submit_one_case_slurm.sh`
  - submit one prepared case to Slurm
- `scripts/submit_sweep_serial.sh`
  - submit all cases in a manifest as one-case-per-job chained execution
- `scripts/submit_sweep_batches.sh`
  - submit all cases in a manifest in batches

Other changes:

- old top-level scripts were removed:
  - `prepare_run.sh`
  - `sweep_mach.sh`
  - `run_all.sh`
  - `job.sh`
- Slurm submission now uses `sbatch --wrap` instead of copying a per-case `job.sh`
- sweep case lists are now stored as manifest files under `runs/manifests/`
- `README.md` was added to document script roles and typical command sequences

### Design decisions

- use `one_case` naming rather than `one_run`
- keep hand-managed scripts under `scripts/`
- keep `runs/` as generated output only
- keep the list of generated sweep cases in manifest files rather than generated submission scripts
- separate responsibilities clearly:
  - `prepare_*` generates files and directories
  - `run_*` executes locally
  - `submit_*` submits to Slurm

### Expected benefits

- easier to understand what each script does
- easier to test one case locally before launching a sweep
- easier to submit sweeps without relying on generated helper scripts
- easier to debug future physics issues because execution flow is clearer

### Notes for future work

- This reorganization was done as infrastructure cleanup before investigating the upstream low-density structure near the potential center.
- The next technical phase should use the cleaned script layout to run controlled comparison tests.

### Planned follow-up

- Investigate the origin of the upstream low-density hole near the potential center.
- One planned diagnostic is to change or compare the EOS setup.
- This is meant as a physics and numerics check, not as part of the script-layout cleanup itself.
- The purpose of the EOS comparison is to test whether the anomalous density structure is related to the present equation-of-state choice rather than only to boundaries, resolution, or other run settings.
- Keep in mind that calling `animate_density.jl` from the Julia REPL may be useful later for repeated interactive use, but this is currently lower priority because runtime is expected to dominate over compilation cost.
- Investigate whether small random perturbations can reduce realization-specific vortex-street imprint in high-Mach runs.
- Compare deterministic runs and perturbed runs by ensemble-averaging drag and density structure.
- Decide whether perturbations should be added only to the initial condition or continuously through the inflow boundary.
- Measure sensitivity to perturbation amplitude and random seed.
