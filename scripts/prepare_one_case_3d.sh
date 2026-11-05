#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd "${script_dir}/.." && pwd)"

# Removed sink options must not silently turn an old setup into a new model.
for removed_option in SINK_RADIUS SINK_TIMESCALE SINK_TAPER_POWER SINK_RHO_FLOOR SINK_VELOCITY_FACTOR; do
  if [[ -v "${removed_option}" ]]; then
    echo "${removed_option} is no longer supported: the absorbing sink was removed. Unset all SINK_* options for new cases; preserve old runs separately." >&2
    exit 1
  fi
done

mach="${MACH:-0.1}"
mp="${MP:-1.0}"
log_lambda_max="${LOG_LAMBDA_MAX:-2.0}"
cells_per_rbhl="${CELLS_PER_RBHL:-2.0}"
n_output="${N_OUTPUT:-20}"

gamma="${GAMMA:-1.6666}"
rho0="${RHO0:-1.0}"
cs0="${CS0:-1.0}"
if [[ -v A_SOFT && -v RSOFT_FRAC ]]; then
  echo "Specify either A_SOFT or RSOFT_FRAC, not both." >&2
  exit 1
fi
softening_mode=legacy
a_soft_input="${A_SOFT-}"
[[ -v A_SOFT ]] && softening_mode=asoft
rsoft_frac="${RSOFT_FRAC:-0.25}"
cs_alert_threshold="${CS_ALERT_THRESHOLD:-1.0e-6}"
cs_alert_every_steps="${CS_ALERT_EVERY_STEPS:-1}"
mach_alert_threshold="${MACH_ALERT_THRESHOLD:-10.0}"
mach_alert_every_steps="${MACH_ALERT_EVERY_STEPS:-1}"

margin_up="${MARGIN_UP:-1.2}"
margin_down="${MARGIN_DOWN:-1.3}"
margin_y="${MARGIN_Y:-1.3}"
upstream_min="${UPSTREAM_MIN:-5.0}"

warn_cells="${WARN_CELLS:-2000000}"
hard_cells="${HARD_CELLS:-8000000}"
min_cells_per_rsoft="${MIN_CELLS_PER_RSOFT:-2}"
min_boundary_over_rsoft="${MIN_BOUNDARY_OVER_RSOFT:-4}"

runs_dir="${RUNS_DIR:-${repo_dir}/runs_3d_timetest}"
export_subdir="${EXPORT_SUBDIR:-export}"

derived="$(awk -v mach="${mach}" \
              -v mp="${mp}" \
              -v log_lambda_max="${log_lambda_max}" \
              -v cells_per_rbhl="${cells_per_rbhl}" \
              -v n_output="${n_output}" \
              -v cs0="${cs0}" \
              -v softening_mode="${softening_mode}" \
              -v a_soft_input="${a_soft_input}" \
              -v rsoft_frac="${rsoft_frac}" \
              -v margin_up="${margin_up}" \
              -v margin_down="${margin_down}" \
              -v margin_y="${margin_y}" \
              -v upstream_min="${upstream_min}" \
              -v warn_cells="${warn_cells}" \
              -v hard_cells="${hard_cells}" \
              -v min_cells_per_rsoft="${min_cells_per_rsoft}" \
              -v min_boundary_over_rsoft="${min_boundary_over_rsoft}" '
function ceil(x) { return (x == int(x)) ? x : int(x) + 1 }
function max2(a,b) { return (a > b) ? a : b }
function max3(a,b,c) { return max2(a, max2(b, c)) }
function fail(message) { print "Invalid case: " message > "/dev/stderr"; exit 1 }
function number(name, value, positive) {
  if (value !~ /^[+-]?([0-9]+([.][0-9]*)?|[.][0-9]+)([eE][+-]?[0-9]+)?$/ ||
      value-value != 0 || (positive && value+0 <= 0)) fail(name " must be a finite " (positive ? "positive " : "") "number")
}
function resolution(axis, spacing) {
  printf("cells_per_rsoft_%s=%.17g\n", axis, rsoft/spacing)
  printf("cells_per_rbondi_%s=%.17g\n", axis, r_bondi/spacing)
  printf("cells_per_rbhl_%s=%.17g\n", axis, rbhl/spacing)
  if (rsoft/spacing < min_cells_per_rsoft)
    printf("Warning: r_soft/d%s=%.6g < MIN_CELLS_PER_RSOFT=%g (numerical heuristic).\n", axis, rsoft/spacing, min_cells_per_rsoft) > "/dev/stderr"
}
function boundary(label, distance) {
  printf("boundary_%s_over_rsoft=%.17g\n", label, distance/rsoft)
  if (distance/rsoft < min_boundary_over_rsoft)
    printf("Warning: %s distance/r_soft=%.6g < MIN_BOUNDARY_OVER_RSOFT=%g (numerical heuristic).\n", label, distance/rsoft, min_boundary_over_rsoft) > "/dev/stderr"
}
BEGIN {
  number("MACH", mach, 0)
  if (mach < 0) fail("MACH must be nonnegative for the +x inflow geometry")
  number("MP", mp, 1)
  number("CS0", cs0, 1)
  number("LOG_LAMBDA_MAX", log_lambda_max, 0)
  number("CELLS_PER_RBHL", cells_per_rbhl, 1)
  number("N_OUTPUT", n_output, 1)
  if (n_output != int(n_output)) fail("N_OUTPUT must be an integer")
  number("MARGIN_UP", margin_up, 1)
  number("MARGIN_DOWN", margin_down, 1)
  number("MARGIN_Y", margin_y, 1)
  number("UPSTREAM_MIN", upstream_min, 1)
  number("WARN_CELLS", warn_cells, 1)
  number("HARD_CELLS", hard_cells, 1)
  number("MIN_CELLS_PER_RSOFT", min_cells_per_rsoft, 1)
  number("MIN_BOUNDARY_OVER_RSOFT", min_boundary_over_rsoft, 1)
  if (softening_mode == "asoft") number("A_SOFT", a_soft_input, 1)
  else number("RSOFT_FRAC", rsoft_frac, 1)
  r_bondi = mp/(cs0*cs0)
  rbhl = r_bondi/(1.0 + mach*mach)
  tmax = rbhl/cs0*exp(log_lambda_max)
  vinf = mach*cs0
  rsoft = softening_mode == "asoft" ? r_bondi/a_soft_input : rsoft_frac*rbhl
  number("derived r_B", r_bondi, 1)
  number("derived r_BHL", rbhl, 1)
  number("derived r_soft", rsoft, 1)
  number("derived tmax", tmax, 1)
  dx_target = rbhl/cells_per_rbhl
  l_up_wave = margin_up*tmax*max2(cs0 - vinf, 0.0)
  l_up = max3(upstream_min, 3.0*rbhl, l_up_wave)
  l_down = margin_down*tmax*(cs0 + vinf)
  l_y = margin_y*tmax*cs0
  xmin = -l_up
  xmax = l_down
  ymin = -l_y
  ymax = l_y
  zmin = -l_y
  zmax = l_y
  nx = ceil((xmax - xmin)/dx_target)
  ny = ceil((ymax - ymin)/dx_target)
  nz = ceil((zmax - zmin)/dx_target)
  ncell = nx*ny*nz
  number("derived cell count", ncell, 1)
  if (ncell > hard_cells) fail("Ncell=" ncell " exceeds HARD_CELLS=" hard_cells)
  dx_actual = (xmax - xmin)/nx
  dy_actual = (ymax - ymin)/ny
  dz_actual = (zmax - zmin)/nz
  dt_out = tmax/n_output
  warn = (ncell > warn_cells) ? 1 : 0
  case_name = sprintf("mach%.3f_mp%.3f_ll%.3f_rbhl%.1f_3d", mach, mp, log_lambda_max, cells_per_rbhl)
  if (softening_mode == "asoft") case_name = sprintf("%s_asoft%.17g", case_name, a_soft_input)
  if (cs0 != 1.0) case_name = sprintf("%s_cs%.17g", case_name, cs0)

  printf("r_bondi=%.17g\n", r_bondi)
  printf("rbhl=%.17g\n", rbhl)
  printf("a_soft=%.17g\n", r_bondi/rsoft)
  printf("rsoft_over_rbondi=%.17g\n", rsoft/r_bondi)
  printf("rsoft_over_rbhl=%.17g\n", rsoft/rbhl)
  resolution("x", dx_actual)
  resolution("y", dy_actual)
  resolution("z", dz_actual)
  boundary("xmin", -xmin)
  boundary("xmax", xmax)
  boundary("ymin", -ymin)
  boundary("ymax", ymax)
  boundary("zmin", -zmin)
  boundary("zmax", zmax)
  printf("tmax=%.17g\n", tmax)
  printf("vinf=%.17g\n", vinf)
  printf("rsoft=%.17g\n", rsoft)
  printf("dx_target=%.17g\n", dx_target)
  printf("dx_actual=%.17g\n", dx_actual)
  printf("dy_actual=%.17g\n", dy_actual)
  printf("dz_actual=%.17g\n", dz_actual)
  printf("xmin=%.17g\n", xmin)
  printf("xmax=%.17g\n", xmax)
  printf("ymin=%.17g\n", ymin)
  printf("ymax=%.17g\n", ymax)
  printf("zmin=%.17g\n", zmin)
  printf("zmax=%.17g\n", zmax)
  printf("dt_out=%.17g\n", dt_out)
  printf("nx=%d\n", nx)
  printf("ny=%d\n", ny)
  printf("nz=%d\n", nz)
  printf("ncell=%d\n", ncell)
  printf("warn=%d\n", warn)
  printf("case_name=%s\n", case_name)
}')"
eval "${derived}"

if [[ "${warn}" -eq 1 ]]; then
  echo "Warning: Ncell=${ncell} exceeds WARN_CELLS=${warn_cells}" >&2
fi

mkdir -p "${runs_dir}"
case_dir="${runs_dir}/${case_name}"
if [[ "${softening_mode}" == asoft ]]; then
  # New benchmark cases must not overwrite an earlier run with different settings.
  mkdir "${case_dir}" || {
    echo "Refusing to overwrite A_SOFT case: ${case_dir}. Choose a fresh RUNS_DIR." >&2
    exit 1
  }
else
  mkdir -p "${case_dir}"
fi
mkdir -p "${case_dir}/${export_subdir}"
mkdir -p "${case_dir}/logs"

cp "${repo_dir}/definitions_3d.h" "${case_dir}/definitions.h"
cp "${repo_dir}/init_3d.c" "${case_dir}/init.c"
cp "${repo_dir}/makefile" "${repo_dir}/local_make" "${case_dir}/"

cat > "${case_dir}/pluto.ini" <<EOF
[Grid]

output_dir           ./${export_subdir}

X1-grid    1    ${xmin}    ${nx}    u    ${xmax}
X2-grid    1    ${ymin}    ${ny}    u    ${ymax}
X3-grid    1    ${zmin}    ${nz}    u    ${zmax}

[Time]

CFL              0.4
CFL_max_var      1.1
tstop            ${tmax}
first_dt         1.e-4

[Solver]

Solver         tvdlf

[Boundary]

X1-beg        userdef
X1-end        outflow
X2-beg        outflow
X2-end        outflow
X3-beg        outflow
X3-end        outflow

[Static Grid Output]

uservar    0
dbl        ${dt_out}  -1   single_file
flt       -1.0  -1   single_file
vtk       -1.0  -1   single_file
dbl.h5    -1.0  -1
flt.h5    -1.0  -1
tab       -1.0  -1
ppm       -1.0  -1
png       -1.0  -1
log        1
analysis  -1.0  1

[Particles]

Nparticles          -1     1
particles_dbl        1.0  -1
particles_flt       -1.0  -1
particles_vtk       -1.0  -1
particles_tab       -1.0  -1

[Parameters]

GAMMA                       ${gamma}
RHO0                        ${rho0}
CS0                         ${cs0}
MACH                        ${mach}
MPERT                       ${mp}
RSOFT                       ${rsoft}
X1P                         0.0
X2P                         0.0
X3P                         0.0
CS_ALERT_THRESHOLD          ${cs_alert_threshold}
CS_ALERT_EVERY_STEPS        ${cs_alert_every_steps}
MACH_ALERT_THRESHOLD        ${mach_alert_threshold}
MACH_ALERT_EVERY_STEPS      ${mach_alert_every_steps}
EOF

cat > "${case_dir}/run_summary.txt" <<EOF
case_name = ${case_name}
dimension = 3
mach = ${mach}
mp = ${mp}
r_bondi = ${r_bondi}
rbhl = ${rbhl}
softening_mode = ${softening_mode}
a_soft = ${a_soft}
rsoft_over_rbondi = ${rsoft_over_rbondi}
rsoft_over_rbhl = ${rsoft_over_rbhl}
tmax = ${tmax}
vinf = ${vinf}
rsoft = ${rsoft}
cs_alert_threshold = ${cs_alert_threshold}
cs_alert_every_steps = ${cs_alert_every_steps}
mach_alert_threshold = ${mach_alert_threshold}
mach_alert_every_steps = ${mach_alert_every_steps}
cs0 = ${cs0}
rho0 = ${rho0}
gamma = ${gamma}
dx_target = ${dx_target}
dx_actual = ${dx_actual}
dy_actual = ${dy_actual}
dz_actual = ${dz_actual}
cells_per_rsoft_x = ${cells_per_rsoft_x}
cells_per_rsoft_y = ${cells_per_rsoft_y}
cells_per_rsoft_z = ${cells_per_rsoft_z}
cells_per_rbondi_x = ${cells_per_rbondi_x}
cells_per_rbondi_y = ${cells_per_rbondi_y}
cells_per_rbondi_z = ${cells_per_rbondi_z}
cells_per_rbhl_x = ${cells_per_rbhl_x}
cells_per_rbhl_y = ${cells_per_rbhl_y}
cells_per_rbhl_z = ${cells_per_rbhl_z}
boundary_xmin_over_rsoft = ${boundary_xmin_over_rsoft}
boundary_xmax_over_rsoft = ${boundary_xmax_over_rsoft}
boundary_ymin_over_rsoft = ${boundary_ymin_over_rsoft}
boundary_ymax_over_rsoft = ${boundary_ymax_over_rsoft}
boundary_zmin_over_rsoft = ${boundary_zmin_over_rsoft}
boundary_zmax_over_rsoft = ${boundary_zmax_over_rsoft}
min_cells_per_rsoft_warning = ${min_cells_per_rsoft}
min_boundary_over_rsoft_warning = ${min_boundary_over_rsoft}
nx = ${nx}
ny = ${ny}
nz = ${nz}
ncell = ${ncell}
xmin = ${xmin}
xmax = ${xmax}
ymin = ${ymin}
ymax = ${ymax}
zmin = ${zmin}
zmax = ${zmax}
log_lambda_max = ${log_lambda_max}
cells_per_rbhl_target = ${cells_per_rbhl}
x1p = 0.0
x2p = 0.0
x3p = 0.0
build_note = make uses PLUTO_DIR from the shell environment when set
output_subdir = ${export_subdir}
EOF

echo "Prepared ${case_dir}"
