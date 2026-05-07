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

start_epoch="$(date +%s)"
echo "start: $(date)"
echo "case dir: ${case_dir}"

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
  make clean
  make
  ./pluto
)
