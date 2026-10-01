# Task: no-sink / variable-softening benchmark for the 3D PLUTO calculation

## Purpose

The immediate goal is to test whether the uniform-flow PLUTO calculation can be
stabilized without using the central sink, by increasing the gravitational
softening length.

The physical target of this stage is NOT BH accretion. We want a clean
non-accreting, softened gravitational perturber and want to determine whether
the outer wake and dynamical-friction force converge while the nonlinear central
flow is regularized.

Do not interpret the softening radius as a BH horizon or accretion radius.

The existing smooth sink has produced an artificial-looking hole in the
downstream wake. For this benchmark, the sink should therefore remain disabled.

Do not implement any literature-specific calibration such as
r_min = const * r_soft in this task. I will check the relevant papers separately.

---

## Current implementation

Inspect the repository before modifying it.

Relevant files include at least:

- `init_3d.c`
- `definitions_3d.h`
- `scripts/prepare_one_case_3d.sh`
- `scripts/prepare_mach_sweep_3d.sh`
- `force_from_run.jl`
- `sweep_force_plot.jl`
- `plot_3d_diagnostics.jl`
- `docs/decisions.md`
- `docs/current_status.md`
- `docs/work_history.md`

The current gravity implementation in `init_3d.c` already uses a Plummer-type
softened potential,

    Phi = - M_p / sqrt(r^2 + r_soft^2)

in code units with G = 1.

Keep this gravitational force law unchanged unless you find an actual bug.

At present, `scripts/prepare_one_case_3d.sh` effectively sets

    r_soft = RSOFT_FRAC * r_BHL

with default `RSOFT_FRAC=0.25`.

This couples the softening strength to Mach number and prevents us from
independently controlling how nonlinear the central gravitational response is.

---

# 1. Add an independent softening-strength parameter

Introduce a generator-level parameter named

    A_SOFT

defined by

    A_SOFT = r_B / r_soft

where

    r_B = G M_p / c_s0^2

and G=1 in the current code units.

Thus,

    r_soft = r_B / A_SOFT.

Important:

- `A_SOFT` is a case-generation parameter.
- PLUTO itself should continue receiving only the existing `RSOFT` parameter.
- Do not add another PLUTO user-defined parameter unless actually necessary.
- `A_SOFT` controls the strength/nonlinearity of the central perturber.
- Smaller A_SOFT means larger softening and a weaker central potential.

Also clearly distinguish:

    r_B    = M_p / c_s0^2

from

    r_BHL  = M_p / (c_s0^2 + V^2)
           = M_p / [c_s0^2 (1 + Mach^2)]

with V = Mach * c_s0.

The current script uses the simplified expression

    r_BHL = M_p / (1 + Mach^2)

which assumes c_s0=1.

While touching this code, make the expression correct for arbitrary `CS0`.
Verify explicitly that the result is unchanged for the present default CS0=1.

---

# 2. Preserve backward compatibility

Do not unnecessarily break old run-generation commands.

Preferred behavior:

- If `A_SOFT` is explicitly supplied, compute `RSOFT` from `r_B/A_SOFT`.
- Otherwise preserve the current `RSOFT_FRAC * r_BHL` behavior.

Do not silently combine the two definitions.

If both `A_SOFT` and an explicitly supplied `RSOFT_FRAC` are given, fail with
a clear error or otherwise make the precedence completely explicit.

For new no-sink softening studies, `A_SOFT` should be the preferred interface.

Do not change the existing default behavior of unrelated production/sweep
scripts unless required.

---

# 3. Record all relevant derived scales

When generating a case using `A_SOFT`, write the following into
`run_summary.txt`:

    r_bondi
    rbhl
    a_soft
    rsoft
    rsoft_over_rbondi
    rsoft_over_rbhl

Also record the actual numerical resolution of the softened region, e.g.

    cells_per_rsoft_x
    cells_per_rsoft_y
    cells_per_rsoft_z

computed using the actual generated grid spacings, not only the requested
target spacing.

Keep the existing resolution information as well.

The case name should contain enough information to distinguish different
A_SOFT runs, for example an `asoft...` component.

---

# 4. Add safety diagnostics for inappropriate boxes/resolution

Larger softening lengths may become comparable to the computational box.

Do not silently generate a scientifically meaningless case.

After determining the grid, calculate and record:

- r_soft / dx
- distance from the perturber to each domain boundary divided by r_soft
- r_B / dx
- r_BHL / dx

Emit a clear warning if the softened object is only poorly resolved or if
r_soft is not comfortably contained inside the domain.

This warning threshold is only a numerical safety heuristic, not a physical
criterion. Document that fact.

Do not automatically create a catastrophically large grid solely to satisfy
this heuristic. Respect the existing `WARN_CELLS` and `HARD_CELLS`
mechanisms.

---

# 5. Add a dedicated no-sink softening sweep

Create a small wrapper script, for example

    scripts/prepare_softening_sweep_3d.sh

for matched uniform-flow cases with different `A_SOFT`.

Its purpose is specifically the no-sink benchmark.

Requirements:

- force `SINK_RADIUS=0`
- vary only A_SOFT unless the caller explicitly changes another common
  parameter
- reuse `prepare_one_case_3d.sh` rather than duplicating case-generation logic
- allow a whitespace-separated list through something like

      A_SOFT_VALUES="10 3 1 0.3 0.1"

- provide a reasonable exploratory default list, but make it obvious that the
  values are not a physically calibrated final choice
- keep Mach, gamma, resolution, time, etc. identical across the generated
  cases

Do not remove the existing sink implementation. We may need it later for a
different physical problem.

For this benchmark, however, sink use must be unambiguous: `SINK_RADIUS=0`.

---

# 6. Add a radial force-contribution diagnostic

We need to know whether changing the central softening modifies only the inner
flow or also the outer wake.

Do not change the semantics of the existing `force_from_run.jl`.

Add a separate diagnostic script, for example

    force_radial_profile_3d.jl

that computes the gravitational-force contribution as a function of excluded
inner radius.

For a snapshot, calculate

    F(>r_cut) =
        M_p ∫_{r > r_cut} (rho-rho0) r_vec/r^3 dV

using the existing sign convention.

Output at least:

    r_cut
    r_cut / r_B
    r_cut / r_BHL
    r_cut / r_soft
    Fx
    Fy
    Fz

Also provide shell contributions if practical:

    dFx_shell
    dFy_shell
    dFz_shell

so that we can identify where the force originates.

Implement this efficiently by binning cells in radius and forming cumulative
sums from outside inward; do not recompute the entire 3D volume separately for
every r_cut.

Use the same background subtraction

    delta_rho = rho - rho0

as the existing force code.

---

# 7. Also calculate the force with the softened kernel

The gas dynamics is evolved using the softened gravitational potential, while
the current post-processing force uses the point-mass kernel outside an inner
cutoff.

For diagnostic purposes, calculate BOTH definitions in the new radial-profile
tool:

Point-mass kernel:

    r_vec / r^3

Softened kernel consistent with the PLUTO potential:

    r_vec / (r^2 + r_soft^2)^(3/2)

Clearly label the two results.

For example:

    Fx_point
    Fy_point
    Fz_point

    Fx_soft
    Fy_soft
    Fz_soft

Do not silently replace the force convention used by the existing analysis.
The purpose is to compare the two definitions.

---

# 8. Preserve physical distinctions in the code/comments

Please keep the following concepts separate in variable names and comments:

- Bondi radius `r_B`
- BHL radius `r_BHL`
- gravitational softening radius `r_soft`
- force-analysis cutoff `r_cut`
- sink radius `r_sink`

In particular:

    r_soft != r_sink
    r_soft != r_cut
    r_B   != r_BHL

Do not use one merely as an alias for another.

The softening radius regularizes the gravitational potential.

The force cutoff is an analysis choice.

The sink, when enabled in other experiments, modifies the fluid variables.

These have different physical meanings.

---

# 9. Do not yet add a Bernal & Sánchez-Salcedo calibration

The motivation for this change comes partly from previous calculations of
extended non-accreting perturbers, but I have not yet finished checking the
paper.

Therefore DO NOT hard-code or assume any literature value such as

    r_min = 2.25 r_soft

or a particular threshold value of A_SOFT.

For now the numerical question is simply:

    As r_soft is increased, does the no-sink calculation become stable,
    and do the density wake and outer gravitational force converge?

Literature calibration will be a separate step.

---

# 10. Verification

After implementation, perform lightweight verification.

At minimum:

1. `bash -n` all modified/new shell scripts.
2. `git diff --check`.
3. Generate a legacy case with no A_SOFT and confirm that the default
   CS0=1 case still gives the same r_BHL and r_soft as before.
4. Generate a case with

       A_SOFT=1

   and verify numerically that

       r_soft = r_B.

5. Generate another A_SOFT value and verify all derived quantities in
   `run_summary.txt`.
6. Verify `SINK_RADIUS=0` in all cases generated by the dedicated
   softening sweep.
7. Check that conflicting softening specifications do not silently give an
   ambiguous result.
8. Compile a small generated 3D case if PLUTO is available.
9. If reasonably cheap, run one or a few steps as a smoke test.
10. Test the radial-force diagnostic on either a small output or synthetic
    data. For uniform rho=rho0 it should give zero force to numerical
    precision.

Do not claim that the physics is validated merely because the program
compiles or runs.

---

# 11. Documentation

Update the relevant repository documentation.

At least record:

- why A_SOFT was introduced
- its definition
- distinction between r_B, r_BHL, r_soft, r_cut, and r_sink
- that the new benchmark is explicitly non-accreting and no-sink
- that the goal is to study sensitivity of the outer wake and drag to the
  inner regularization
- what was implemented versus what has actually been run/validated

Update `docs/work_history.md` with implementation and verification results.

Do not mark the Ostriker comparison or physical convergence as completed
unless actual numerical runs demonstrate it.

---

# Deliverable

After making the changes, report:

1. files changed/added
2. exact new user-facing parameters and their definitions
3. formulas used for r_B, r_BHL, and r_soft
4. backward-compatibility behavior
5. verification commands run and their results
6. anything you found in the existing implementation that could invalidate
   the intended comparison
7. suggested first small set of runs, but do not launch expensive 3D sweeps
   without explicit instruction
