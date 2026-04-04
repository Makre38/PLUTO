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

prev_jobid=""

while IFS= read -r case_dir; do
  [[ -z "${case_dir}" ]] && continue

  if [[ -n "${prev_jobid}" ]]; then
    submit_out="$(
      SLURM_DEPENDENCY="afterany:${prev_jobid}" \
      "${script_dir}/submit_one_case_slurm.sh" "${case_dir}"
    )"
  else
    submit_out="$("${script_dir}/submit_one_case_slurm.sh" "${case_dir}")"
  fi

  printf '%s\n' "${submit_out}"
  prev_jobid="$(printf '%s\n' "${submit_out}" | awk '{print $4}')"
done < "${manifest_path}"
