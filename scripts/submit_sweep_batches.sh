#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 MANIFEST_PATH" >&2
  exit 1
fi

manifest_path="$1"
[[ -f "${manifest_path}" ]] || {
  echo "Missing manifest: ${manifest_path}" >&2
  exit 1
}

batch_size="${BATCH_SIZE:-5}"
[[ "${batch_size}" =~ ^[0-9]+$ ]] || {
  echo "BATCH_SIZE must be an integer" >&2
  exit 1
}
(( batch_size > 0 )) || {
  echo "BATCH_SIZE must be positive" >&2
  exit 1
}

mapfile -t case_dirs < "${manifest_path}"

prev_jobid=""

for ((i = 0; i < ${#case_dirs[@]}; i += batch_size)); do
  batch_case_dirs=()
  for ((j = i; j < i + batch_size && j < ${#case_dirs[@]}; ++j)); do
    [[ -n "${case_dirs[j]}" ]] && batch_case_dirs+=("${case_dirs[j]}")
  done
  (( ${#batch_case_dirs[@]} > 0 )) || continue

  wrap_cmd="set -euo pipefail"
  for case_dir in "${batch_case_dirs[@]}"; do
    wrap_cmd+="; bash ${script_dir}/run_one_case_local.sh $(printf '%q' "${case_dir}")"
  done

  first_case="$(basename "${batch_case_dirs[0]}")"
  last_case="$(basename "${batch_case_dirs[${#batch_case_dirs[@]}-1]}")"
  job_name="${first_case%%_*}-to-${last_case%%_*}"
  partition="${SLURM_PARTITION:-c79}"
  time_limit="${SLURM_TIME_LIMIT:-30-00:00:00}"
  stdout_path="${SLURM_STDOUT_PATH:-$(dirname "${manifest_path}")/slurm-%x-%j.out}"
  stderr_path="${SLURM_STDERR_PATH:-$(dirname "${manifest_path}")/slurm-%x-%j.err}"

  cmd=(sbatch
    -J "${job_name}"
    -p "${partition}"
    --nodes=1
    --ntasks=1
    -t "${time_limit}"
    -o "${stdout_path}"
    -e "${stderr_path}"
  )

  if [[ -n "${prev_jobid}" ]]; then
    cmd+=(--dependency="afterany:${prev_jobid}")
  fi

  cmd+=(--wrap "${wrap_cmd}")

  submit_out="$("${cmd[@]}")"
  printf '%s\n' "${submit_out}"
  prev_jobid="$(printf '%s\n' "${submit_out}" | awk '{print $4}')"
done
