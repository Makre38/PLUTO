# Initial Setup Log

Date: 2026-03-12

This is an archived copy of the original setup memo. Current project state is maintained in `docs/current_status.md`, next work in `docs/next_actions.md`, and durable choices in `docs/decisions.md`.

## Goal

Compute dynamical friction on a massive object moving through uniform gas, following the setup motivated by Ostriker (1999).

Planned numerical picture:

- Uniform-density, uniform-velocity gas
- Fixed gravitational potential at a point in the domain
- Run PLUTO hydrodynamics simulation
- Post-process gas density field to compute the gravitational force on the potential center
- Repeat with multiple resolutions to assess how much resolution is needed

## Current repository state at the time

The directory already contained a minimal PLUTO problem setup:

- `definitions.h`
- `init.c`
- `pluto.ini`
- `makefile`

At that point they were still mostly template/default content.

Observed state:

- `definitions.h`
  - `PHYSICS = HD`
  - `DIMENSIONS = 2`
  - `GEOMETRY = CARTESIAN`
  - `BODY_FORCE = POTENTIAL`
  - `EOS = IDEAL`
  - `USER_DEF_PARAMETERS = 2`
- `init.c`
  - uniform default state only
  - no inflow setup
  - no custom boundary handling
  - no analysis routine
  - no gravitational potential yet
- `pluto.ini`
  - default-like grid/output settings
  - all boundaries currently `outflow`
  - parameter values still zero

## Agreed direction

- Start with 2D implementation
- Use a fixed grid first
- Use inflow boundary on the upstream side
- Use outflow boundaries elsewhere
- Output PLUTO data and analyze it in Julia
- Prefer isothermal EOS first, because the target comparison is motivated by the `c_s = const.` setup in Ostriker (1999)

## Rationale

Why 2D first:

- faster iteration
- easier debugging of boundaries, wake structure, and analysis pipeline
- acceptable as an implementation/debug stage

Why fixed grid first:

- easier to interpret convergence behavior
- avoids AMR-specific complications during first setup

Why Julia for analysis:

- keeps PLUTO-side implementation simpler
- easier to recompute force diagnostics without rerunning simulations

Why isothermal first:

- closest to the intended constant-sound-speed comparison target
- cleaner parameterization in terms of Mach number

## Important caveat

2D should be treated as a setup/debug stage, not as the final quantitative comparison to Ostriker (1999). The main physical comparison is fundamentally closer to a 3D problem.

## Output format decision

For the first implementation stage, prefer PLUTO `double` binary output over `HDF5`.

Reasoning:

- lower setup friction
- faster iteration for 2D fixed-grid debugging
- sufficient for the current workflow, where Julia is the only planned post-processing path

`HDF5` should be reconsidered later if any of the following become important:

- 3D production runs
- richer metadata attached to each output
- data sharing with other tools or users
- a longer-lived analysis pipeline with more variables and diagnostics

## Unit system and derived scales

Adopt the code-unit convention:

- `rho0 = 1`
- `cs = 1`
- `G = 1`

Use the perturber mass notation `M_p`, following Ostriker (1999).

For the planning stage, define the BHL radius as:

- `r_BHL = M_p / (1 + Mach^2)`

Important separation of roles:

- `r_BHL` is the physical inner scale used to organize the force analysis
- `r_s` is the numerical softening length used only to regularize the potential near the origin
- the force integral may exclude an inner region using `r_cut`, with the first preferred choice:
  - `r_cut ~ r_BHL`

## Main implementation pieces identified

### PLUTO problem setup

Needed:

- isothermal HD configuration
- uniform background gas:
  - density `rho0`
  - flow velocity `v_inf`
- fixed softened gravitational potential:
  - likely parameterized by `GM` and softening length `r_s`
- boundary conditions:
  - `X1-beg`: inflow
  - `X1-end`, `X2-beg`, `X2-end`: outflow

### Runtime/output setup

Needed:

- output format:
  - use PLUTO `double` binary for the first phase
- output cadence
- which primitive variables to save
- total runtime long enough for wake development

Direction:

- use coarse-in-time outputs, because the final target diagnostic is `F_df` versus `Mach`, not detailed time evolution
- store enough snapshots to recover representative values at selected `log_Lambda`

### Julia analysis

Needed code for:

- reading PLUTO `double` outputs
- using PLUTO-side metadata for variable ordering, grid dimensions, and dump time
- reconstructing cell-centered coordinates and fluid density
- computing gravitational force from gas on the potential center
- extracting `F_x`, `F_y`, and a time series of force
- comparing results across resolutions
- computing `log_Lambda = ln(cs t / r_BHL)`
- selecting outputs nearest to desired `log_Lambda` values during post-processing

## Numerical issues flagged

- A point-mass potential cannot be left singular; softening is required.
- The softening scale must be considered together with grid spacing.
- The box must be large enough that the wake is not immediately dominated by boundaries.
- Force estimates near the potential center may need an exclusion radius such as:
  - `r < r_s`
  - `r < 2 dx`
- Resolution studies should likely be interpreted using both:
  - domain-scale resolution
  - effective resolution of the softened core, e.g. `r_s / dx`

## Suggested first-round parameter design

- 2D Cartesian box
- flow direction along `+x`
- potential center placed near the middle, possibly slightly upstream of center
- uniform inflow enters from `X1-beg`
- a small set of fixed-grid runs at different resolutions
- force computed in Julia, not inside PLUTO

## Open decisions at the time

- exact EOS support choice in PLUTO
- sign convention and direction of the background flow
- exact form of softened potential
- box size
- initial resolution list
- parameter list to expose in `definitions.h` and `pluto.ini`
- whether the force integral should exclude inner cells by default

## Run-generation strategy

Prefer generating `pluto.ini` separately for each run using a shell script.

Why:

- box size depends on `Mach`, `M_p`, and runtime
- effective resolution should track `r_BHL`
- calculations will be launched on a remote machine, where a shell-based workflow is convenient

Recommended run-script inputs:

Physical controls:

- `Mach`
- `M_p`
- `log_lambda_max`

Numerical controls:

- `cells_per_rbhl`
- `n_output`
- `margin_up`
- `margin_down`

