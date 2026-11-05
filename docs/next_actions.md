# Next Actions

Last updated: 2026-10-21 (axial alpha plot verification; other features planned)

Implementation priority (2026-11-05): sink removal, then TOML-based setup,
then transverse velocity gradients. The user confirms stable no-sink runs
and nearly unchanged results for tested CFL values below `1/dim`; softening
sensitivity is still unverified. See the
[updated test report](no_sink_softening_benchmark.md#2026-11-05-user-reported-no-sink-and-cfl-results).
This supersedes earlier continuation-only CFL notes below.

## Research Stages Toward The Final Goal

The final goal is to measure DF and the transverse gravitational force on the
perturber in a flow with a velocity gradient perpendicular to the flow direction.
For a background velocity `v_gas = v_x(y) e_x`, these are `Fx` and `Fy`.

1. Validate the current uniform-velocity, uniform-density baseline against
   analytical DF calculations using the no-sink model. Assess resolution,
   inner-cutoff, and numerical stability; sink removal is now planned below.
2. Specify the transverse velocity profile and gradient strength, then extend
   the initial and inflow conditions and record those parameters in each case.
   The exact profile is not yet decided; a linear profile is not a requirement.
3. Calculate and compare flow-direction DF and the signed gradient-direction
   gravitational force across velocity-gradient cases. Use the uniform-flow
   case as the zero-gradient reference, and check the numerical sensitivity
   of both force components.

The velocity-gradient workflow is future work. The tasks below support the
current baseline-validation stage.

## Near-Term Implementation

### Requested feature changes (2026-10-20)

Implementation status is recorded per item below. The first axial alpha
plot is implemented on `dev/alpha-plot`; the other requested features remain
plans. A 2D alpha slice remains a future option.

#### Density perturbation plots

- Implemented first version: `plot_alpha_profile_3d.jl RUN_DIR LOG_LAMBDA`
  plots raw `alpha=rho/rho0-1` along x at `(y,z)=(y_p,z_p)`. It selects the
  nearest positive-time snapshot in log Lambda and records the actual time.
- Bilinear transverse interpolation uses at most four density rows; exact
  cell-center locations use direct values. Output is PNG plus a `.dat` table
  containing signed `x-x_p`, rho, alpha, and interpolation metadata.
- Existing signed-log density slices are unchanged. Additional axes, 2D raw
  alpha slices, coordinate normalization, and animations remain future options.
- Verified locally on 2026-10-21: 51 numerical assertions, synthetic PNG/table
  output, and extraction/rendering of positive-time output from a 612-cell
  PLUTO smoke run. The real-data densities matched a full-volume reference.
- Next validation: use positive-time production output to inspect the wake
  and compare the profile with the corresponding interpolated slice. Synthetic
  interpolation tests and successful rendering do not establish physical
  convergence of the simulation.

#### Transverse velocity gradient at the inflow boundary

- Add a configurable inflow speed varying perpendicular to the flow, e.g.
  `v_gas = vx(y) e_x` for inflow along `+x`. This supports measurement of `Fx`
  and the force along the gradient direction, `Fy` in this example.
- Decide the profile shape, reference velocity/location, gradient strength
  and units, and permitted velocity range. A linear profile is a candidate,
  not a settled requirement.
- Specify whether the same profile fills the initial domain or is introduced
  at the boundary into an initially uniform flow; document the resulting
  transient. Keep background density/pressure choices explicit.
- Propagate parameters through case generation, PLUTO inputs, summaries,
  sweep/launch wrappers, and analysis labels. Review box/runtime estimates
  currently based on one background Mach, and the treatment of transverse
  boundaries and any velocity reversal at the nominal inflow boundary.
- Likely scope: `init_3d.c`, `definitions_3d.h`, 3D generators/wrappers, and
  metadata consumers. Define the 2D scope explicitly before implementation.
- Future verification: zero gradient reproduces the uniform baseline;
  prescribed boundary velocities match the selected profile, including ghost
  cells; initial/boundary consistency, parameter validation, and short
  serial/MPI runs are checked before physical force comparisons.

#### Remove the central absorbing sink

- Remove the optional fluid-removal/relaxation feature referred to as the
  sink. Keep the fixed gravitational perturber, Plummer potential, `A_SOFT`,
  and force diagnostics. Sink removal does not mean removal of gravity.
- Audit and remove sink application/calls, sink-specific parameters and their
  indexing, generator/wrapper options, sink logs, tests, and active usage docs.
  Review `INTERNAL_BOUNDARY` after checking whether other code needs it.
- Likely scope includes `init_3d.c`, `definitions_3d.h`, 3D preparation/run
  scripts, the softening sweep, and generator tests. Search for dependencies
  before deletion rather than assuming that only the C function uses them.
- Define how old `pluto.ini` and `run_summary.txt` files with sink fields are
  handled. Preserve historical data and work logs, and retain the ability to
  analyze old outputs; do not silently reinterpret an old sink run as no-sink.
- Future verification: compile and smoke-test the resulting no-sink setup,
  check parameter indices and generated cases, and compare with the existing
  `SINK_RADIUS=0` baseline at matched settings. Ensure softening and force
  analysis still work.
- This supersedes the earlier plan to retain and tune the sink for new
  experiments. The sink remains implemented until this removal is performed.

#### Simulation setup from a configuration file

- Add a file-based setup interface so parameter exploration does not require
  editing tracked shell scripts or retyping long environment/CLI assignments.
  TOML is the preferred format candidate; the schema, parser, and command
  interface remain to be selected. This is not implemented.
- Let a short command select a setup file for preparation and subsequent
  local or batch execution. Keep `pluto.ini` as the generated PLUTO input;
  the setup file also describes generator-level controls and derived scales.
- Cover physical parameters (Mach, gamma, mass, density, sound speed,
  softening, and future velocity gradients), numerical controls (including
  CFL), resolution/box/runtime controls, and output settings. Define which
  build/MPI/Slurm settings belong in the file versus a machine-specific
  configuration; avoid coupling physical cases to one cluster.
- Track example configurations and selected reproducible benchmarks in Git.
  Put personal trial configurations in a dedicated ignored directory; choose
  its path and document how to promote a case into a tracked benchmark.
  Parameter changes should not require changes to executable scripts.
- Preserve the original setup file and the fully resolved effective settings
  with each run, including defaults, overrides, derived quantities, and code
  revision. Define relative-path resolution and existing-case/overwrite
  behavior so repeated commands cannot silently change an earlier run.
- Candidate precedence is explicit CLI overrides > file values > defaults.
  Decide how existing environment-variable workflows remain compatible and
  prevent inherited shell variables from silently overriding file values.
  Record the chosen precedence and resolved values in the run metadata.
- Validate types, ranges, unknown keys, and conflicting inputs (for example,
  `A_SOFT` versus `RSOFT_FRAC`) before generating or launching a case. Define
  behavior for old sink settings consistently with planned sink removal.
- Specify matched sweep lists and their expansion rules; preserve manifests
  and per-case resolved settings. Decide initial 3D coverage and any 2D
  compatibility explicitly. Reuse one configuration-resolution path across
  preparation, local execution, and Slurm wrappers.
- Likely scope: configuration loader/schema, generators and runner/submitter
  interfaces, example files, `.gitignore`, metadata, documentation, and tests.
- Future verification: equivalent legacy and file-based inputs produce the
  same generated parameters; precedence, validation, relative paths, sweep
  expansion, case preservation, and effective-setting records behave as
  documented. Check a short local run and later the remote wrapper workflow.

### No-sink variable-softening benchmark: remote verification, then production validation

The generator-level `A_SOFT` parameter, dedicated matched sweep, and radial
force diagnostic are implemented in `5e1472a` and have passed lightweight
local checks. **A remote CFL-only comparison is now user-reported: `0.2`
was running, while `0.4` stopped.** Completion and systematic remote
verification are not established. Follow the
[remote verification procedure](no_sink_softening_benchmark.md#remote-verification-to-perform)
for environment checks, short serial/MPI execution, logs and force analysis.
Record remote results before marking that stage complete.

First preserve both comparison runs' settings/logs and record the `0.2`
run's reached time and exit status. See the
[CFL comparison record](no_sink_softening_benchmark.md#2026-10-05-user-reported-cfl-comparison).
Other factors have not been tested in this comparison. Keep CFL fixed when
testing resolution, softening, or other numerical choices. Review the
generator's unchanged `CFL=0.4` default before further 3D RK2 runs.

After remote smoke tests pass, proceed to numerical validation:

- Start with a matched pair such as `A_SOFT_VALUES="2 1"`, `MACH=0.5`,
  `GAMMA=1.6666`, `LOG_LAMBDA_MAX=1.5`, `CELLS_PER_RBHL=4`; review the generated
  grid and boundary ratios before running. These are exploratory settings.
- Keep `SINK_RADIUS=0` and common parameters fixed; compare density, pressure,
  local Mach, timestep history and radial force profiles at matching times.
- Compare point and softened kernels and vary the force cutoff independently
  of `r_soft`; measure whether changes extend into the outer wake.
- Check box size and resolution convergence before interpreting any apparent
  stability or agreement with analytic DF. Do not infer a literature cutoff
  calibration or mark the Ostriker comparison complete from the smoke test.

### Pressure-collapse diagnostic

Goal:

- Identify where and when pressure or internal energy first becomes too small near the potential center in failing 3D runs.

Current state:

- `CS_ALERT_THRESHOLD` and `MACH_ALERT_THRESHOLD` diagnostics exist.
- The latest CFL-only comparison supports timestep instability as a leading
  candidate; energy cancellation has not been established as the initial cause.
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
- Continue this diagnosis with the no-sink model. The earlier proposal to
  tune the absorbing sink is superseded by the planned sink removal above;
  historical sink runs remain evidence about earlier behavior.
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
