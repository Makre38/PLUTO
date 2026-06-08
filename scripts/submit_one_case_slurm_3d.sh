#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 CASE_DIR" >&2
  exit 1
fi

case_dir="$(cd "$1" && pwd)"
[[ -d "${case_dir}" ]] || {
  echo "Missing case directory: ${case_dir}" >&2
  exit 1
}

case_name="$(basename "${case_dir}")"
job_name="$(printf '%s\n' "${case_name}" | awk -F'_' '{print $1 "_3d"}')"
partition="${SLURM_PARTITION:-c79}"
time_limit="${SLURM_TIME_LIMIT:-30-00:00:00}"
stdout_path="${SLURM_STDOUT_PATH:-${case_dir}/slurm-%x-%j.out}"
stderr_path="${SLURM_STDERR_PATH:-${case_dir}/slurm-%x-%j.err}"
dependency="${SLURM_DEPENDENCY:-}"
mpi_tasks="${MPI_TASKS:-1}"
[[ "${mpi_tasks}" =~ ^[0-9]+$ ]] || {
  echo "MPI_TASKS must be an integer" >&2
  exit 1
}
(( mpi_tasks > 0 )) || {
  echo "MPI_TASKS must be positive" >&2
  exit 1
}
mpi_launcher="${MPI_LAUNCHER:-mpirun}"
case "${mpi_launcher}" in
  mpirun|srun) ;;
  *)
    echo "MPI_LAUNCHER must be either 'mpirun' or 'srun'" >&2
    exit 1
    ;;
esac

cmd=(sbatch
  -J "${job_name}"
  -p "${partition}"
  --nodes=1
  --ntasks="${mpi_tasks}"
  -t "${time_limit}"
  -o "${stdout_path}"
  -e "${stderr_path}"
)

if [[ -n "${dependency}" ]]; then
  cmd+=(--dependency="${dependency}")
fi

printf -v wrap_cmd 'MPI_TASKS=%q MPI_LAUNCHER=%q bash %q %q' \
  "${mpi_tasks}" "${mpi_launcher}" "${script_dir}/run_one_case_local_3d.sh" "${case_dir}"
cmd+=(--wrap "${wrap_cmd}")

"${cmd[@]}"
