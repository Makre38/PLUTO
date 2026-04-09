# Change Log

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
