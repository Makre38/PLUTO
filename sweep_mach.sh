#!/usr/bin/env bash

set -euo pipefail

mach_min="${MACH_MIN:-0.1}"
mach_max="${MACH_MAX:-5.0}"
mach_step="${MACH_STEP:-0.1}"

mp="${MP:-1.0}"
log_lambda_max="${LOG_LAMBDA_MAX:-2.0}"
cells_per_rbhl="${CELLS_PER_RBHL:-2.0}"
n_output="${N_OUTPUT:-80}"

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

generated_cases=()

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
    RSOFT_FRAC="${rsoft_frac}" \
    MARGIN_UP="${margin_up}" \
    MARGIN_DOWN="${margin_down}" \
    MARGIN_Y="${margin_y}" \
    UPSTREAM_MIN="${upstream_min}" \
    WARN_CELLS="${warn_cells}" \
    HARD_CELLS="${hard_cells}" \
    RUNS_DIR="${runs_dir}" \
    ./prepare_run.sh
  )"
  printf '%s\n' "${output}"

  case_dir="$(printf '%s\n' "${output}" | awk '/^Prepared /{print $2}')"
  [[ -n "${case_dir}" ]] || {
    echo "Failed to determine generated run directory for Mach=${mach}" >&2
    exit 1
  }
  generated_cases+=("${case_dir}")
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

submit_script="${runs_dir}/submit_all.sh"
{
  echo "#!/usr/bin/env bash"
  echo
  echo "set -euo pipefail"
  echo
  echo "batch_size=5"
  echo "count=0"
  echo
  for case_dir in "${generated_cases[@]}"; do
    echo "sbatch ${case_dir}/job.sh"
    echo "count=\$((count + 1))"
    echo "if (( count % batch_size == 0 )); then"
    echo "  echo \"Submitted \$count jobs; press Enter to continue with the next batch...\""
    echo "  read -r _"
    echo "fi"
    echo
  done
} > "${submit_script}"
chmod +x "${submit_script}"

echo "Wrote ${submit_script}"
