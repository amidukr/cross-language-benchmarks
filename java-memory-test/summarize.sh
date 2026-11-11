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
summary="$root/summary.csv"
if [[ -e $summary ]]; then
  [[ $(wc -l <"$summary") -le 1 ]] || die "summary already contains data: $summary"
fi
summary_tmp=$(mktemp "$root/summary.csv.tmp.XXXXXX")
echo 'application,target,collector,heap_profile,trial,phase,metric,samples,min_bytes,p10_bytes,median_bytes,max_bytes,range_bytes,final_window_range_bytes' >"$summary_tmp"
tmp_dir=$(mktemp -d)
trap 'rm -rf -- "$tmp_dir"; rm -f -- "$summary_tmp"' EXIT
while IFS= read -r raw; do
  dir=${raw%/raw-samples.csv}
  manifest="$dir/manifest.txt"
  [[ $(sed -n 's/^status=//p' "$manifest" | tail -n 1) == success ]] || continue
  app=$(sed -n 's/^application=//p' "$manifest")
  target=$(sed -n 's/^target=//p' "$manifest")
  collector=$(sed -n 's/^collector=//p' "$manifest")
  profile=$(sed -n 's/^heap_profile=//p' "$manifest")
  trial=$(sed -n 's/^trial=//p' "$manifest")
  duration_mode=$(sed -n 's/^duration_mode=//p' "$manifest")
  if [[ $duration_mode == survey ]]; then
    phases=(survey-idle)
  else
    phases=(ready-idle post-exercise-idle)
  fi
  for phase in "${phases[@]}"; do
    for metric_column in rss_bytes:5 peak_rss_bytes:6 cgroup_memory_bytes:7; do
      metric=${metric_column%%:*}
      column=${metric_column#*:}
      values="$tmp_dir/values"
      awk -F, -v p="$phase" -v c="$column" 'NR>1 && $3==p{print $c}' "$raw" | sort -n >"$values"
      count=$(wc -l <"$values")
      ((count > 0)) || continue
      min=$(sed -n '1p' "$values")
      max=$(sed -n "${count}p" "$values")
      p10_index=$(((count + 9) / 10)); ((p10_index > 0)) || p10_index=1
      median_index=$(((count + 1) / 2))
      p10=$(sed -n "${p10_index}p" "$values")
      median=$(sed -n "${median_index}p" "$values")
      final_range=$(awk -F, -v p="$phase" -v c="$column" 'NR>1 && $3==p{v[n++]=$c} END{s=n-30;if(s<0)s=0;for(i=s;i<n;i++){if(min==""||v[i]<min)min=v[i];if(max==""||v[i]>max)max=v[i]} print max-min}' "$raw")
      printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
        "$app" "$target" "$collector" "$profile" "$trial" "$phase" "$metric" "$count" \
        "$min" "$p10" "$median" "$max" "$((max - min))" "$final_range" >>"$summary_tmp"
    done
  done
done < <(find "$root" -type f -name raw-samples.csv | sort)
mv -- "$summary_tmp" "$summary"
echo "summary=$summary"
