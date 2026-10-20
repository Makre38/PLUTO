# Next Actions

Last updated: 2026-10-20 (planned plotting, velocity-gradient inflow, and sink removal)

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

### Requested feature changes (2026-10-20; planning only)

The following work is requested but **not implemented**. This update only
records the scope, open choices, and future verification. The preference for
an axial profile is not a final decision to exclude 2D slices.

#### Density perturbation plots

- Add plots of `alpha(t, x) = rho(t, x)/rho0 - 1`, using the case's background
  density `rho0`. Uniform gas must give zero; underdensities must remain negative.
- Prefer a one-dimensional profile along an axis through the perturber as
  the initial design candidate. Keep a two-dimensional slice through the
  perturber as an alternative or optional view.
- Existing `plot_3d_diagnostics.jl` density views use
  `sign(alpha)*log10(1+abs(alpha))`. Label raw alpha separately so it is not
  confused with that transformed quantity or with the sink relaxation factor.
- Decide which axis to sample (flow direction first is a candidate; transverse
  direction is useful for the later shear flow), snapshot/time selection,
  coordinate normalization, and output format before implementation.
- Define how a line through the actual perturber position is sampled when it
  lies between cell centers: interpolation versus nearest-cell sampling must
  be explicit, with sampled coordinates recorded.
- Likely scope: `plot_3d_diagnostics.jl` or a dedicated profile script, shared
  snapshot/metadata readers, usage documentation, and focused plotting tests.
- Future verification: synthetic uniform and known signed density fields,
  nonzero perturber coordinates and off-grid positions, agreement with the
  corresponding slice, and one real-output plot. Account for large 3D files
  when choosing how to read only the required data.

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
