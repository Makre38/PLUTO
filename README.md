# PLUTO Dynamical Friction Setup

This repository prepares and runs 2D PLUTO hydrodynamics cases with a softened point-mass potential, then post-processes the output in Julia to estimate dynamical friction.

## Script roles

Shell scripts live under `scripts/`.

- `scripts/prepare_one_case.sh`
  - Generate one case directory under `runs/`.
- `scripts/prepare_one_case_3d.sh`
  - Generate one 3D Cartesian case directory under `runs_3d/`.
- `scripts/prepare_mach_sweep.sh`
  - Generate a Mach sweep and write a manifest file under `runs/manifests/`.
- `scripts/prepare_mach_sweep_3d.sh`
  - Generate a 3D Mach sweep and write a manifest file under `runs_3d/manifests/`.
- `scripts/run_one_case_local.sh`
  - Build and run one prepared case locally.
- `scripts/run_one_case_local_3d.sh`
  - Build and run one prepared 3D case locally, optionally with MPI via `MPI_TASKS`.
- `scripts/submit_one_case_slurm.sh`
  - Submit one prepared case to Slurm with `sbatch --wrap`.
- `scripts/submit_one_case_slurm_3d.sh`
  - Submit one prepared 3D case to Slurm.
- `scripts/submit_sweep_serial.sh`
  - Submit all cases listed in one manifest, one case per Slurm job, chained with dependencies.
- `scripts/submit_sweep_serial_3d.sh`
  - Submit all 3D cases listed in one manifest, one case per Slurm job, chained with dependencies.
- `scripts/submit_sweep_windowed_3d.sh`
  - Submit all 3D cases listed in one manifest, one case per Slurm job, with a bounded number of concurrent jobs.
- `scripts/submit_sweep_batches.sh`
  - Submit all cases listed in one manifest in batches, chained with dependencies.
- `scripts/submit_sweep_batches_3d.sh`
  - Submit all 3D cases listed in one manifest in batches.

Julia scripts:

- `force_from_run.jl`
  - Compute the force from one run output.
- `force_from_run_3d.jl`
  - Compute `Fx` from one 3D run output using the full 3D density field.
- `sweep_force_plot.jl`
  - Aggregate force results across a sweep.
- `animate_density.jl`
  - Visualize density snapshots.
- `plot_3d_diagnostics.jl`
  - Plot 3D diagnostic slices through the perturber position, with `rsoft` and `rcut` overlays.

## Typical workflows

### Prepare one case

```bash
MACH=0.1 MP=1.0 LOG_LAMBDA_MAX=2.0 CELLS_PER_RBHL=8 \
  ./scripts/prepare_one_case.sh
```

This creates a directory like `runs/mach0.100_mp1.000_ll2.000_rbhl8.0/`.

### Prepare one 3D case

```bash
MACH=0.5 MP=1.0 LOG_LAMBDA_MAX=1.0 CELLS_PER_RBHL=2 N_OUTPUT=10 \
  ./scripts/prepare_one_case_3d.sh
```

This creates a directory like `runs_3d/mach0.500_mp1.000_ll1.000_rbhl2.0_3d/`.

3D cases run per-step runtime alerts through PLUTO `Analysis()`. If the
minimum local sound speed falls below `CS_ALERT_THRESHOLD`, the code writes the
cell location and local state to `logs/diagnostics_cs_alert_3d.rankNNNN.dat` and the runtime
log. If the maximum local Mach number exceeds `MACH_ALERT_THRESHOLD`, it writes
to `logs/diagnostics_mach_alert_3d.rankNNNN.dat` and the runtime log. The default
thresholds are `CS_ALERT_THRESHOLD=1.0e-6` and `MACH_ALERT_THRESHOLD=10.0`; set
either threshold to `0.0` to disable that diagnostic. `CS_ALERT_EVERY_STEPS` and
`MACH_ALERT_EVERY_STEPS` control repeated alert logging while a condition
persists. `UserDefBoundary(..., side == 0)` calls are recorded in
`logs/sink_boundary_3d.rankNNNN.dat`, including the number of cells inside the
configured sink radius on that rank.

A central sink-like sponge can be enabled for 3D cases by setting
`SINK_RADIUS`. Inside that radius, density is relaxed toward
`SINK_RHO_FLOOR`, velocity toward `SINK_VELOCITY_FACTOR` times the ambient
inflow, and pressure toward the local nearly-isothermal value over
`SINK_TIMESCALE`. The default `SINK_RADIUS=0.0` disables the sink, and the
default `SINK_VELOCITY_FACTOR=1.0` preserves the original ambient-inflow sink
velocity. Use `SINK_VELOCITY_FACTOR=0.0` to relax the sink velocity toward rest.

```bash
SINK_RADIUS=0.05 SINK_TIMESCALE=0.01 SINK_RHO_FLOOR=1.0e-6 \
SINK_VELOCITY_FACTOR=0.0 \
  MACH=0.5 MP=1.0 LOG_LAMBDA_MAX=1.0 CELLS_PER_RBHL=2 N_OUTPUT=10 \
  ./scripts/prepare_one_case_3d.sh
```

### Run one case locally

```bash
./scripts/run_one_case_local.sh runs/mach0.100_mp1.000_ll2.000_rbhl8.0
```

### Run one 3D case locally

```bash
MPI_TASKS=4 ./scripts/run_one_case_local_3d.sh \
  runs_3d/mach0.500_mp1.000_ll1.000_rbhl2.0_3d
```

For MPI runs, `MPI_LAUNCHER` selects the launcher used after compilation.
The default is `mpirun`; on Slurm systems, `MPI_LAUNCHER=srun` may be required.
The runner writes build and run stage markers to `logs/run_stage_3d.log` in the
case directory.

### Prepare a Mach sweep

```bash
MACH_MIN=0.1 MACH_MAX=3.0 MACH_STEP=0.1 MP=1.0 LOG_LAMBDA_MAX=2.0 CELLS_PER_RBHL=8 \
  ./scripts/prepare_mach_sweep.sh
```

This writes a manifest like:

```text
runs/manifests/mach0.1-3.0_step0.1_mp1.0_ll2.0_rbhl8.0.txt
```

### Submit one case to Slurm

```bash
SLURM_PARTITION=c79 \
SLURM_TIME_LIMIT=30-00:00:00 \
./scripts/submit_one_case_slurm.sh runs/mach0.100_mp1.000_ll2.000_rbhl8.0
```

### Submit a sweep to Slurm, one case per job

```bash
./scripts/submit_sweep_serial.sh runs/manifests/mach0.1-3.0_step0.1_mp1.0_ll2.0_rbhl8.0.txt
```

### Submit a 3D case to Slurm

```bash
MPI_TASKS=8 ./scripts/submit_one_case_slurm_3d.sh \
  runs_3d/mach0.500_mp1.000_ll1.000_rbhl2.0_3d
```

If the cluster expects Slurm to launch MPI tasks, use:

```bash
MPI_TASKS=8 MPI_LAUNCHER=srun ./scripts/submit_one_case_slurm_3d.sh \
  runs_3d/mach0.500_mp1.000_ll1.000_rbhl2.0_3d
```

### Submit a 3D sweep to Slurm with bounded concurrency

```bash
MPI_TASKS=8 MAX_CONCURRENT_JOBS=4 \
  ./scripts/submit_sweep_windowed_3d.sh \
  runs_3d/manifests/mach0.1-3.0_step0.1_mp1.0_ll2.0_rbhl2.0_3d.txt
```

Alternatively, cap the total requested MPI tasks:

```bash
MPI_TASKS=8 MAX_TOTAL_TASKS=32 \
  ./scripts/submit_sweep_windowed_3d.sh \
  runs_3d/manifests/mach0.1-3.0_step0.1_mp1.0_ll2.0_rbhl2.0_3d.txt
```

### Submit a sweep to Slurm in batches

```bash
BATCH_SIZE=5 ./scripts/submit_sweep_batches.sh \
  runs/manifests/mach0.1-3.0_step0.1_mp1.0_ll2.0_rbhl8.0.txt
```

### Plot 3D diagnostic slices

```bash
julia plot_3d_diagnostics.jl \
  runs_3d/mach0.500_mp1.000_ll1.000_rbhl2.0_3d
```

The default plot shows signed-log fractional density perturbations on the
`z = x3p` and `y = x2p` slices. Force-contribution views are available with
`--quantity dfx`, `--quantity dfy`, or `--quantity dfdf`. Velocity-magnitude
and local-Mach views are available with `--quantity speed` and `--quantity mach`.
Density, speed, and Mach animations can be generated with `--animate`, which
writes an HTML player and PNG frames by default. Use `--stride N` and
`--max-frames N` to limit animation size. The perturber marker and `rsoft` /
`rcut` radius overlays are hidden by default; add `--show-overlays` to draw
them.

## Notes

- `runs/` is treated as generated output and is ignored by Git.
- `runs_3d/` is likewise treated as generated output.
- Slurm job names are derived from case names.
- Slurm resource settings are controlled by environment variables such as `SLURM_PARTITION` and `SLURM_TIME_LIMIT`.
