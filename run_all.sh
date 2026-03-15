#!/usr/bin/env bash

set -euo pipefail

prev_jobid=""

if [[ -z "$prev_jobid" ]]; then
  submit_out=$(sbatch --wrap="bash runs/submit_runs_1.sh")
else
  submit_out=$(sbatch --dependency=afterany:${prev_jobid} --wrap="bash runs/submit_runs_1.sh")
fi
prev_jobid=$(printf "%s\n" "$submit_out" | awk "{print \$4}")
echo "$submit_out"

if [[ -z "$prev_jobid" ]]; then
  submit_out=$(sbatch --wrap="bash runs/submit_runs_2.sh")
else
  submit_out=$(sbatch --dependency=afterany:${prev_jobid} --wrap="bash runs/submit_runs_2.sh")
fi
prev_jobid=$(printf "%s\n" "$submit_out" | awk "{print \$4}")
echo "$submit_out"

if [[ -z "$prev_jobid" ]]; then
  submit_out=$(sbatch --wrap="bash runs/submit_runs_3.sh")
else
  submit_out=$(sbatch --dependency=afterany:${prev_jobid} --wrap="bash runs/submit_runs_3.sh")
fi
prev_jobid=$(printf "%s\n" "$submit_out" | awk "{print \$4}")
echo "$submit_out"

