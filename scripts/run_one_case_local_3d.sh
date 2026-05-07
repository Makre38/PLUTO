#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 CASE_DIR" >&2
  exit 1
fi

case_dir="$(cd "$1" && pwd)"
[[ -d "${case_dir}" ]] || {
  echo "Missing case directory: ${case_dir}" >&2
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

if (( mpi_tasks > 1 )); then
  arch="${PLUTO_ARCH:-Linux.mpicc.defs}"
else
  arch="${PLUTO_ARCH:-Linux.gcc.defs}"
fi

start_epoch="$(date +%s)"
echo "start: $(date)"
echo "case dir: ${case_dir}"
echo "arch: ${arch}"
echo "mpi tasks: ${mpi_tasks}"

finish_log() {
  status=$?
  end_epoch="$(date +%s)"
  echo "end: $(date)"
  echo "elapsed_sec: $((end_epoch - start_epoch))"
  echo "exit_status: ${status}"
}
trap finish_log EXIT

(
  cd "${case_dir}"
  make clean ARCH="${arch}"
  make ARCH="${arch}"
  if (( mpi_tasks > 1 )); then
    mpirun -n "${mpi_tasks}" ./pluto
  else
    ./pluto
  fi
)
