#!/usr/bin/env bash

# Matched, non-accreting cases: only A_SOFT varies within this sweep.
set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd "${script_dir}/.." && pwd)"

if [[ -v RSOFT_FRAC || -v A_SOFT ]]; then
  echo "Use A_SOFT_VALUES for this sweep; unset A_SOFT and RSOFT_FRAC." >&2
  exit 1
fi
# Exploratory values, not a literature calibration or a convergence claim.
values="${A_SOFT_VALUES-10 3 1 0.3 0.1}"
read -r -a a_soft_values <<< "${values//$'\n'/ }"
(( ${#a_soft_values[@]} > 0 )) || { echo "A_SOFT_VALUES must not be empty." >&2; exit 1; }
# Validate the entire list before generating any cases (including duplicates).
awk '
  BEGIN { ok=1 }
  {
    if ($0 !~ /^[+]?([0-9]+([.][0-9]*)?|[.][0-9]+)([eE][+-]?[0-9]+)?$/ ||
        $0+0 <= 0 || ($0+0)-($0+0) != 0) {
      print "Invalid A_SOFT_VALUES entry: " $0 > "/dev/stderr"; ok=0
    }
    key=sprintf("%.17g", $0+0)
    if (seen[key]++) { print "Duplicate A_SOFT_VALUES entry: " $0 > "/dev/stderr"; ok=0 }
  }
  END { exit !ok }
' < <(printf '%s\n' "${a_soft_values[@]}")

runs_dir="${RUNS_DIR:-${repo_dir}/runs_3d_softening}"
mkdir -p "${runs_dir}/manifests"
manifest_path="$(mktemp "${runs_dir}/manifests/softening_3d.XXXXXX.txt")"
echo "No-sink benchmark: forcing SINK_RADIUS=0; varying A_SOFT only."
echo "Manifest: ${manifest_path} (records each successfully prepared case)"
for a_soft in "${a_soft_values[@]}"; do
  output="$(A_SOFT="${a_soft}" SINK_RADIUS=0 RUNS_DIR="${runs_dir}" \
    "${script_dir}/prepare_one_case_3d.sh")"
  printf '%s\n' "${output}"
  case_dir="$(printf '%s\n' "${output}" | sed -n 's/^Prepared //p')"
  [[ -n "${case_dir}" ]] || { echo "Missing generated case path." >&2; exit 1; }
  printf '%s\n' "${case_dir}" >> "${manifest_path}"
done
echo "Wrote manifest ${manifest_path}"
