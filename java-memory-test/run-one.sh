#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "$0")/scripts/common.sh"

app=
target=
collector=
heap_profile=
heap_initial=
heap_max=
run_id=
trial=
probe_only=false
output_root="$repo_root/reports/java-memory-test"
declare -A seen=()
while (($#)); do
  option=$1
  case "$1" in
    --application|--target|--collector|--heap-profile|--xms|--xmx|--run-id|--trial|--output)
      (($# >= 2)) || die "missing value for $1"
      [[ -z ${seen[$option]:-} ]] || die "duplicate $option"
      seen[$option]=true
      value=$2
      case "$option" in
        --application) app=$value ;;
        --target) target=$value ;;
        --collector) collector=$value ;;
        --heap-profile) heap_profile=$value ;;
        --xms) heap_initial=$value ;;
        --xmx) heap_max=$value ;;
        --run-id) run_id=$value ;;
        --trial) trial=$value ;;
        --output) output_root=$value ;;
      esac
      shift 2 ;;
    --probe-only) probe_only=true; shift ;;
    --help)
      echo "Usage: $0 --application ID --target ID --collector ID --heap-profile ID --run-id ID --trial N [--xms SIZE] [--xmx SIZE] [--probe-only] [--output DIR]"
      exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
done
[[ -n $app && -n $target && -n $collector && -n $heap_profile && -n $run_id && -n $trial ]] || die "missing required option"
require_application "$app"
require_target "$target"
require_collector "$collector"
require_id heap-profile "$heap_profile"
require_id run-id "$run_id"
[[ $trial =~ ^[1-9][0-9]*$ ]] || die "invalid trial: $trial"
require_heap_value xms "$heap_initial"
require_heap_value xmx "$heap_max"
if [[ $target == graalvm-native ]]; then
  case "$collector" in default|serial|epsilon|g1) ;; *) die "collector $collector is not a Native Image build collector" ;; esac
fi

select_engine
output_root=$(absolute_directory "$output_root")
trial_dir="$output_root/$run_id/$app/$target/$collector/$heap_profile/$trial"
[[ ! -e $trial_dir ]] || die "trial output already exists: $trial_dir"
mkdir -p "$trial_dir"
trial_dir=$(cd -- "$trial_dir" && pwd)
image=$(image_for "$app" "$target" "$collector")
image_id=$("$container_engine" image inspect --format '{{.Id}}' "$image" 2>/dev/null) || {
  echo "required image not found: $image" >&2
  printf 'status=failed\nfailure_reason=image-not-found\nimage=%s\n' "$image" >"$trial_dir/host-manifest.txt"
  printf 'status=failed\nfailure_reason=image-not-found\napplication=%s\ntarget=%s\ncollector=%s\nheap_profile=%s\ntrial=%s\n' \
    "$app" "$target" "$collector" "$heap_profile" "$trial" >"$trial_dir/manifest.txt"
  exit 1
}
cpu=${BENCH_CPU:-0}
host_environment="$(uname -srmo); $(sed -n 's/^model name[[:space:]]*: //p' /proc/cpuinfo | sed -n '1p')"
env_args=(
  --env "MEMORY_COLLECTOR=$collector"
  --env "MEMORY_HEAP_PROFILE=$heap_profile"
  --env "MEMORY_HEAP_INITIAL=$heap_initial"
  --env "MEMORY_HEAP_MAX=$heap_max"
  --env "MEMORY_RUN_ID=$run_id"
  --env "MEMORY_TRIAL=$trial"
  --env "MEMORY_PROBE_ONLY=$probe_only"
  --env "MEMORY_IMAGE_REF=$image"
  --env "MEMORY_IMAGE_ID=$image_id"
  --env "MEMORY_CONTAINER_ENGINE=$container_runtime"
  --env "MEMORY_CONTAINER_ENGINE_VERSION=$container_engine_version"
  --env "MEMORY_HOST_ENVIRONMENT=$host_environment"
)
run_args=(run --rm --memory 1g --pids-limit 512 --volume "$trial_dir:/output" "${env_args[@]}" "$image")
if [[ $container_runtime == podman ]]; then
  command -v taskset >/dev/null 2>&1 || die "taskset is required for rootless Podman CPU affinity"
  run_command=(taskset -c "$cpu" "$container_engine" "${run_args[@]:0:2}" --userns keep-id "${run_args[@]:2}")
else
  run_command=("$container_engine" "${run_args[@]:0:2}" --cpuset-cpus "$cpu" --user "$(id -u):$(id -g)" "${run_args[@]:2}")
fi
printf '%q ' "${run_command[@]}" >"$trial_dir/host-command.txt"
printf '\n' >>"$trial_dir/host-command.txt"
set +e
"${run_command[@]}" >"$trial_dir/container.stdout" 2>"$trial_dir/container.stderr"
status=$?
set -e
{
  echo "status=$([[ $status == 0 ]] && echo success || echo failed)"
  echo "exit_status=$status"
  echo "container_runtime=$container_runtime"
  echo "container_engine_version=$container_engine_version"
  echo "cpu=$cpu"
  echo "memory_limit_bytes=1073741824"
  echo "image=$image"
  echo "image_id=$image_id"
} >"$trial_dir/host-manifest.txt"
if [[ ! -e $trial_dir/manifest.txt ]]; then
  printf 'status=failed\nfailure_reason=container-exit-%s\napplication=%s\ntarget=%s\ncollector=%s\nheap_profile=%s\ntrial=%s\n' \
    "$status" "$app" "$target" "$collector" "$heap_profile" "$trial" >"$trial_dir/manifest.txt"
fi
exit "$status"
