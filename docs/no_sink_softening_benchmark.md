# No-Sink Variable-Softening Benchmark: Implementation And Handoff

Last updated: 2026-10-05

## Status

| Stage | Status |
| --- | --- |
| Implementation | Committed as `5e1472a` on `dev/no-sink-variable-softening` |
| Local regression checks | Passed: 9 generator tests and 69 radial-force assertions |
| Local PLUTO check | Serial compilation and a three-step, 612-cell smoke run passed |
| Remote environment / compilation / execution | Partial: user reports a CFL-only comparison; environment/build details and completion are not verified |
| Remote MPI / Slurm | Serial/MPI equivalence and launcher verification are not established for this benchmark |
| Long-time stability, outer-wake/DF convergence, analytical comparison | **Not established** |

Earlier remote MPI/Slurm checks recorded elsewhere in this repository predate
this implementation. They do not validate this benchmark. The later user-run
CFL comparison is recorded below; it does not complete the remote verification
checklist. No remote jobs were submitted by the assistant.

This document replaces the implementation request `additional_task.md`.
Its original text is preserved in commit `5e1472a`. Durable choices also appear
in [decisions.md](decisions.md), and the detailed implementation record is in
[work_history.md](work_history.md).

## Purpose And Constraints

The user observed an artificial-looking downstream hole with the smooth sink.
The immediate experiment is therefore a non-accreting softened perturber in
uniform gas, with the sink disabled. Increase gravitational softening and test
whether the central flow stabilizes while the outer wake and drag converge.
This supports the uniform-flow validation stage of the eventual transverse
velocity-gradient study; that final flow model has not been implemented here.

The existing Plummer potential is unchanged:

```text
Phi = -MP / sqrt(r^2 + r_soft^2)          (G = 1)
r_B = MP / CS0^2
r_BHL = MP / [CS0^2 * (1 + Mach^2)]      (V = Mach * CS0)
A_SOFT = r_B / r_soft
r_soft = r_B / A_SOFT
```

`r_B` and `r_BHL` are distinct scales. `r_soft` regularizes gravity, `r_cut`
selects the force-integration region, and `r_sink` controls fluid modification.
None is an alias for another. The softening radius is not a BH horizon or an
accretion radius. The sink implementation remains available for other
experiments, but the dedicated benchmark always forces `SINK_RADIUS=0`.

No Bernal & Sánchez-Salcedo calibration, fixed `r_cut/r_soft`, or literature
threshold for `A_SOFT` has been adopted. The user will check the papers
separately. Compilation or a short run is not evidence of physical convergence.

## Implemented Changes

| Files | Result |
| --- | --- |
| `scripts/prepare_one_case_3d.sh` | Added `A_SOFT`, corrected arbitrary-CS0 BHL scale, derived-scale metadata, numerical warnings, and distinct A_SOFT case names with overwrite refusal |
| `scripts/prepare_mach_sweep_3d.sh` | Forwards the selected softening interface without injecting a conflicting legacy default |
| `scripts/prepare_softening_sweep_3d.sh` | Reuses the one-case generator for matched cases varying only A_SOFT; forces no sink and writes a manifest |
| `force_radial_profile_3d.jl` | Bins cells once and accumulates outside-in force profiles and shell contributions for two kernels |
| `tests/test_softening_generation.py` | Generator compatibility, scales, invalid/conflicting inputs, warnings, limits and sweep checks |
| `tests/test_force_radial_profile_3d.jl` | Numerical force, cutoff, shell, input-format and CLI checks |
| `README.md`, current status, decisions, next actions, work history | Usage, physical distinctions, verification and remaining work |

`A_SOFT` is a positive generator-level input; PLUTO still receives only `RSOFT`.
Smaller `A_SOFT` means larger softening. Without `A_SOFT`, the old relation
`r_soft = RSOFT_FRAC * r_BHL` remains, with `RSOFT_FRAC=0.25` by default.
Explicitly supplying both inputs fails. Default `CS0=1` generation is preserved.

`run_summary.txt` records `r_bondi`, `rbhl`, `a_soft`, `rsoft`,
`rsoft_over_rbondi`, `rsoft_over_rbhl`, actual cells per each scale along all
three axes, and all six boundary distances divided by `r_soft`. Existing
resolution metadata remains. Warnings use `MIN_CELLS_PER_RSOFT=2` and
`MIN_BOUNDARY_OVER_RSOFT=4` by default. These are configurable numerical
heuristics, not physical criteria; they do not resize the box/grid or override
`WARN_CELLS` / `HARD_CELLS`.

The dedicated wrapper accepts whitespace-separated `A_SOFT_VALUES`, defaulting
to the exploratory list `10 3 1 0.3 0.1`. It holds Mach, gamma, grid, box,
runtime and output times fixed across cases. A_SOFT cases refuse existing case
directories; use a fresh `RUNS_DIR` for a different experiment.

The radial diagnostic computes `F(r > r_cut)` from `rho-rho0` using both:

- Point kernel: `r_vec/r^3`.
- Softened kernel: `r_vec/(r^2+r_soft^2)^(3/2)`.

It outputs cutoff ratios to `r_B`, `r_BHL` and `r_soft`, separately labeled
`Fx/Fy/Fz` for each kernel, and shell contributions. Positive `Fx` is positive
DF for the configured +x flow. Existing one-case and sweep-analysis force
definitions remain unchanged. CLI options and examples are in
[README: radial force diagnostic](../README.md#radial-force-diagnostic).

## Completed Local Verification

These results are from the implementation session, not remote execution:

```bash
bash -n scripts/prepare_one_case_3d.sh scripts/prepare_mach_sweep_3d.sh scripts/prepare_softening_sweep_3d.sh
python3 tests/test_softening_generation.py -v
julia --startup-file=no tests/test_force_radial_profile_3d.jl
git diff --check
```

All passed. Coverage includes legacy `CS0=1`, `A_SOFT=1` giving `r_soft=r_B`,
another A_SOFT value and non-unit CS0, all derived quantities, conflict errors,
forced no-sink sweeps, numerical warning/cell limits and overwrite refusal.
A separate comparison with the pre-change generator produced byte-for-byte
identical default `pluto.ini` files.

Radial tests include uniform-density zero force, signed asymmetric density,
direct integration of both kernels, cutoff equality, shell/cumulative sums,
little/big endian data with multiple fields, and agreement with the existing
one-case point-force calculation.

A generated case with `A_SOFT=1 MACH=0.5 LOG_LAMBDA_MAX=0.1
CELLS_PER_RBHL=2 SINK_RADIUS=0` was compiled using
`make -j2 ARCH=Linux.gcc.defs` and run with `./pluto -maxsteps 3`.
The grid was 17x6x6 (612 cells). The radial tool read initial and positive-time
PLUTO output; forces were zero initially and finite after evolution. The
sink log showed radius zero and zero sink cells. The temporary output interval
was shortened to `1.e-4` to obtain a positive-time dump within three steps.
This intentionally small box emitted heuristic warnings and was only a smoke
test. Temporary artifact locations are recorded in the work history and may
not persist.

## 2026-10-05: User-Reported CFL Comparison

The user reports changing only CFL: the `CFL=0.2` run was running, whereas
the `CFL=0.4` run stopped. The reached time and normal completion of the
`0.2` run have not been confirmed. Other factors have not been tested in
this comparison; this is evidence of CFL sensitivity, not proof that CFL
is the only cause or that the solution is physically converged.

The original failing case is documented locally in
`runs_detail/run_summary.txt`, `runs_detail/prepare_one_case_3d.sh`, and
`runs_detail/exportlog`. These local run artifacts may not be available in
other checkouts. Its recorded settings are:

- `Mach=0.1`, `GAMMA=1.6666`, `MP=CS0=RHO0=1`, `LOG_LAMBDA_MAX=4`.
- `SINK_RADIUS=0`; legacy softening with `r_soft=0.25*r_BHL`
  `=0.2475247525*r_B`, equivalent to `A_SOFT=4.04`.
  The earlier description of a radius near `2*r_B` was incorrect.
- `CELLS_PER_RBHL=8`, about two cells per softening radius in each direction;
  grid `1097 x 1136 x 1136`.
- The preparation script sets `CFL=0.4`; repository definitions use 3D
  `LINEAR + RK2`, with the generated solver set to `tvdlf`.

The original log shows Mach increasing from `1.601036` at step 242 to
`1.2137e19` at step 243 and `inf` at step 244 (`t=5.5816`). The explicit
abort is `NextTimeStep(): dt is too small (7.267096e-27)`, rather than a
Mach threshold. The new comparison's outcome is user-reported; separate
logs for both comparison runs have not been independently inspected.

For 3D unsplit RK2, the documented stability limit is approximately
`CFL <= 1/3`; `0.4` exceeds that limit and `0.2` is below it
([PLUTO user guide](https://plutocode.ph.unito.it/files/userguide.pdf)).
This makes timestep instability a leading candidate. Initial loss of
density/pressure positivity and subsequent energy cancellation have not
been distinguished. Resolution, softening, gravity-source discretization,
and other numerical factors remain untested in this comparison.

Next, preserve both runs' settings/logs and record the `0.2` run's reached
time and exit status. Then test other factors separately at fixed CFL,
including resolution and softening, and compare wake/force convergence.
This documentation update does not change the generator's `CFL=0.4` default.

## Remote Verification To Perform

The systematic checks below remain unverified. These are resumption
instructions, distinct from the user-reported CFL comparison above.

1. Check the remote checkout/commit, `PLUTO_DIR`, compiler, Julia, MPI and
   Slurm environment. Run the lightweight shell and regression checks above.
2. Generate a fresh small no-sink case. Inspect `pluto.ini`, `run_summary.txt`,
   softening/resolution/boundary ratios and the cell count before execution.
   Confirm `SINK_RADIUS=0` explicitly.
3. On an appropriate allocated compute node, compile and run a short serial
   case, then a short MPI case with the same physical/grid settings. The
   existing MPI architecture is `Linux.mpicc.defs`; select the launcher required
   by the cluster. Earlier jobs on the known Slurm environment required `srun`.
   When using the submission wrapper, set `MPI_LAUNCHER=srun` explicitly there.
4. Inspect `logs/run_stage_3d.log` when using the runner, Slurm stdout/stderr,
   PLUTO output, and rank-specific diagnostic/sink logs. Confirm clean exits,
   zero sink cells, usable snapshots and finite state/force values. Compare
   serial and MPI results at matching times with a recorded numerical tolerance.
5. Run the radial tool on remote output. Compare its point-kernel result at
   `r_cut=r_BHL` with existing one-case analysis, accounting for exact-cutoff
   inclusion differences. Inspect the softened result separately.
6. Record the commit, machine, compiler/MPI/Julia versions, job IDs, commands,
   case paths, parameters and outcomes in `work_history.md`. Only then update
   the remote verification status.

After remote smoke tests pass, a first matched exploratory pair can use
`A_SOFT_VALUES="2 1" MACH=0.5 GAMMA=1.6666 LOG_LAMBDA_MAX=1.5
CELLS_PER_RBHL=4 N_OUTPUT=10`. See
[README: case preparation](../README.md#no-sink-variable-softening-benchmark).
Inspect generated geometry before running; do not automatically launch an
expensive 3D sweep without explicit instruction.

Production work must compare density, pressure, local Mach, timestep history,
outer wake and both force profiles at matched times. Vary resolution, box
size, softening and analysis cutoff before claiming convergence or analytical
agreement. Set gamma explicitly: the old one-case and Mach-sweep defaults
differ. Older non-unit-CS0 3D cases and the unchanged 2D generator use the old
BHL formula, so they must not be silently mixed with the corrected benchmark.
