# Julia TOML: runtime and numerical verification

- Executed: 2026-11-05T15:29:57.077
- Julia: 1.12.6
- Revision at execution: ef57aa7f5272d637bfa950dfe59d70e38f1a2128
- Implementation was uncommitted at execution.

| Result | Check |
| --- | --- |
| PASS | Julia shell entry generates a 17×6×6 (612-cell) case: Mach=0.5, A_SOFT=1, CFL=0.2, log Lambda max=0.1. |
| PASS | Serial compilation using make -j2 ARCH=Linux.gcc.defs PLUTO_DIR=/home/nkoba/PLUTO. |
| PASS | ./pluto -maxsteps 10 exits successfully and writes 11 snapshots. |
| PASS | Sound-speed alerts: steps 0,2,4,6,8,10. Threshold=2, repeat interval=2. |
| PASS | Mach alerts: steps 0,3,6,9. Threshold=0.1, repeat interval=3. |

PASS: all 11 full-variable snapshots and dbl.out match the previous Python-generated case byte for byte. The Python implementation was not executed.

Artifacts: `/tmp/pluto-toml-julia-smoke-M2Xn8l` (build.log, run.log, smoke.toml, case-path and generated case). Temporary files may not persist.

This is a small serial behavior/I/O check. MPI, Slurm, production evolution, physical convergence and softening sensitivity are not verified.

## Existing numerical Julia suites

The following commands were executed after the rewrite; both exited successfully.

```bash
julia --startup-file=no tests/test_force_radial_profile_3d.jl
julia --startup-file=no tests/test_alpha_profile_3d.jl
```

| Result | Scope | Assertions |
| --- | --- | --- |
| PASS | Radial kernels and shell sums: uniform/asymmetric density, force signs, point/softened kernels and cumulative/shell consistency | 57 / 57 |
| PASS | PLUTO input and radial tables: endian/field ordering, CLI/table output and existing force cross-check | 12 / 12 |
| PASS | Alpha geometry/time selection: interpolation weights, valid log-time snapshot selection, CLI validation | 18 / 18 |
| PASS | Partial density reads and signed interpolation: selected read offsets, both endian orders, profiles/tables and malformed input | 33 / 33 |

Shell syntax (`bash -n scripts/prepare_from_toml.sh`) and `git diff --check`
also passed. No Python tests or Python implementation were run in this rewrite.
The pre-existing Python softening-generation suite remains unchanged and was
not rerun; TOML and legacy-input equivalence is checked by the new Julia suite.
