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

mach_min="${MACH_MIN:-0.1}"
mach_max="${MACH_MAX:-1.1}"
mach_step="${MACH_STEP:-0.5}"

mp="${MP:-1.0}"
log_lambda_max="${LOG_LAMBDA_MAX:-2.0}"
cells_per_rbhl="${CELLS_PER_RBHL:-2.0}"
n_output="${N_OUTPUT:-80}"

gamma="${GAMMA:-1.0001}"
rho0="${RHO0:-1.0}"
cs0="${CS0:-1.0}"
# Preserve whether RSOFT_FRAC was explicitly supplied; do not manufacture a
# conflict with A_SOFT by forwarding the legacy default.
if [[ -v A_SOFT && -v RSOFT_FRAC ]]; then
  echo "Specify either A_SOFT or RSOFT_FRAC, not both." >&2
  exit 1
fi
softening_env=()
softening_suffix=""
if [[ -v A_SOFT ]]; then
  awk -v a="${A_SOFT}" 'BEGIN {
    if (a !~ /^[+]?([0-9]+([.][0-9]*)?|[.][0-9]+)([eE][+-]?[0-9]+)?$/ || a+0 <= 0 || a-a != 0) {
      print "A_SOFT must be a finite positive number" > "/dev/stderr"; exit 1
    }
  }'
  softening_env+=("A_SOFT=${A_SOFT}")
  softening_suffix="_asoft${A_SOFT}"
elif [[ -v RSOFT_FRAC ]]; then
  softening_env+=("RSOFT_FRAC=${RSOFT_FRAC}")
fi
cs_alert_threshold="${CS_ALERT_THRESHOLD:-1.0e-6}"
cs_alert_every_steps="${CS_ALERT_EVERY_STEPS:-1}"
mach_alert_threshold="${MACH_ALERT_THRESHOLD:-0.0}"
mach_alert_every_steps="${MACH_ALERT_EVERY_STEPS:-1}"

margin_up="${MARGIN_UP:-1.2}"
margin_down="${MARGIN_DOWN:-1.3}"
margin_y="${MARGIN_Y:-1.3}"
upstream_min="${UPSTREAM_MIN:-5.0}"

warn_cells="${WARN_CELLS:-2000000}"
hard_cells="${HARD_CELLS:-8000000}"
runs_dir="${RUNS_DIR:-${repo_dir}/runs_3d}"

manifest_dir="${runs_dir}/manifests"
mkdir -p "${manifest_dir}"

manifest_name="mach${mach_min}-${mach_max}_step${mach_step}_mp${mp}_ll${log_lambda_max}_rbhl${cells_per_rbhl}_3d${softening_suffix}.txt"
manifest_path="${manifest_dir}/${manifest_name}"
if [[ -v A_SOFT ]]; then
  manifest_path="$(mktemp "${manifest_dir}/${manifest_name%.txt}.XXXXXX.txt")"
fi
: > "${manifest_path}"

while IFS= read -r mach; do
  [[ -z "${mach}" ]] && continue

  output="$(
    MACH="${mach}" \
    MP="${mp}" \
    LOG_LAMBDA_MAX="${log_lambda_max}" \
    CELLS_PER_RBHL="${cells_per_rbhl}" \
    N_OUTPUT="${n_output}" \
    GAMMA="${gamma}" \
    RHO0="${rho0}" \
    CS0="${cs0}" \
    CS_ALERT_THRESHOLD="${cs_alert_threshold}" \
    CS_ALERT_EVERY_STEPS="${cs_alert_every_steps}" \
    MACH_ALERT_THRESHOLD="${mach_alert_threshold}" \
    MACH_ALERT_EVERY_STEPS="${mach_alert_every_steps}" \
    MARGIN_UP="${margin_up}" \
    MARGIN_DOWN="${margin_down}" \
    MARGIN_Y="${margin_y}" \
    UPSTREAM_MIN="${upstream_min}" \
    WARN_CELLS="${warn_cells}" \
    HARD_CELLS="${hard_cells}" \
    RUNS_DIR="${runs_dir}" \
    env "${softening_env[@]}" "${script_dir}/prepare_one_case_3d.sh"
  )"
  printf '%s\n' "${output}"

  case_dir="$(printf '%s\n' "${output}" | sed -n 's/^Prepared //p')"
  [[ -n "${case_dir}" ]] || {
    echo "Failed to determine generated case directory for Mach=${mach}" >&2
    exit 1
  }
  printf '%s\n' "${case_dir}" >> "${manifest_path}"
done < <(
  awk -v lo="${mach_min}" -v hi="${mach_max}" -v step="${mach_step}" '
    BEGIN {
      i = 0
      for (mach = lo; mach <= hi + 0.5*step; mach += step) {
        printf("%.6f\n", mach)
        i++
        if (i > 100000) exit 1
      }
    }
  '
)

echo "Wrote manifest ${manifest_path}"
