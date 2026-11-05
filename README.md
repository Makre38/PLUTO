# PLUTO Dynamical Friction Setup

This repository prepares and runs 2D and 3D PLUTO hydrodynamics cases with a softened point-mass potential, then post-processes the output in Julia to estimate dynamical friction.

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
- `scripts/prepare_softening_sweep_3d.sh`
  - Generate matched no-sink 3D cases varying only `A_SOFT`, with a manifest under `runs_3d_softening/manifests/` by default.
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
- `force_radial_profile_3d.jl`
  - Compute cumulative and shell gravitational forces with both point-mass and softened kernels, without changing the existing one-case analysis.
- `sweep_force_plot.jl`
  - Aggregate force results across a sweep.
- `animate_density.jl`
  - Visualize density snapshots.
- `plot_3d_diagnostics.jl`
  - Plot 3D diagnostic slices through the perturber position, with `rsoft` and `rcut` overlays.
- `plot_alpha_profile_3d.jl`
  - Plot raw `alpha=rho/rho0-1` along the x-axis through the perturber at a requested `log Lambda`, and save the numerical profile.

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

A central smooth absorbing sink can be enabled for 3D cases by setting
`SINK_RADIUS`. Inside that radius, density and pressure are relaxed toward the
initial ambient values, and all velocity components are relaxed toward zero.
The relaxation strength is
`alpha = (1 - exp(-dt/SINK_TIMESCALE)) * max(0, 1 - r/SINK_RADIUS)^SINK_TAPER_POWER`,
so the sink tapers smoothly to zero at `SINK_RADIUS`. The default
`SINK_RADIUS=0.0` disables the sink, and the default `SINK_TAPER_POWER=2.0`
uses a quadratic radial taper.

```bash
SINK_RADIUS=0.05 SINK_TIMESCALE=0.01 SINK_TAPER_POWER=2.0 \
  MACH=0.5 MP=1.0 LOG_LAMBDA_MAX=1.0 CELLS_PER_RBHL=2 N_OUTPUT=10 \
  ./scripts/prepare_one_case_3d.sh
```

### No-sink, variable-softening benchmark

This benchmark studies a non-accreting gravitational perturber: increase the
softening radius to test numerical stability and the sensitivity of the outer
wake and drag. The softening radius is neither a BH horizon nor an accretion
radius. The existing sink is retained for other experiments.

The 3D generator uses these scales (G = 1, V = Mach * CS0):

```text
r_B    = MP / CS0^2
r_BHL  = MP / (CS0^2 * (1 + Mach^2))
A_SOFT = r_B / r_soft
r_soft = r_B / A_SOFT                 when A_SOFT is supplied
r_soft = RSOFT_FRAC * r_BHL           otherwise (RSOFT_FRAC defaults to 0.25)
```

`A_SOFT` is a positive case-generation parameter; smaller values mean larger
softening. PLUTO still receives only `RSOFT`, and its Plummer potential is
unchanged. Explicitly supplying both `A_SOFT` and `RSOFT_FRAC` is an error.
At `CS0=1`, legacy cases retain their grid, runtime, softening, and case names.
For `CS0!=1`, the corrected `r_BHL` also changes the derived grid, box and runtime;
case names gain a `cs...` suffix. The 2D generator is unchanged and still assumes
`CS0=1` in its BHL scale.

For one case:

```bash
A_SOFT=1 SINK_RADIUS=0 MACH=0.5 GAMMA=1.6666 \
  LOG_LAMBDA_MAX=1.5 CELLS_PER_RBHL=4 RUNS_DIR=./runs_3d_softening \
  ./scripts/prepare_one_case_3d.sh
```

For a first matched pair, generate the cases with:

```bash
A_SOFT_VALUES="2 1" MACH=0.5 GAMMA=1.6666 \
  LOG_LAMBDA_MAX=1.5 CELLS_PER_RBHL=4 N_OUTPUT=10 \
  RUNS_DIR=./runs_3d_softening_pair ./scripts/prepare_softening_sweep_3d.sh
```

The wrapper always forces `SINK_RADIUS=0`, even if another value is inherited.
It accepts a whitespace-separated `A_SOFT_VALUES` list and otherwise inherits
the one-case defaults. Its default list, `10 3 1 0.3 0.1`, is exploratory, not
physically calibrated; the largest softening radii may trigger box warnings.
Unset `A_SOFT` and `RSOFT_FRAC` when using this wrapper. All common parameters,
including the box, grid, gamma and output times, are identical within a sweep.
These commands only generate cases; execution uses the existing runners.

`A_SOFT` case names include `asoft...`. Existing directories for these cases
are never overwritten; use a fresh `RUNS_DIR` for a repeat experiment with
different common settings. The dedicated sweep creates a unique manifest and
records each successfully generated case, even if a later case fails.
`prepare_mach_sweep_3d.sh` also forwards `A_SOFT` without injecting a conflicting
legacy `RSOFT_FRAC` default. Set `GAMMA` explicitly for comparisons across
workflows: the one-case and Mach-sweep scripts have different legacy defaults.

`run_summary.txt` records `r_bondi`, `rbhl`, `a_soft`, `rsoft`, the ratios
`rsoft_over_rbondi` and `rsoft_over_rbhl`, and actual grid-resolution measures
`cells_per_{rsoft,rbondi,rbhl}_{x,y,z}`. It also records distances from the
perturber to each boundary as `boundary_{xmin,xmax,ymin,ymax,zmin,zmax}_over_rsoft`.

Warnings use `MIN_CELLS_PER_RSOFT=2` cells per radius and
`MIN_BOUNDARY_OVER_RSOFT=4` softening radii to each boundary by default.
These configurable thresholds are numerical heuristics, not physical criteria
or convergence guarantees. They never enlarge the box or grid automatically;
`WARN_CELLS` and `HARD_CELLS` still apply.

### Radial force diagnostic

```bash
julia force_radial_profile_3d.jl CASE_DIR 1.5 --bins 64
julia force_radial_profile_3d.jl CASE_DIR --snapshot 0 \
  --r-cuts 0,0.1,0.3,1,3,10 --output radial.dat
```

The optional positional target selects the nearest positive-time snapshot in
`log(CS0*t/r_BHL)`; its default is the run's `log_lambda_max`. `--snapshot` selects
an exact dump index and can inspect the initial state. Use either selection
method, and either `--bins` or `--r-cuts`. Cutoff values are in code length units.
The default 64 linear bins span zero to just beyond the farthest cell center,
giving 65 cumulative-force rows. Custom cutoffs must be nonnegative and strictly
increasing. No plotting packages are needed.

The output defaults to `CASE_DIR/force_radial_profile_3d.NNNN.dat` and contains:

- `r_cut`, ratios to `r_B`, `r_BHL`, `r_soft`, and `r_shell_outer`;
- `Fx_point`, `Fy_point`, `Fz_point` using `r_vec/r^3`;
- `Fx_soft`, `Fy_soft`, `Fz_soft` using `r_vec/(r^2+r_soft^2)^(3/2)`;
- the corresponding `dF*_point_shell` and `dF*_soft_shell` contributions.

Both kernels use `rho-rho0` and the force-on-perturber sign convention. For `+x`
ambient flow, `Fx` is positive drag. Cumulative values integrate `r > r_cut`;
shells cover `r_cut < r <= r_shell_outer`. The final shell includes the remaining
finite domain (`Inf` denotes no further radial bound). A cell exactly at the
perturber is excluded. Cells are binned once, then summed from outside inward.

`r_soft` regularizes the potential, `r_cut` selects the integration region, and
`r_sink` controls modification of the fluid. These are independent concepts.
The existing force scripts still use the point-mass kernel with `r_cut=r_BHL`
(including cells exactly on the cutoff). The new tool makes no literature-based
identification such as `r_cut=2.25*r_soft`. The stored `rbhl` is preserved when
reading older runs; a mismatch with the corrected formula is warned about when
Mach metadata is available. Regenerate old non-unit-`CS0` cases before using
them as matched benchmarks.

Lightweight regression checks:

```bash
python3 tests/test_softening_generation.py -v
julia --startup-file=no tests/test_force_radial_profile_3d.jl
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

### Plot an axial density-perturbation profile

```bash
julia plot_alpha_profile_3d.jl RUN_DIR 2.0
# Optional output name (the numerical table uses the same stem):
julia plot_alpha_profile_3d.jl RUN_DIR 2.0 --output figures/alpha_ll2.png
```

The second argument is the requested `log Lambda = ln(t*cs0/r_BHL)`.
The script selects the closest **positive-time** snapshot in log Lambda;
it does not interpolate in time. A tie selects the first matching entry in
`dbl.out`. Targets outside the available time range select the closest saved
snapshot. Actual time, actual log Lambda, requested log Lambda, and snapshot
index are shown in the plot and console/table metadata. An initial-only run
cannot be plotted by this interface.

The horizontal axis is the signed code-unit coordinate `x-x_p`. The vertical
axis is raw `alpha=rho/rho0-1`, using the run's background `rho0`, with negative
values retained and a zero reference line. This differs from the signed-log
density view in `plot_3d_diagnostics.jl`.

At each x cell center, density is interpolated in y and z to the line
`(y,z)=(y_p,z_p)` from `run_summary.txt`. If the line lies on transverse cell
centers, those values are used directly. For an even, origin-symmetric y/z
grid, this is the average of the four surrounding rows. No extrapolation
outside the transverse cell-center range is allowed; the table records the
sampled indices, coordinates, and weights. There is no averaging along x.

Outputs default to `RUN_DIR/alpha_profile_x.NNNN.png` and `.dat`, where
`NNNN` is the selected snapshot index. Repeating a selection with the same
output path replaces these files. The table has commented metadata followed
by columns `x x_minus_xp rho alpha`. It can be transferred for further analysis
without moving the full snapshot.

This initial version supports 3D Cartesian PLUTO `single_file` double output
with little or big endian storage. Only the required rho rows (at most four)
are read using file offsets, so working data memory scales with `Nx`, not the
3D volume. Nonfinite or negative density in sampled rows produces an error.
Plots.jl is required for PNG rendering. Numeric tests do not load Plots:

```bash
julia --startup-file=no tests/test_alpha_profile_3d.jl
# Also exercise the CLI and PNG output in an environment with Plots:
GKSwstype=100 julia --startup-file=no tests/test_alpha_profile_3d.jl --plot
```

## Drag sign convention

`Fx` is the x-component of the gravitational force exerted by the gas density
perturbation on the perturber. Positive drag means that this force acts along
the ambient gas velocity relative to the perturber, reducing their relative
motion. With `u_rel = v_gas - v_perturber`, the general definition is
`Fdf = F_perturber dot (u_rel / |u_rel|)` for nonzero ambient relative velocity.

The current setup has a stationary perturber and ambient flow along `+x`
(`vx = Mach * cs0` for positive Mach), so all force analysis uses `Fdf = Fx`.
An excess of gas on the downstream (`x > x_p`) side contributes positively;
an excess on the upstream (`x < x_p`) side contributes negatively. The
diagnostic quantity `dfdf` consequently equals `dfx`.

In sweep plots, `--flow-dir` controls upstream/downstream labels only; it does
not change the sign of `Fdf`. A reversed ambient flow would require projecting
the force along that reversed direction (`Fdf = -Fx` for `-x` flow).

Older one-case outputs and `dfdf` diagnostic plots used `Fdf = -Fx`; regenerate
them before comparing with the current convention. Sweep outputs generated
before the June 29, 2026 sign correction also used the older convention.

## Notes

- `runs/` is treated as generated output and is ignored by Git.
- `runs_3d/` is likewise treated as generated output.
- Slurm job names are derived from case names.
- Slurm resource settings are controlled by environment variables such as `SLURM_PARTITION` and `SLURM_TIME_LIMIT`.
