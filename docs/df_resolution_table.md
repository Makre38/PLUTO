# Normalized DF versus resolution (3D)

## Scope and command

```bash
julia collect_df_resolution_3d.jl RUNS_DIR LOG_LAMBDA [--output PATH] [--force|-f]
```

This collector writes **one `.dat` table only**. It does not draw plots, prepare
cases, build PLUTO, execute simulations or submit jobs. It uses Julia standard
library `Printf` and the existing one-case readers and force integral from
`force_from_run.jl`. No Julia plotting package, gnuplot, Python, Git checkout or
external command is required at runtime. Verification was performed with Julia
1.12.6; other Julia versions have not been tested.

Use a separate TOML for each target resolution, with `softening.a_soft` as its
sweep parameter. Send all cases to one directory. For TOMLs in `configs/local/`:

```toml
[output]
runs_dir = "../../runs_3d"
```

This is a partial TOML fragment, not a complete sweep input: the other common
settings must still be explicit. TOML output paths are relative to the TOML
directory. Case generation, simulation execution and this analysis are separate
steps; their existing interfaces are preserved.

```bash
julia collect_df_resolution_3d.jl ./runs_3d 2.0
julia collect_df_resolution_3d.jl ./runs_3d 2.0 --output comparison.dat
julia collect_df_resolution_3d.jl ./runs_3d 2.0 --output comparison.dat --force
```

`RUNS_DIR` and explicit `--output` paths are relative to the current working
directory. The default file is `RUNS_DIR/df_resolution_loglambda_2.0.dat` for
target `2.0` (the parsed numeric target is used in the name). The parent of an
explicit output must already exist. Outputs must have a `.dat` extension.

## Input selection and validation

- Inspect immediate child directories only. A child with `run_summary.txt` or
  `pluto.ini` is a case; unrelated directories such as `manifests/` are ignored.
  No recursive discovery, manifest input or fixed Mach selection is performed.
- Cases require a valid `run_summary.txt` declaring `dimension=3`, `mach`,
  `a_soft`, `cells_per_rbhl_target`, `cells_per_rbhl_x`, `rbhl`, `mp`, `cs0`,
  `rho0`, and `x1p/x2p/x3p`. This is the current generator's format; incomplete
  older cases must be handled separately. No values are inferred from directory
  names. If `dx_actual` is present, its consistency with `rbhl` and
  `cells_per_rbhl_x` is checked.
- Mach must match across all discovered cases, including cases not yet evolved.
  Its value need not be 1.3. Other physical parameters are recorded when
  available rather than required to match; choose a comparable case set.
- Group rows by `cells_per_rbhl_target`, but use **actual** `cells_per_rbhl_x`
  for the numerical first column. The actual x resolution must match across
  all A_soft members of a row. Duplicate target-resolution/A_soft combinations
  are errors, even if one case is not yet evolved. Distinct targets that produce
  the same actual resolution are also rejected. No implicit averaging, arbitrary
  case selection or resolution interpolation is performed.
- Numeric metadata matching uses relative tolerance `1e-10` and zero absolute
  tolerance. The selected grid's x cell widths must agree with the recorded
  actual spacing to relative tolerance `1e-8`, allowing grid-file roundoff.
- A selected snapshot must be 3D Cartesian, single-file double output. Both
  little- and big-endian data and arbitrary variable ordering are supported.
  The full-variable file size, presence of rho, finite/nonnegative density,
  finite grid coordinates and positive cell widths are checked. Malformed
  metadata, duplicate snapshot indices, missing selected data and unsupported
  formats are errors rather than silently skipped cases.

As with the existing one-case script, grids are interpreted as Cartesian;
the caller must use Cartesian cases. The collector is not a converter for other
coordinate systems or nonuniform x grids.

## Force and time conventions

- `A_soft = R_B/r_soft`, with Bondi radius `R_B`. It is **not**
  `R_BHL/r_soft`.
- Integrate `rho-rho0` using the existing point-mass kernel and `r_cut=R_BHL`.
  Exclude cells with `r < R_BHL` and the exact center; include cells exactly on
  the cutoff. This is the existing one-case/sweep convention, not the radial
  diagnostic's strict `r > r_cut` convention.
- For the configured `+x` inflow, `Fdf=Fx`. Each case's column value is
  `Fx / (4*pi*rho0*(G*mp)^2/cs0^2)`, with code-unit `G=1`, as in the existing
  sweep plot. There is no new Plummer-kernel or inner-cutoff option.
- Supply one finite target `log Lambda = ln(t*cs0/R_BHL)` per invocation.
  A case must have reached this target in its saved positive-time outputs.
  An absolute log-time tolerance of `1e-6` allows the usual six-decimal
  scientific time formatting in `dbl.out` at the final snapshot.
- For reached cases, select the saved positive-time output nearest in
  log Lambda, with no interpolation or time averaging. Equally near outputs
  use the first entry in `dbl.out`. Actual time and log Lambda are recorded.
- Unstarted cases (no grid or snapshot metadata), initial-only cases and cases
  whose latest saved output is too early yield no DF. An empty output directory
  is allowed. Having only one of `grid.out`/`dbl.out` is an input error. Missing
  or corrupt selected output from a reached case is also an input error.

## Table format

```text
# R_BHL_over_dx DF_A0.5 DF_A1.0 DF_A1.5 DF_A2.0
```

Numeric rows follow this header, ordered by actual resolution; columns are
ordered numerically by A_soft values discovered in the input. Values are
space-separated, with enough precision to preserve Float64 values. Header and
provenance lines start with `#` and can be ignored by gnuplot or other readers.

An absent resolution/A_soft combination or an unreached case is written as
`NaN`, never as zero. Rows missing every DF are removed. Discovered A_soft columns
are retained even if all their cases are unreached. If no case is usable, exit
nonzero without creating or replacing a table.

Comments record Mach, target log Lambda, normalization, cutoff, A_soft
definition, and one provenance entry per case. Entries include target/actual
resolution, A_soft, reached status or selected snapshot/time/actual log Lambda,
raw Fx, normalization, rho0, cs0, mp, gamma when available, and the absolute run
path. Paths use Julia string quoting, keeping spaces and special characters
inside comment lines. No second metadata file is generated.

## Existing files and failures

Existing destinations cause an error **before expensive data reads**.
`--force` and `-f` are equivalent and permit replacing the output `.dat`.
Symbolic-link destinations and nonregular files are rejected, including with
`--force`. File creation without force is exclusive, also refusing a destination
that appears while analysis is in progress.

All collection/validation and in-memory table rendering finish before opening
the destination for writing. Therefore a collection error creates no table and
preserves an existing destination even with force. There is no temporary-file
staging, backup or automatic output-directory creation. An I/O failure during
the final write may leave a partial new table or, with force, a truncated
replacement. The CLI prints the error and exits nonzero.

## Verification

```bash
julia --startup-file=no scripts/verify_df_resolution.jl
julia --startup-file=no scripts/verify_df_resolution.jl --report /tmp/df-check.md
```

New verification lives under `scripts/` to respect the repository's ignore
rule for new files under `tests/`. It uses Julia standard libraries `Test`,
`Printf`, and `Dates`, and creates temporary synthetic fixtures with Julia's
standard temporary-directory handling. They are removed after each scenario;
the production collector itself uses no temporary storage. Git is used only
as an optional source of revision information in the verification report.

The default readable report is [test_reports/df_resolution.md](test_reports/df_resolution.md).
It records scenarios, failures, execution command, Julia version and revision.
The suite continues reporting individual scenario failures but exits nonzero if
any scenario failed. It compares an analytic excess-cell force, the existing
one-case CLI, table layout/time selection, rejection paths and both overwrite
flags; it also runs the existing radial and alpha Julia regression suites.
No simulation, physical convergence, production result or remote behavior is
established by these synthetic checks.
