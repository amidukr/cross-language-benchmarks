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

xms_values=(1m 2m 4m 8m 12m 16m 24m 32m 48m 64m)
xmx_desc=(512m 384m 256m 192m 128m 96m 64m 48m 32m 24m 16m 12m 8m 4m)
xmx_asc=(4m 8m 12m 16m 24m 32m 48m 64m 96m 128m 192m 256m 384m 512m)
progress=0
failed_retained=0

run_config() {
  local app=$1 target=$2 collector=$3 profile=$4 trial=$5 xms=${6:-} xmx=${7:-}
  ((progress += 1))
  echo "RUN $progress application=$app target=$target collector=$collector heap_profile=$profile xms=${xms:-default} xmx=${xmx:-default} trial=$trial"
  args=(--application "$app" --target "$target" --collector "$collector" \
    --heap-profile "$profile" --run-id "$run_id" --trial "$trial" --output "$output_root")
  [[ -z $xms ]] || args+=(--xms "$xms")
  [[ -z $xmx ]] || args+=(--xmx "$xmx")
  "$memory_root/run-one.sh" "${args[@]}"
}

for app in console swing spring-boot quarkus; do
  for target in temurin-c2 graalvm-jit graalvm-native; do
    xms_supported=$(awk -F '\t' -v t="$target" 'NR>1 && $1==t && $2=="xms"{print $3}' "$run_root/probes/heap-options.tsv")
    xmx_supported=$(awk -F '\t' -v t="$target" 'NR>1 && $1==t && $2=="xmx"{print $3}' "$run_root/probes/heap-options.tsv")
    mapfile -t collectors < <(awk -F '\t' -v t="$target" 'NR>1 && $1==t && $3=="supported"{print $2}' "$run_root/probes/support.tsv")
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

      for trial in 1 2 3 4 5; do
        run_config "$app" "$target" "$collector" default "$trial" || ((failed_retained += 1))
      done

      selected_xms=
      if [[ $xms_supported == supported ]]; then
        for value in "${xms_values[@]}"; do
          profile="initial-$value"
          if run_config "$app" "$target" "$collector" "$profile" 1 "$value" ''; then
            selected_xms=$value
            for trial in 2 3 4 5; do run_config "$app" "$target" "$collector" "$profile" "$trial" "$value" '' || ((failed_retained += 1)); done
            break
          else
            ((failed_retained += 1))
          fi
        done
      fi

      selected_xmx=
      selected_xmx_profile=
      if [[ $xmx_supported == supported ]]; then
        for value in "${xmx_desc[@]}"; do
          profile="maximum-$value"
          if run_config "$app" "$target" "$collector" "$profile" 1 '' "$value"; then
            selected_xmx=$value
            selected_xmx_profile=$profile
          else
            ((failed_retained += 1))
          fi
        done
      fi
      if [[ -n $selected_xmx ]]; then
        for trial in 2 3 4 5; do run_config "$app" "$target" "$collector" "$selected_xmx_profile" "$trial" '' "$selected_xmx" || ((failed_retained += 1)); done
      fi

      selected_combined_xms=
      selected_combined_xmx=
      selected_combined_profile=
      if [[ -n $selected_xms && -n $selected_xmx ]]; then
        xms_enabled=false
        for xms in "${xms_values[@]}"; do
          [[ $xms == "$selected_xms" ]] && xms_enabled=true
          [[ $xms_enabled == true ]] || continue
          xmx_enabled=false
          for xmx in "${xmx_asc[@]}"; do
            [[ $xmx == "$selected_xmx" ]] && xmx_enabled=true
            [[ $xmx_enabled == true ]] || continue
            profile="combined-${xms}-${xmx}"
            if run_config "$app" "$target" "$collector" "$profile" 1 "$xms" "$xmx"; then
              selected_combined_xms=$xms
              selected_combined_xmx=$xmx
              selected_combined_profile=$profile
              break 2
            else
              ((failed_retained += 1))
            fi
          done
        done
      fi
      if [[ -n $selected_combined_profile ]]; then
        for trial in 2 3 4 5; do
          run_config "$app" "$target" "$collector" "$selected_combined_profile" "$trial" "$selected_combined_xms" "$selected_combined_xmx" || ((failed_retained += 1))
        done
      fi

      if [[ -n $selected_xmx ]]; then
        profile="fixed-$selected_xmx"
        for trial in 1 2 3 4 5; do
          run_config "$app" "$target" "$collector" "$profile" "$trial" "$selected_xmx" "$selected_xmx" || ((failed_retained += 1))
        done
      fi

      boundary="$run_root/$app/$target/$collector/viability-boundary.txt"
      mkdir -p "${boundary%/*}"
      {
        echo "smallest_accepted_xms=${selected_xms:-none}"
        echo "smallest_viable_xmx=${selected_xmx:-none}"
        echo "combined_xms=${selected_combined_xms:-none}"
        echo "combined_xmx=${selected_combined_xmx:-none}"
        echo "fixed_heap=${selected_xmx:-none}"
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
