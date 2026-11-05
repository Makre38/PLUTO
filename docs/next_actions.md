# Next Actions

Last updated: 2026-11-05 (TOML setup implemented)

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
   inner-cutoff, and numerical stability; sink removal is recorded below.
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
plot is merged into local main and the sink is removed on `dev/remove-sink`.
TOML setup is implemented on `dev/toml-setup`; velocity gradients remain planned. A 2D alpha slice remains a
future option.

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

- Implemented on `dev/remove-sink` (2026-11-05): removed fluid relaxation,
  sink-specific parameters/logs and wrapper settings. Disabled INTERNAL_BOUNDARY
  while preserving user-defined inflow, gravity, softening and diagnostics.
- Removed sink environment options are rejected before any case/manifest is
  created, including empty/zero values. Unset them for new generation.
- Keep historical cases intact. Analyze their output normally; rerun old models
  only with the original source/definitions/parameter files together. Never
  reinterpret an old sink-enabled case as a new non-accreting case.
- TOML setup is implemented; transverse velocity gradients are next. Softening
  sensitivity remains a separate unverified numerical study.

#### Simulation setup from a configuration file

- Implemented on `dev/toml-setup` in `e0f1a14`. See [toml_setup.md](toml_setup.md)
  for the confirmed schema, defaults, examples, validation and record format.
  The initial Python loader/tests have been replaced by Julia. The readable
  [test report](test_reports/toml_setup_julia.md) describes every scenario.
- Julia standard library only; use `bash scripts/prepare_from_toml.sh FILE`.
  3D single cases and one-parameter Mach/softening lists reuse the existing
  generator. Execution, MPI and Slurm remain separate.
- Original/effective configuration and provenance are saved per case. Existing
  destinations, unknown keys, conflicts and invalid values are rejected before
  publication. Personal files belong in ignored `configs/local/`.
- Local integration/regression checks and a 10-step serial run passed. Remote
  Julia availability, MPI/Slurm execution and production studies remain open.
- Further options (2D, multiple sweep axes, per-key CLI overrides and execution
  profiles) are outside this first version. Velocity-profile design is next.

### No-sink variable-softening benchmark: remote verification, then production validation

The generator-level `A_SOFT` parameter, dedicated matched sweep, and radial
force diagnostic are implemented in `5e1472a` and have passed lightweight
local checks. The latest user report confirms no-sink stability and nearly
unchanged results for tested CFL values below `1/dim`; softening sensitivity
is unverified. Preserve the test configurations, logs, comparison quantities
and tolerances when available. Systematic remote/MPI checks remain open;
follow the [verification procedure](no_sink_softening_benchmark.md#remote-verification-to-perform)
using the new interface (no sink options or logs).

Keep CFL fixed while testing resolution and softening. The generator still
writes `CFL=0.333` by default and accepts explicit CFL input. The removal comparison
used CFL=0.2 by changing only temporary case input files. CFL is configurable
through the TOML interface.

After remote smoke tests pass, proceed to numerical validation:

- Start with a matched pair such as `A_SOFT_VALUES="2 1"`, `MACH=0.5`,
  `GAMMA=1.6666`, `LOG_LAMBDA_MAX=1.5`, `CELLS_PER_RBHL=4`; review the generated
  grid and boundary ratios before running. These are exploratory settings.
- Use the non-accreting model and keep common parameters fixed; compare density, pressure,
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
  tune the absorbing sink is superseded by the completed sink removal above;
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
