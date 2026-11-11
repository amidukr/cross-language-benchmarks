#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "$0")/scripts/common.sh"

if (($# > 2)); then die "Usage: $0 RUN_ID [OUTPUT_ROOT]"; fi
if [[ ${1:-} == --help ]]; then echo "Usage: $0 RUN_ID [OUTPUT_ROOT]"; exit 0; fi
run_id=${1:-}
[[ -n $run_id ]] || die "Usage: $0 RUN_ID [OUTPUT_ROOT]"
require_id run-id "$run_id"
output_root=${2:-$repo_root/reports/java-memory-test}
root="$output_root/$run_id"
[[ -d $root ]] || die "run not found: $root"
failures=0
trials=0
retained_failures=0
while IFS= read -r manifest; do
  ((trials += 1))
  dir=${manifest%/manifest.txt}
  status=$(sed -n 's/^status=//p' "$manifest" | tail -n 1)
  if [[ $status == failed ]]; then
    reason=$(sed -n 's/^failure_reason=//p' "$manifest" | tail -n 1)
    if [[ -z $reason ]]; then
      echo "INVALID failed-without-reason path=$dir"
      ((failures += 1))
    else
      echo "RETAINED failure=$reason path=$dir"
      ((retained_failures += 1))
    fi
    continue
  elif [[ $status != success ]]; then
    echo "INVALID status=$status path=$dir"
    ((failures += 1))
    continue
  fi
  for required in raw-samples.csv results.csv app.stdout host-manifest.txt toolchain-version.txt os-packages.txt; do
    if [[ ! -s $dir/$required ]]; then
      echo "INVALID missing=$required path=$dir"
      ((failures += 1))
    fi
  done
  for required in app.stderr container.stdout container.stderr; do
    if [[ ! -e $dir/$required ]]; then
      echo "INVALID missing=$required path=$dir"
      ((failures += 1))
    fi
  done
  duration_mode=$(sed -n 's/^duration_mode=//p' "$manifest" | tail -n 1)
  if [[ $duration_mode == survey ]]; then
    survey_count=$(awk -F, 'NR>1 && $3=="survey-idle"{n++} END{print n+0}' "$dir/raw-samples.csv")
    if [[ $survey_count != 100 ]]; then
      echo "INVALID samples survey=$survey_count path=$dir"
      ((failures += 1))
    fi
  else
    ready_count=$(awk -F, 'NR>1 && $3=="ready-idle"{n++} END{print n+0}' "$dir/raw-samples.csv")
    post_count=$(awk -F, 'NR>1 && $3=="post-exercise-idle"{n++} END{print n+0}' "$dir/raw-samples.csv")
    if [[ $ready_count != 300 || $post_count != 300 ]]; then
      echo "INVALID samples ready=$ready_count post=$post_count path=$dir"
      ((failures += 1))
    fi
  fi
  malformed_results=$(awk -F, 'NF!=17{n++} END{print n+0}' "$dir/results.csv")
  if [[ $malformed_results != 0 ]]; then
    echo "INVALID result_csv_rows=$malformed_results path=$dir"
    ((failures += 1))
  fi
  if ! grep -q '^MEMORY_TEST_READY ' "$dir/app.stdout"; then
    echo "INVALID readiness-marker path=$dir"
    ((failures += 1))
  fi
  request_failures=$(sed -n 's/^request_failures=//p' "$manifest" | tail -n 1)
  if [[ ${request_failures:-missing} != 0 ]]; then
    echo "INVALID request_failures=${request_failures:-missing} path=$dir"
    ((failures += 1))
  fi
done < <(find "$root" -type f -name manifest.txt -path '*/[0-9]*/manifest.txt' | sort)
echo "validated_attempts=$trials retained_expected_failures=$retained_failures invalid=$failures"
((trials > 0 && failures == 0))
