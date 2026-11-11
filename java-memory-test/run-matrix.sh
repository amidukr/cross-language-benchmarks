#!/usr/bin/env bash
set -uo pipefail
source "$(dirname -- "$0")/scripts/common.sh"

if (($# > 2)); then die "Usage: $0 RUN_ID [OUTPUT_ROOT]"; fi
if [[ ${1:-} == --help ]]; then echo "Usage: $0 RUN_ID [OUTPUT_ROOT]"; exit 0; fi
run_id=${1:-}
[[ -n $run_id ]] || die "Usage: $0 RUN_ID [OUTPUT_ROOT]"
require_id run-id "$run_id"
output_root=${2:-$repo_root/reports/java-memory-test}
mkdir -p "$output_root"
output_root=$(cd -- "$output_root" && pwd)
run_root="$output_root/$run_id"
[[ ! -e $run_root ]] || die "run ID already exists: $run_root"
mkdir -p "$run_root"
{
  echo "run_id=$run_id"
  echo "started_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "status=running"
} >"$run_root/matrix-manifest.txt"

echo "PROBE collectors and heap options"
if ! "$memory_root/probe-collectors.sh" --output "$run_root/probes"; then
  echo "collector probing failed" >&2
  echo "status=failed" >>"$run_root/matrix-manifest.txt"
  exit 1
fi

trial_count=1
duration_mode=survey
collector_policy=${MEMORY_COLLECTOR_POLICY:-default}
heap_profiles=(
  'default||'
  'xms-1m|1m|'
  'xms-1m-xmx-16m|1m|16m'
  'xms-1m-xmx-1024m|1m|1024m'
  'xms-512m-xmx-1024m|512m|1024m'
)
progress=0
failed_retained=0

run_config() {
  local app=$1 target=$2 collector=$3 profile=$4 trial=$5 xms=${6:-} xmx=${7:-} mode=${8:-$duration_mode}
  ((progress += 1))
  local phase=TRIAL
  [[ $probe_only == true ]] && phase=PROBE
  echo "$phase $progress duration=$mode application=$app target=$target collector=$collector heap_profile=$profile xms=${xms:-default} xmx=${xmx:-default} trial=$trial"
  args=(--application "$app" --target "$target" --collector "$collector" \
    --heap-profile "$profile" --run-id "$run_id" --trial "$trial" --output "$output_root")
  [[ -z $xms ]] || args+=(--xms "$xms")
  [[ -z $xmx ]] || args+=(--xmx "$xmx")
  args+=(--duration-mode "$mode")
  "$memory_root/run-one.sh" "${args[@]}"
}

for app in console swing spring-boot quarkus; do
  for target in temurin-c2 graalvm-jit graalvm-native; do
    xms_supported=$(awk -F '\t' -v t="$target" 'NR>1 && $1==t && $2=="xms"{print $3}' "$run_root/probes/heap-options.tsv")
    xmx_supported=$(awk -F '\t' -v t="$target" 'NR>1 && $1==t && $2=="xmx"{print $3}' "$run_root/probes/heap-options.tsv")
    if [[ $collector_policy == default ]]; then
      mapfile -t collectors < <(awk -F '\t' -v t="$target" 'NR>1 && $1==t && $2=="default" && $3=="supported"{print $2}' "$run_root/probes/support.tsv")
    elif [[ $collector_policy == all ]]; then
      mapfile -t collectors < <(awk -F '\t' -v t="$target" 'NR>1 && $1==t && $3=="supported"{print $2}' "$run_root/probes/support.tsv")
    else
      echo "invalid MEMORY_COLLECTOR_POLICY=$collector_policy (expected default or all)" >&2
      exit 2
    fi
    if ((${#collectors[@]} == 0)); then
      mkdir -p "$run_root/$app/$target"
      printf 'status=unsupported\nreason=no-supported-collector\n' >"$run_root/$app/$target/unsupported.txt"
      continue
    fi
    for collector in "${collectors[@]}"; do
      if [[ $target == graalvm-native && $collector == default ]]; then
        # Default is retained separately even when it resolves to Serial.
        :
      fi

      for heap_config in "${heap_profiles[@]}"; do
        IFS='|' read -r profile xms xmx <<<"$heap_config"
        if [[ -n $xms && $xms_supported != supported ]] || [[ -n $xmx && $xmx_supported != supported ]]; then
          mkdir -p "$run_root/$app/$target/$collector/$profile"
          printf 'status=unsupported\nreason=heap-option-not-supported\nxms_support=%s\nxmx_support=%s\n' \
            "$xms_supported" "$xmx_supported" >"$run_root/$app/$target/$collector/$profile/unsupported.txt"
          continue
        fi
        for ((trial=1; trial<=trial_count; trial++)); do
          run_config "$app" "$target" "$collector" "$profile" "$trial" "$xms" "$xmx" || ((failed_retained += 1))
        done
      done

      boundary="$run_root/$app/$target/$collector/viability-boundary.txt"
      mkdir -p "${boundary%/*}"
      {
        echo "heap_profiles=${heap_profiles[*]}"
  echo "trials_per_profile=$trial_count"
  echo "duration_mode=$duration_mode"
        echo "xms_option_support=$xms_supported"
        echo "xmx_option_support=$xmx_supported"
        echo "scope=smallest successful tested grid value in this environment"
      } >"$boundary"
    done
  done
done

{
  echo "completed_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "configurations_attempted=$progress"
  echo "failed_attempts_retained=$failed_retained"
  echo "status=complete"
} >>"$run_root/matrix-manifest.txt"
"$memory_root/summarize.sh" "$run_id" "$output_root"
echo "Task 4.1 collection complete: $run_root"
