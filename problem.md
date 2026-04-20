# Current Problems

Date: 2026-04-16

## Topic

Open questions around the force calculation used in `sweep_force_plot.jl` and its comparison to the Ostriker (1999) drag formula.

## Current understanding

- The present PLUTO runs are 2D Cartesian simulations.
- In `sweep_force_plot.jl`, the force calculation is intended to interpret the 2D density field as if it were revolved around the x-axis to construct an axisymmetric 3D mass distribution.
- The current investigation was triggered because the resulting sweep plot does not match the expected trend from the Ostriker formula.

## Confirmed points

- The force kernel used for `Fx` does not currently show an obvious typo.
- The current code integrates with a volume-weight factor proportional to `pi * abs(y) * dx * dy`.
- For `Fx` only, this factor is not obviously inconsistent if both positive- and negative-y cells are included and the field is interpreted as an axisymmetric 3D reconstruction.
- The `Fy` expression is not currently trusted as a proper axisymmetric 3D result, but this is not an immediate problem because the present analysis only uses `Fx`.

## Important implementation facts

- In `sweep_force_plot.jl`, the drag-like quantity is currently taken from `fx`.
- In `force_from_run.jl`, the force calculation still uses the older pure-2D area element `dx * dy`.
- This difference between the two Julia scripts is currently understood to be an inconsistency left over from an incomplete update.
- The inner cutoff radius `rcut` is not an independently configured parameter at present.
- Instead, both Julia scripts effectively use:
  - `rcut = rbhl`
- The value of `rbhl` is generated during case preparation and stored in `run_summary.txt`.

## Open problems

### 1. Sign convention for drag

- `sweep_force_plot.jl` currently stores the plotted drag-like quantity using `fx` directly.
- It is still necessary to check carefully whether the intended drag comparison should instead use `-fx`.
- A sign mismatch against the theoretical curve may be contributing to the disagreement.

### 2. Meaning of the 2D-to-3D reconstruction

- The present simulations are 2D Cartesian, not axisymmetric cylindrical runs.
- The post-processing step assumes that the 2D density field can be revolved around the x-axis to estimate a 3D gravitational force.
- Even if the algebra for `Fx` is internally consistent, this interpretation may not be physically equivalent to the 3D setup assumed in Ostriker (1999).
- This model mismatch may be a major reason the comparison does not agree.

### 3. Inner cutoff choice

- The current choice `rcut = rbhl` is hard-coded in practice.
- It is not yet clear whether this is the right exclusion radius for comparison to the theoretical `log Lambda`.
- The drag estimate may be sensitive to this cutoff.

### 4. Cross-script inconsistency

- `sweep_force_plot.jl` and `force_from_run.jl` are not currently computing the same quantity.
- This should be cleaned up before relying on cross-checks between the two scripts.

## Suggested next checks

- Check the drag sign convention explicitly and confirm whether the plotted quantity should be `fx` or `-fx`.
- Make `rcut` an explicit analysis parameter instead of implicitly tying it to `rbhl`.
- Compare results for several `rcut` choices to measure sensitivity.
- Decide whether the current sweep plot should be interpreted only as a qualitative diagnostic rather than a direct quantitative comparison to Ostriker (1999).
- Unify `force_from_run.jl` and `sweep_force_plot.jl` so they use the same force definition.

追記:この問題が2次元で流体計算をしている事による物である可能性を考え、3次元の流体計算を行って結果を見たい。
