# Decisions

Last updated: 2026-10-20 (planned feature changes)

## Physical Setup

- Use code units:
  - `rho0 = 1`
  - `cs = 1`
  - `G = 1`
- Use the perturber mass notation `M_p`, following Ostriker (1999).
- For 3D case generation, distinguish the Bondi and BHL scales:
  - `r_B = M_p / cs0^2`
  - `r_BHL = M_p / [cs0^2 (1 + Mach^2)]`, with `V = Mach * cs0`
  - the older expression `M_p / (1 + Mach^2)` assumes `cs0=1`; the unchanged
    2D generator still uses that assumption
- Treat `r_BHL` as the physical inner scale used to organize force analysis.
- Treat `r_s` as the numerical softening length used to regularize the potential near the origin.

## No-Sink Variable-Softening Benchmark

- Model a non-accreting softened gravitational perturber to study whether
  regularizing the central flow stabilizes the run and leaves converged outer
  wake and force results. This is not a BH accretion model.
- Introduce generator-level `A_SOFT = r_B / r_soft`; for this mode set
  `r_soft = r_B / A_SOFT`. PLUTO continues to receive `RSOFT` and uses the
  unchanged Plummer potential.
- Preserve `r_soft = RSOFT_FRAC * r_BHL` when `A_SOFT` is absent; fail if both
  parameters are explicitly supplied. Preserve legacy `CS0=1` generation.
- The original implementation retained the sink and forced `SINK_RADIUS=0`
  in the dedicated softening sweep. On 2026-10-20 the user requested removal
  of the sink feature; this supersedes the retention policy. Removal is
  planned, not implemented. The gravitational perturber and softening remain.
- Record derived scales, actual cells per radius, and all boundary distances
  relative to softening. Default warning thresholds (2 cells per radius,
  4 radii to a boundary) are configurable numerical heuristics. Do not resize
  the domain/grid automatically or override the cell-count limits.
- Keep `r_B`, `r_BHL`, `r_soft`, force cutoff `r_cut`, and sink radius `r_sink`
  distinct. Add no literature calibration or fixed relationship between
  `r_cut` and `r_soft`.
- Use the separate radial diagnostic to compare point and softened force
  kernels, cumulative outside each cutoff and in radial shells. Preserve the
  existing one-case and sweep-analysis semantics.
- Treat compilation and short smoke runs as implementation checks only;
  long-time stability, physical convergence and analytical agreement remain
  open numerical questions.

## Dimensional Strategy

- Use 2D simulations for setup, debugging, and qualitative diagnostics.
- Treat the main physical comparison to Ostriker (1999) as fundamentally 3D.
- Add and maintain a separate 3D Cartesian workflow rather than trying to make 2D results carry the final interpretation.

## Output And Analysis

- Planned (2026-10-20): add raw density perturbation `alpha=rho/rho0-1`
  plotting. An axis through the perturber is the preferred initial candidate;
  a 2D slice remains an alternative. Axis choice and off-grid sampling are
  not yet decided. Distinguish raw alpha from the existing signed-log view.
- Use PLUTO `double` binary output for the current workflow.
- Reconsider HDF5 only if richer metadata, 3D production data sharing, or a longer-lived analysis pipeline requires it.
- Keep force calculation in Julia rather than PLUTO so diagnostics can be recomputed without rerunning simulations.
- Use `log_Lambda = ln(cs t / r_BHL)` as the main time-like comparison variable.
- Select snapshots nearest to requested `log_Lambda` values during post-processing.
- Define positive drag as force on the perturber along the ambient gas velocity
  relative to it: `Fdf = F_perturber dot (u_rel / |u_rel|)`, where
  `u_rel = v_gas - v_perturber` is nonzero.
- Use `Fdf = Fx` for the configured `+x` ambient flow in one-case analysis,
  sweep analysis, and diagnostic plots (`dfdf = dfx`). `Fx` is the gravitational
  force from the gas density perturbation on the perturber.
- Sweep `--flow-dir` is a region-label option, not a sign-conversion option.
  Reversed ambient flow would require `Fdf = -Fx` instead.
- Regenerate outputs made with the old `Fdf = -Fx` convention before comparison.

## Force Calculation

- For true 3D runs, use the full 3D density field and volume element.
- For 2D runs, keep any 2D-to-3D reconstructed force interpretation clearly provisional.
- Keep `rcut = rbhl` as the current default inner cutoff, but treat this as an open analysis choice that needs sensitivity tests.
- Prefer `force_from_run.jl` as the unified one-case analysis entry point.
- Keep `force_from_run_3d.jl` only as a simple cross-check unless it becomes unnecessary.

## Run Generation

- Planned (2026-10-20): accept simulation setup files, with TOML as the
  preferred format candidate, while continuing to generate `pluto.ini`.
  Track examples/benchmarks, keep personal trial setups in an ignored
  directory, and archive original plus effective settings per run. Candidate
  precedence is explicit CLI overrides > file > defaults; environment-variable
  compatibility, schema, parser, and sweep rules are not yet decided. See
  [the setup-file plan](next_actions.md#simulation-setup-from-a-configuration-file).
- Planned (2026-10-20): support an inflow velocity gradient perpendicular
  to the flow, with zero gradient recovering the uniform baseline. Profile
  shape/strength and treatment of the initial domain remain undecided. See
  [the feature plan](next_actions.md#requested-feature-changes-2026-10-20-planning-only).
- Generate `pluto.ini` separately for each run.
- Control effective resolution by `cells_per_rbhl`, not directly by hand-written `Nx` and `Ny`.
- Compute `r_BHL`, box size, total runtime, and grid size from a small set of physical and numerical controls.
- Keep box-size margins in the run-generation scripts rather than hard-coding them as physical model parameters.
- Keep generated run directories under `runs/` and `runs_3d/`, both ignored by Git.

## Script Organization

- Keep hand-managed workflow scripts under `scripts/`.
- Use `one_case` naming for single-case scripts.
- Store generated sweep case lists as manifest files under generated run directories.
- Separate script responsibilities:
  - `prepare_*` generates case files and directories
  - `run_*` executes prepared cases locally
  - `submit_*` submits prepared cases to Slurm
