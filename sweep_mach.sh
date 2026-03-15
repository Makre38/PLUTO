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
batch_size=5
script_index=1
run_all_script="run_all.sh"

rm -f "${runs_dir}"/submit_runs_*.sh "${submit_script}" "${run_all_script}"

{
  echo "#!/usr/bin/env bash"
  echo
  echo "set -euo pipefail"
  echo
  echo 'prev_jobid=""'
  echo
} > "${run_all_script}"

for ((i = 0; i < ${#generated_cases[@]}; i += batch_size)); do
  submit_runs_script="${runs_dir}/submit_runs_${script_index}.sh"
  {
    echo "#!/usr/bin/env bash"
    echo
    echo "set -euo pipefail"
    echo
    for ((j = i; j < i + batch_size && j < ${#generated_cases[@]}; ++j)); do
      case_dir="${generated_cases[j]}"
      echo "( cd ${case_dir} && sbatch job.sh )"
    done
  } > "${submit_runs_script}"
  chmod +x "${submit_runs_script}"
  {
    echo "if [[ -z \"\$prev_jobid\" ]]; then"
    echo "  submit_out=\$(sbatch --wrap=\"bash ${submit_runs_script}\")"
    echo "else"
    echo "  submit_out=\$(sbatch --dependency=afterany:\${prev_jobid} --wrap=\"bash ${submit_runs_script}\")"
    echo "fi"
    echo 'prev_jobid=$(printf "%s\n" "$submit_out" | awk "{print \$4}")'
    echo 'echo "$submit_out"'
    echo
  } >> "${run_all_script}"
  script_index=$((script_index + 1))
done

chmod +x "${run_all_script}"
cp "${runs_dir}/submit_runs_1.sh" "${submit_script}"

echo "Wrote ${run_all_script}"
echo "Wrote ${runs_dir}/submit_runs_*.sh"
