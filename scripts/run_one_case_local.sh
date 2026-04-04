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

start_time="$(date)"
echo "start: ${start_time}"
echo "case dir: ${case_dir}"

(
  cd "${case_dir}"
  make clean
  make
  ./pluto
)

finish_time="$(date)"
echo "finish: ${finish_time}"
