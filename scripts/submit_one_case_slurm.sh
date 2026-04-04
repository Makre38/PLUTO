#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 CASE_DIR" >&2
  exit 1
fi

case_dir="$1"
[[ -d "${case_dir}" ]] || {
  echo "Missing case directory: ${case_dir}" >&2
  exit 1
}

case_name="$(basename "${case_dir}")"
job_name="$(printf '%s\n' "${case_name}" | awk -F'_' '{print $1}')"
partition="${SLURM_PARTITION:-c79}"
time_limit="${SLURM_TIME_LIMIT:-30-00:00:00}"
stdout_path="${SLURM_STDOUT_PATH:-${case_dir}/slurm-%x-%j.out}"
stderr_path="${SLURM_STDERR_PATH:-${case_dir}/slurm-%x-%j.err}"
dependency="${SLURM_DEPENDENCY:-}"

cmd=(sbatch
  -J "${job_name}"
  -p "${partition}"
  --nodes=1
  --ntasks=1
  -t "${time_limit}"
  -o "${stdout_path}"
  -e "${stderr_path}"
)

if [[ -n "${dependency}" ]]; then
  cmd+=(--dependency="${dependency}")
fi

cmd+=(--wrap "bash ${script_dir}/run_one_case_local.sh ${case_dir}")

"${cmd[@]}"
