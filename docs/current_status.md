# Current Status

Last updated: 2026-11-05 (sink removal and local baseline comparison)

Latest test update (2026-11-05): the user confirms no-sink calculations do
not break down, and results are nearly unchanged when varying CFL within
`CFL < 1/dim` in the tested conditions. Detailed run records and tolerances
were not supplied here. Softening sensitivity remains unverified. See the
[updated test report](no_sink_softening_benchmark.md#2026-11-05-user-reported-no-sink-and-cfl-results).
Implementation order: remove the sink, add TOML setup, then velocity gradients.
Earlier CFL continuation-only notes below are historical and are superseded
by this report; systematic MPI and physical-convergence checks remain open.

## Requested Work And Implementation Status

On 2026-10-20 the user requested four changes: plotting raw
`alpha=rho/rho0-1` (preferentially as a profile along an axis through the
perturber, with 2D slices still an option), a transverse velocity gradient
at the inflow boundary, removal of the central absorbing sink, and simulation
setup from a configuration file (TOML is the preferred candidate).
The file interface should avoid script edits and repeated long commands,
separate tracked examples from ignored trial setups, and retain effective
settings with each run. Its schema and override/compatibility rules are pending.
The gravitational perturber and variable softening are to remain.
The [feature plan](next_actions.md#requested-feature-changes-2026-10-20)
records scope, unresolved design choices, and future verification.
The first alpha plotting implementation is merged into local `main`:
`plot_alpha_profile_3d.jl` selects the nearest saved log Lambda and writes a
PNG plus numerical table for the x-axis through the perturber, interpolating
transversely and reading only the required density rows. Other axes, 2D alpha
slices, and time animations are not included in this first version.
The absorbing sink has been removed on `dev/remove-sink`. Velocity-gradient
inflow and file-based setup remain planned; TOML setup is the next feature.
Existing plotting and uniform inflow remain. Earlier sink-tuning plans are
superseded.

## Project Aim

The final goal is to calculate the gravitational force exerted by gas on a
softened point mass in a flow whose speed varies in a direction perpendicular
to the flow. The quantities of interest are both the flow-direction dynamical
friction (DF) and the gravitational force component along the transverse
velocity-gradient direction. Simulations use PLUTO, with force analysis in Julia.

For example, with flow along `+x` and its speed varying with `y`, the background
velocity is `v_gas = v_x(y) e_x`. The target force components on the perturber
are `Fx` (DF, positive along the relative background flow) and `Fy` (the signed
transverse gravitational force). The velocity profile, including whether it
is linear, and its gradient strength remain to be specified.

The current stage is validation with uniform background velocity and density:
compare the simulated DF against analytical calculations motivated by
Ostriker (1999), and assess numerical reliability before introducing the
transverse velocity gradient. Uniform-flow comparison is therefore a baseline
for the final study. The velocity-gradient flow is not yet implemented.

The 2D workflow remains useful for setup and debugging, but the main
quantitative comparison and final study should be treated as 3D problems.

## Implemented Workflows

- No-sink variable-softening benchmark (3D):
  - `A_SOFT = r_B/r_soft` controls softening independently of Mach
  - corrected arbitrary-`CS0` Bondi/BHL scales, derived-scale metadata and
    resolution/boundary warnings in `prepare_one_case_3d.sh`
  - matched non-accreting cases via `prepare_softening_sweep_3d.sh`
  - radial cumulative and shell forces for both point and softened kernels
    via `force_radial_profile_3d.jl`
  - PLUTO gravity, softening and one-case force semantics preserved; sink removed

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
  - `plot_alpha_profile_3d.jl` plots raw `rho/rho0-1` against `x-x_p` at the
    requested log Lambda; it records actual snapshot/time and interpolation
    weights in a companion `.dat` table
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

- The immediate benchmark now tests increased softening without a sink. The
  user reports an artificial-looking downstream hole with the smooth sink;
  the new benchmark instead models a non-accreting softened perturber.
- Implementation and local lightweight verification are complete; whether softening
  stabilizes a production run and preserves converged outer wakes/DF is still
  unverified. Softening is not identified with a force cutoff or a BH radius.

- The drag sign convention is currently:
  - `Fdf = Fx` for the configured `+x` ambient flow
  - `Fx` is the gravitational force on the perturber from the gas density perturbation
  - positive drag acts along the ambient gas velocity relative to the perturber
  - one-case analysis, sweep analysis, and diagnostic `dfdf = dfx` use the same convention
  - `--flow-dir` in sweep analysis changes region labels only, not the force sign
  - older one-case outputs and diagnostic plots need regeneration before comparison
- `force_from_run.jl` supports:
  - `--dimension auto`
  - `--dimension 2`
  - `--dimension 3`
- `sweep_force_plot.jl` supports:
  - `--dimension auto|2|3`
  - `--force-mode auto|axisym|2d|3d`
- For 3D runs, the preferred force calculation is a true 3D volume integral.
- For 2D runs, the direct comparison to Ostriker (1999) is provisional because the simulation is not a true 3D setup.
- The inspected 3D no-sink log shows Mach divergence followed by an explicit
  `NextTimeStep(): dt is too small` abort; it does not locate the first failure.
- No `CS_ALERT` appeared in the inspected failure, but later plots showed very small pressure near the origin for `gamma = 1.6666`.
- Near-isothermal settings such as `gamma = 1.00001` did not show the same pressure-collapse failure mode in the tested case.
- The 2026-10-05 CFL-only comparison makes timestep instability a leading
  candidate: the user reports `CFL=0.2` running and `0.4` stopping. Other
  factors have not been tested, and initial energy cancellation is not established.
  The original run used `r_soft=0.2475*r_B`, about two cells per softening
  radius, and no sink. See the [comparison record](no_sink_softening_benchmark.md#2026-10-05-user-reported-cfl-comparison).
- The central absorbing sink, its three active parameters and its runtime logs
  have been removed. INTERNAL_BOUNDARY is disabled; the inflow boundary and
  sound-speed/Mach diagnostics are preserved. Removed sink environment
  options are rejected, and old output remains analyzable.

## Verification Status

Verified locally:

- On 2026-11-05, sink-removal verification passed: 10 generator tests,
  69 radial-force assertions and 51 alpha-profile assertions. Old sink-disabled
  and new no-sink serial cases compiled and ran 10 steps on the same 612-cell
  grid at CFL=0.2. All 11 full-variable snapshots and dbl.out were byte-identical.
  Alpha and radial-force analyses matched exactly across old/new metadata.
  All 13 parameter indices matched generated labels; low-threshold runtime
  checks emitted both sound-speed and Mach alerts with no sink logs.

- On 2026-10-21, all 51 alpha-profile assertions passed, covering log-Lambda
  selection, off-center and exact-center interpolation, signed alpha,
  partial reads, both byte orders, numerical tables, and invalid input.
  The CLI/main rendering path produced PNG and `.dat` output from synthetic
  data and a positive-time snapshot of a new 612-cell serial PLUTO smoke run.
  At `t=0.000771561`, all 17 extracted densities exactly matched a separate
  full-volume four-cell average. This verifies the extraction/output path,
  not wake or force convergence. Details and artifact paths are in the
  2026-10-21 work-history entry.
- On 2026-10-01, case-generation regression tests covered legacy compatibility,
  arbitrary `CS0`, all derived scales, softening conflicts, warning/cell limits,
  case preservation, and matched no-sink sweeps. The default `CS0=1` generated
  `pluto.ini` was byte-for-byte identical to the pre-change generator output.
- Radial-force synthetic tests passed for uniform density, signed asymmetric
  perturbations, exact cutoff boundaries, shell/cumulative consistency, both
  kernels against direct integration, little/big endian multi-variable input,
  the CLI, and agreement with the existing one-case point-force calculation.
- An `A_SOFT=1`, `SINK_RADIUS=0` serial case compiled and ran three steps;
  the radial diagnostic read both initial and positive-time PLUTO output.

- On 2026-09-29, 97 synthetic-data assertions passed for the unified drag sign:
  one-case CLI output, 2D/3D and axisymmetric sweep calculations, split tables,
  normalization, and diagnostic force contributions. A synthetic `dfdf` PNG
  was generated and visually checked for upstream-negative/downstream-positive
  contributions and the `dFdf = dFx` label.
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
- Earlier Slurm wrapper changes were syntax-checked locally, and a remote run
  using `MPI_LAUNCHER=srun` compiled and launched. This predates the variable-
  softening benchmark and does not verify its remote execution.
- Julia plotting scripts loaded locally after the origin-overlay cleanup, and `--show-overlays` parsing was checked.

Partially verified or not yet verified:

- The user reports stable no-sink runs and nearly unchanged results for tested
  CFL values below `1/dim`. Detailed run records/tolerances and systematic
  remote/MPI verification are still missing. Softening sweeps and physical
  wake/force convergence remain unverified.

- Full PNG generation from `sweep_force_plot.jl` was not verified locally because the local Julia environment lacks `Plots`.
- Remote verification of updated 3D sweep plotting should be done after relevant jobs finish.
- `animate_density.jl` still visualizes a 2D slice and is not yet a mature 3D visualization workflow.
- Sensitivity of force results to the inner cutoff choice has not been measured.
- The full 3D Mach sweep comparison against the Ostriker model remains open.
- The pressure-collapse mechanism has not yet been captured by a dedicated pressure/internal-energy runtime alert.
- Historical sink-enabled runs retain their original fluid model and must be
  distinguished from new non-accreting cases.

## Known Issues And Risks

- Older 3D runs and the unchanged 2D generator use a BHL formula assuming
  `CS0=1`. Their non-unit-`CS0` metadata/domain/runtime must not be mixed silently
  with newly generated matched cases.
- Single-case and Mach-sweep generation retain different `GAMMA` defaults;
  explicitly match gamma when comparing workflows. Large softening can exceed
  the useful box size even when the cell-count limits are satisfied.

- The physical choice of inner cutoff is still effectively `rcut = rbhl`; this is a provisional analysis choice, not a validated physical conclusion.
- The 2D-to-3D axisymmetric reconstruction in sweep analysis is useful as a diagnostic but may not represent the physics assumed by Ostriker (1999).
- The old `problem.md` noted an inconsistency between `force_from_run.jl` and `sweep_force_plot.jl`; recent work reduced this by adding unified 2D/3D paths, but force-mode choices still need to be interpreted carefully.
- 3D density diagnostics show a suspicious low-density hole-like structure near the potential center. It appears numerical from the animation behavior, and at least one comparable-resolution 2D run did not show the same feature.
- Some 3D runs collapse to extremely small timesteps. The latest comparison
  supports CFL sensitivity; earlier low-pressure observations do not establish
  whether pressure collapse initiates the failure or follows numerical instability.
- Earlier near-isothermal tests such as `gamma = 1.00001` did not show the same
  failure mode, but EOS and other factors have not been varied in the latest
  CFL-only comparison. The generator still defaults to `CFL=0.4`.
- Do not mix an old sink parameter file with new source/definitions. Preserve
  the original case for historical reruns and generate fresh non-accreting cases.
- Simply increasing `cells_per_rbhl` is expensive in 3D because the total cell count scales roughly as the cube of the linear resolution. AMR or another local-refinement strategy should be investigated before relying on brute-force uniform-grid convergence.
