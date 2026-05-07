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

mpi_tasks="${MPI_TASKS:-1}"
[[ "${mpi_tasks}" =~ ^[0-9]+$ ]] || {
  echo "MPI_TASKS must be an integer" >&2
  exit 1
}
(( mpi_tasks > 0 )) || {
  echo "MPI_TASKS must be positive" >&2
  exit 1
}

if [[ -n "${MAX_CONCURRENT_JOBS:-}" ]]; then
  max_concurrent_jobs="${MAX_CONCURRENT_JOBS}"
  [[ "${max_concurrent_jobs}" =~ ^[0-9]+$ ]] || {
    echo "MAX_CONCURRENT_JOBS must be an integer" >&2
    exit 1
  }
  (( max_concurrent_jobs > 0 )) || {
    echo "MAX_CONCURRENT_JOBS must be positive" >&2
    exit 1
  }
elif [[ -n "${MAX_TOTAL_TASKS:-}" ]]; then
  [[ "${MAX_TOTAL_TASKS}" =~ ^[0-9]+$ ]] || {
    echo "MAX_TOTAL_TASKS must be an integer" >&2
    exit 1
  }
  (( MAX_TOTAL_TASKS > 0 )) || {
    echo "MAX_TOTAL_TASKS must be positive" >&2
    exit 1
  }
  max_concurrent_jobs=$((MAX_TOTAL_TASKS / mpi_tasks))
  (( max_concurrent_jobs > 0 )) || {
    echo "MAX_TOTAL_TASKS must be at least MPI_TASKS" >&2
    exit 1
  }
else
  max_concurrent_jobs=1
fi

max_total_tasks=$((mpi_tasks * max_concurrent_jobs))
base_dependency="${SLURM_DEPENDENCY:-}"
slot_jobids=()

echo "mpi_tasks_per_case: ${mpi_tasks}" >&2
echo "max_concurrent_jobs: ${max_concurrent_jobs}" >&2
echo "max_total_tasks: ${max_total_tasks}" >&2

submit_index=0

while IFS= read -r case_dir; do
  [[ -z "${case_dir}" ]] && continue

  slot=$((submit_index % max_concurrent_jobs))
  dependency="${base_dependency}"

  if [[ -n "${slot_jobids[slot]:-}" ]]; then
    if [[ -n "${dependency}" ]]; then
      dependency+=",afterany:${slot_jobids[slot]}"
    else
      dependency="afterany:${slot_jobids[slot]}"
    fi
  fi

  if [[ -n "${dependency}" ]]; then
    submit_out="$(
      MPI_TASKS="${mpi_tasks}" \
      SLURM_DEPENDENCY="${dependency}" \
      "${script_dir}/submit_one_case_slurm_3d.sh" "${case_dir}"
    )"
  else
    submit_out="$(
      MPI_TASKS="${mpi_tasks}" \
      "${script_dir}/submit_one_case_slurm_3d.sh" "${case_dir}"
    )"
  fi

  printf '%s\n' "${submit_out}"
  jobid="$(printf '%s\n' "${submit_out}" | awk '{print $4}')"
  [[ -n "${jobid}" ]] || {
    echo "Failed to parse Slurm job id from: ${submit_out}" >&2
    exit 1
  }

  slot_jobids[slot]="${jobid}"
  submit_index=$((submit_index + 1))
done < "${manifest_path}"
