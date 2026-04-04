# PLUTO Dynamical Friction Setup

This repository prepares and runs 2D PLUTO hydrodynamics cases with a softened point-mass potential, then post-processes the output in Julia to estimate dynamical friction.

## Script roles

Shell scripts live under `scripts/`.

- `scripts/prepare_one_case.sh`
  - Generate one case directory under `runs/`.
- `scripts/prepare_mach_sweep.sh`
  - Generate a Mach sweep and write a manifest file under `runs/manifests/`.
- `scripts/run_one_case_local.sh`
  - Build and run one prepared case locally.
- `scripts/submit_one_case_slurm.sh`
  - Submit one prepared case to Slurm with `sbatch --wrap`.
- `scripts/submit_sweep_serial.sh`
  - Submit all cases listed in one manifest, one case per Slurm job, chained with dependencies.
- `scripts/submit_sweep_batches.sh`
  - Submit all cases listed in one manifest in batches, chained with dependencies.

Julia scripts:

- `force_from_run.jl`
  - Compute the force from one run output.
- `sweep_force_plot.jl`
  - Aggregate force results across a sweep.
- `animate_density.jl`
  - Visualize density snapshots.

## Typical workflows

### Prepare one case

```bash
MACH=0.1 MP=1.0 LOG_LAMBDA_MAX=2.0 CELLS_PER_RBHL=8 \
  ./scripts/prepare_one_case.sh
```

This creates a directory like `runs/mach0.100_mp1.000_ll2.000_rbhl8.0/`.

### Run one case locally

```bash
./scripts/run_one_case_local.sh runs/mach0.100_mp1.000_ll2.000_rbhl8.0
```

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

### Submit a sweep to Slurm in batches

```bash
BATCH_SIZE=5 ./scripts/submit_sweep_batches.sh \
  runs/manifests/mach0.1-3.0_step0.1_mp1.0_ll2.0_rbhl8.0.txt
```

## Notes

- `runs/` is treated as generated output and is ignored by Git.
- Slurm job names are derived from case names.
- Slurm resource settings are controlled by environment variables such as `SLURM_PARTITION` and `SLURM_TIME_LIMIT`.
