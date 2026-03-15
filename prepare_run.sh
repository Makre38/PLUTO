#!/usr/bin/env bash

set -euo pipefail

mach="${MACH:-1.0}"
mp="${MP:-1.0}"
log_lambda_max="${LOG_LAMBDA_MAX:-2.0}"
cells_per_rbhl="${CELLS_PER_RBHL:-8.0}"
n_output="${N_OUTPUT:-20}"

gamma="${GAMMA:-1.0001}"
rho0="${RHO0:-1.0}"
cs0="${CS0:-1.0}"
rsoft_frac="${RSOFT_FRAC:-0.25}"

margin_up="${MARGIN_UP:-1.2}"
margin_down="${MARGIN_DOWN:-1.3}"
margin_y="${MARGIN_Y:-1.3}"
upstream_min="${UPSTREAM_MIN:-5.0}"

warn_cells="${WARN_CELLS:-2000000}"
hard_cells="${HARD_CELLS:-8000000}"

runs_dir="${RUNS_DIR:-runs}"

eval "$(awk -v mach="${mach}" \
              -v mp="${mp}" \
              -v log_lambda_max="${log_lambda_max}" \
              -v cells_per_rbhl="${cells_per_rbhl}" \
              -v n_output="${n_output}" \
              -v cs0="${cs0}" \
              -v rsoft_frac="${rsoft_frac}" \
              -v margin_up="${margin_up}" \
              -v margin_down="${margin_down}" \
              -v margin_y="${margin_y}" \
              -v upstream_min="${upstream_min}" \
              -v warn_cells="${warn_cells}" \
              -v hard_cells="${hard_cells}" '
function ceil(x) { return (x == int(x)) ? x : int(x) + 1 }
function max2(a,b) { return (a > b) ? a : b }
function max3(a,b,c) { return max2(a, max2(b, c)) }
BEGIN {
  rbhl = mp/(1.0 + mach*mach)
  tmax = rbhl/cs0*exp(log_lambda_max)
  vinf = mach*cs0
  rsoft = rsoft_frac*rbhl
  dx_target = rbhl/cells_per_rbhl
  l_up_wave = margin_up*tmax*max2(cs0 - vinf, 0.0)
  l_up = max3(upstream_min, 3.0*rbhl, l_up_wave)
  l_down = margin_down*tmax*(cs0 + vinf)
  l_y = margin_y*tmax*cs0
  xmin = -l_up
  xmax = l_down
  ymin = -l_y
  ymax = l_y
  nx = ceil((xmax - xmin)/dx_target)
  ny = ceil((ymax - ymin)/dx_target)
  ncell = nx*ny
  dx_actual = (xmax - xmin)/nx
  dy_actual = (ymax - ymin)/ny
  dt_out = tmax/n_output
  warn = (ncell > warn_cells) ? 1 : 0
  hard = (ncell > hard_cells) ? 1 : 0
  case_name = sprintf("mach%.3f_mp%.3f_ll%.3f_rbhl%.1f", mach, mp, log_lambda_max, cells_per_rbhl)

  printf("rbhl=%.17g\n", rbhl)
  printf("tmax=%.17g\n", tmax)
  printf("vinf=%.17g\n", vinf)
  printf("rsoft=%.17g\n", rsoft)
  printf("dx_target=%.17g\n", dx_target)
  printf("dx_actual=%.17g\n", dx_actual)
  printf("dy_actual=%.17g\n", dy_actual)
  printf("xmin=%.17g\n", xmin)
  printf("xmax=%.17g\n", xmax)
  printf("ymin=%.17g\n", ymin)
  printf("ymax=%.17g\n", ymax)
  printf("dt_out=%.17g\n", dt_out)
  printf("nx=%d\n", nx)
  printf("ny=%d\n", ny)
  printf("ncell=%d\n", ncell)
  printf("warn=%d\n", warn)
  printf("hard=%d\n", hard)
  printf("case_name=%s\n", case_name)
}')"

if [[ "${hard}" -eq 1 ]]; then
  echo "Refusing to generate run: Ncell=${ncell} exceeds HARD_CELLS=${hard_cells}" >&2
  exit 1
fi

if [[ "${warn}" -eq 1 ]]; then
  echo "Warning: Ncell=${ncell} exceeds WARN_CELLS=${warn_cells}" >&2
fi

run_dir="${runs_dir}/${case_name}"
mkdir -p "${run_dir}"
mkdir -p "${run_dir}/output"

cp definitions.h init.c makefile local_make "${run_dir}/"

cat > "${run_dir}/pluto.ini" <<EOF
[Grid]

output_dir           ./output

X1-grid    1    ${xmin}    ${nx}    u    ${xmax}
X2-grid    1    ${ymin}    ${ny}    u    ${ymax}
X3-grid    1    0.0    1    u    1.0

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
analysis  -1.0  -1

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
EOF

cat > "${run_dir}/run_summary.txt" <<EOF
case_name = ${case_name}
rbhl = ${rbhl}
tmax = ${tmax}
vinf = ${vinf}
rsoft = ${rsoft}
dx_target = ${dx_target}
dx_actual = ${dx_actual}
dy_actual = ${dy_actual}
nx = ${nx}
ny = ${ny}
ncell = ${ncell}
xmin = ${xmin}
xmax = ${xmax}
ymin = ${ymin}
ymax = ${ymax}
log_lambda_max = ${log_lambda_max}
cells_per_rbhl_target = ${cells_per_rbhl}
EOF

echo "Prepared ${run_dir}"
