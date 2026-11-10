#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "$0")/scripts/common.sh"

app=
target=
collector=default
log_dir=
app_seen=false
target_seen=false
collector_seen=false
log_dir_seen=false
while (($#)); do
  case "$1" in
    --application) (($# >= 2)) || die "missing value for $1"; [[ $app_seen == false ]] || die "duplicate $1"; app_seen=true; app=$2; shift 2 ;;
    --target) (($# >= 2)) || die "missing value for $1"; [[ $target_seen == false ]] || die "duplicate $1"; target_seen=true; target=$2; shift 2 ;;
    --collector) (($# >= 2)) || die "missing value for $1"; [[ $collector_seen == false ]] || die "duplicate $1"; collector_seen=true; collector=$2; shift 2 ;;
    --log-dir) (($# >= 2)) || die "missing value for $1"; [[ $log_dir_seen == false ]] || die "duplicate $1"; log_dir_seen=true; log_dir=$2; shift 2 ;;
    --help) echo "Usage: $0 --application ID --target ID [--collector ID] [--log-dir DIR]"; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
done
[[ -n $app && -n $target ]] || die "--application and --target are required"
require_application "$app"
require_target "$target"
require_collector "$collector"
if [[ $target != graalvm-native && $collector != default ]]; then
  die "JVM images are collector-independent; build with --collector default"
fi
if [[ $target == graalvm-native ]]; then
  case "$collector" in default|serial|epsilon|g1) ;; *) die "invalid Native Image collector: $collector" ;; esac
fi
select_engine
image=$(image_for "$app" "$target" "$collector")
args=(build --pull --build-arg "APP=$app" --build-arg "TARGET=$target" --build-arg "COLLECTOR=$collector" --file "$memory_root/Dockerfile" --tag "$image" "$memory_root")
if [[ -n $log_dir ]]; then
  mkdir -p "$log_dir"
  printf '%q ' "$container_engine" "${args[@]}" >"$log_dir/command.txt"
  printf '\n' >>"$log_dir/command.txt"
  set +e
  "$container_engine" "${args[@]}" >"$log_dir/stdout.txt" 2>"$log_dir/stderr.txt"
  status=$?
  set -e
  {
    echo "application=$app"
    echo "target=$target"
    echo "collector=$collector"
    echo "container_engine=$container_engine"
    echo "container_engine_version=$container_engine_version"
    echo "image=$image"
    echo "exit_status=$status"
    if ((status == 0)); then echo "status=success"; else echo "status=unsupported-or-failed"; fi
  } >"$log_dir/manifest.txt"
  exit "$status"
fi
exec "$container_engine" "${args[@]}"
