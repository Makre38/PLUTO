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
mpi_launcher="${MPI_LAUNCHER:-mpirun}"
case "${mpi_launcher}" in
  mpirun|srun) ;;
  *)
    echo "MPI_LAUNCHER must be either 'mpirun' or 'srun'" >&2
    exit 1
    ;;
esac

start_epoch="$(date +%s)"
stage="startup"
stage_log="${case_dir}/run_stage_3d.log"

log_stage() {
  stage="$1"
  shift
  printf '%s stage=%s %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "${stage}" "$*" | tee -a "${stage_log}"
}

echo "start: $(date)"
echo "case dir: ${case_dir}"
echo "arch: ${arch}"
echo "mpi tasks: ${mpi_tasks}"
echo "mpi launcher: ${mpi_launcher}"
echo "stage log: ${stage_log}"

finish_log() {
  status=$?
  end_epoch="$(date +%s)"
  last_stage="${stage}"
  log_stage "finish" "exit_status=${status} elapsed_sec=$((end_epoch - start_epoch)) last_stage=${last_stage}"
  echo "end: $(date)"
  echo "elapsed_sec: $((end_epoch - start_epoch))"
  echo "exit_status: ${status}"
  echo "last_stage: ${last_stage}"
}
trap finish_log EXIT

cd "${case_dir}"
log_stage "build_clean_start" "cmd=make clean ARCH=${arch}"
make clean ARCH="${arch}"
log_stage "build_clean_done" "cmd=make clean ARCH=${arch}"
log_stage "build_start" "cmd=make ARCH=${arch}"
make ARCH="${arch}"
log_stage "build_done" "cmd=make ARCH=${arch}"
log_stage "run_start" "mpi_tasks=${mpi_tasks} launcher=${mpi_launcher}"
if (( mpi_tasks > 1 )); then
  if [[ "${mpi_launcher}" == "srun" ]]; then
    echo "run command: srun -n ${mpi_tasks} ./pluto"
    srun -n "${mpi_tasks}" ./pluto
  else
    echo "run command: mpirun -n ${mpi_tasks} ./pluto"
    mpirun -n "${mpi_tasks}" ./pluto
  fi
else
  echo "run command: ./pluto"
  ./pluto
fi
log_stage "run_done" "mpi_tasks=${mpi_tasks} launcher=${mpi_launcher}"
