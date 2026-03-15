# PLUTO setup memo for dynamical friction test

Date: 2026-03-12

## Goal

Compute dynamical friction on a massive object moving through uniform gas, following the setup motivated by Ostriker (1999).

Planned numerical picture:

- Uniform-density, uniform-velocity gas
- Fixed gravitational potential at a point in the domain
- Run PLUTO hydrodynamics simulation
- Post-process gas density field to compute the gravitational force on the potential center
- Repeat with multiple resolutions to assess how much resolution is needed

## Current repository state

The directory already contains a minimal PLUTO problem setup:

- `definitions.h`
- `init.c`
- `pluto.ini`
- `makefile`

At this point they are still mostly template/default content.

Observed current state:

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
  - parameter values are still zero

## Agreed direction so far

- Start with 2D implementation
- Use a fixed grid first
- Use inflow boundary on the upstream side
- Use outflow boundaries elsewhere
- Output PLUTO data and analyze it in Julia
- Prefer isothermal EOS first, because the target comparison is motivated by the `c_s = const.` setup in Ostriker (1999)

## Rationale for the current plan

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

For the current planning stage, define the BHL radius as:

- `r_BHL = M_p / (1 + Mach^2)`

This can be revised later if a different convention is preferred.

Important separation of roles:

- `r_BHL` is the physical inner scale used to organize the force analysis
- `r_s` is still the numerical softening length used only to regularize the potential near the origin
- the force integral may exclude an inner region using `r_cut`, with the current preferred choice:
  - `r_cut ~ r_BHL`

## Main implementation pieces identified

### 1. PLUTO problem setup

Need to implement:

- isothermal HD configuration
- uniform background gas:
  - density `rho0`
  - flow velocity `v_inf`
- fixed softened gravitational potential:
  - likely parameterized by `GM` and softening length `r_s`
- boundary conditions:
  - `X1-beg`: inflow
  - `X1-end`, `X2-beg`, `X2-end`: outflow

### 2. Runtime/output setup

Need to choose:

- output format:
  - use PLUTO `double` binary for the first phase
- output cadence
- which primitive variables to save
- total runtime long enough for wake development

Current direction:

- use coarse-in-time outputs, because the final target diagnostic is `F_df` versus `Mach`, not detailed time evolution
- store enough snapshots to recover representative values at selected `log_Lambda`
  - time resolution does not need to be especially fine in the first stage

### 3. Julia analysis

Need code for:

- reading PLUTO `double` outputs
- using the PLUTO-side metadata that describes:
  - variable ordering
  - grid dimensions
  - time for each dump
- reconstructing cell-centered coordinates and fluid density
- computing gravitational force from gas on the potential center
- extracting at least:
  - `F_x`
  - `F_y`
  - time series of force
- comparing results across resolutions
- computing
  - `log_Lambda = ln(cs t / r_BHL)`
- selecting outputs nearest to desired `log_Lambda` values during post-processing

## Numerical issues already flagged

- A point-mass potential cannot be left singular; softening is required
- The softening scale must be considered together with grid spacing
- The box must be large enough that the wake is not immediately dominated by boundaries
- Force estimates near the potential center may need an exclusion radius such as:
  - `r < r_s`
  - or `r < 2 dx`
- Resolution studies should likely be interpreted using both:
  - domain-scale resolution
  - effective resolution of the softened core, e.g. `r_s / dx`

## Suggested first-round parameter design

These were not fixed yet, but this is the intended structure:

- 2D Cartesian box
- flow direction along `+x`
- potential center placed near the middle, possibly slightly upstream of center
- uniform inflow enters from `X1-beg`
- a small set of fixed-grid runs at different resolutions
- force computed in Julia, not inside PLUTO

## Open decisions for next session

These still need to be fixed before coding:

- exact EOS support choice in PLUTO for the first implementation
  - confirm how to configure isothermal in this local PLUTO version
- sign convention / direction of the background flow
- exact form of softened potential
  - e.g. Plummer-like or another smoothing
- box size
- initial resolution list
- parameter list to expose in `definitions.h` / `pluto.ini`
  - likely candidates:
    - `RHO0`
    - `CS0`
    - `VINF`
    - `GM`
    - `RS`
    - potential center coordinates
- whether the force integral should exclude inner cells by default

Decided in this session:

- first output format will be PLUTO `double` binary, not `HDF5`
- use code units `rho0 = 1`, `cs = 1`, `G = 1`
- denote the perturber mass by `M_p`
- use, for now, `r_BHL = M_p / (1 + Mach^2)`
- use `log_Lambda = ln(cs t / r_BHL)` as the main time-like comparison variable
- use `r_cut ~ r_BHL` as the preferred first choice for the force-integration inner cutoff
- resolution should be controlled by `cells_per_rbhl`, not directly by `Nx, Ny`
- `pluto.ini` should be generated separately for each run
- box-size margins should be controlled by the run-generation script, not hard-coded as physical model parameters

Implication:

- the Julia reader should be designed around PLUTO binary dumps plus accompanying metadata, rather than assuming a self-describing container format
- the run workflow should compute `r_BHL`, box size, total runtime, and grid size from a small set of physical and numerical control parameters

## Run-generation strategy

Prefer generating `pluto.ini` separately for each run using a shell script.

Why:

- box size depends on `Mach`, `M_p`, and runtime
- effective resolution should track `r_BHL`
- the calculations will be launched on a remote machine, where a shell-based workflow is convenient

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
- `margin_y`
- `upstream_min`
- `warn_cells`
- `hard_cells`

Derived quantities:

- `r_BHL = M_p / (1 + Mach^2)`
- `t_max = (r_BHL / cs) * exp(log_lambda_max)`
- `dx_target = r_BHL / cells_per_rbhl`
- `dy_target = dx_target`

Suggested box-size construction:

- `L_up_wave = margin_up * t_max * max(cs - v_inf, 0)`
- `L_up = max(upstream_min, 3 * r_BHL, L_up_wave)`
- `L_down = margin_down * t_max * (cs + v_inf)`
- `L_y = margin_y * t_max * cs`

With code units `cs = 1` and `v_inf = Mach`, this becomes:

- `t_max = r_BHL * exp(log_lambda_max)`
- `L_up_wave = margin_up * t_max * max(1 - Mach, 0)`
- `L_down = margin_down * t_max * (1 + Mach)`
- `L_y = margin_y * t_max`

Grid construction should use target cell sizes, not fixed cell counts:

- `Nx = ceil((x_max - x_min) / dx_target)`
- `Ny = ceil((y_max - y_min) / dy_target)`

This ensures that each run is controlled by how well `r_BHL` is resolved, rather than by arbitrary fixed `Nx, Ny`.

Cost control:

- compute `Ncell = Nx * Ny`
- warn if `Ncell > warn_cells`
- stop run generation if `Ncell > hard_cells`

## Output-time strategy

Use `log_Lambda = ln(cs t / r_BHL)` as the comparison variable for analysis.

However, the PLUTO output schedule itself should remain simple:

- output snapshots at uniform intervals in simulation time
- keep the number of snapshots modest in the first stage

Reason:

- the final target is `F_df` versus `Mach`
- detailed time resolution is not a priority in the first round
- desired `log_Lambda` values can be selected later during Julia post-processing

## Recommended next step

At restart, the next useful action is:

1. Finalize the first-run parameter list, including a first guess for `M_p`, `log_lambda_max`, `cells_per_rbhl`, and box-margin defaults
2. Update `definitions.h` and `init.c` for the 2D softened-potential setup
3. Add a shell script that generates per-run `pluto.ini` files from physical and numerical control parameters
4. Add Julia post-processing for:
   - reading PLUTO binary dumps
   - computing `log_Lambda`
   - integrating the force with `r_cut ~ r_BHL`
   - extracting representative `F_df` values for later `F_df`-versus-`Mach` plots

## If continuing from here

The next Codex turn should likely use:

- `implementation-strategy`

with the immediate objective:

- define the concrete PLUTO-side changes
- define the Julia analysis responsibilities
- propose an initial parameter set for a first test run
