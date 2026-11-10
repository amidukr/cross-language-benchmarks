#!/usr/bin/env bash
set -uo pipefail
source "$(dirname -- "$0")/scripts/common.sh"

if (($# > 1)); then die "Usage: $0 [BUILD_ID]"; fi
if [[ ${1:-} == --help ]]; then echo "Usage: $0 [BUILD_ID]"; exit 0; fi
build_id=${1:-build-$(date -u +%Y%m%dT%H%M%SZ)}
require_id build-id "$build_id"
output="$repo_root/reports/java-memory-test/build/$build_id"
[[ ! -e $output ]] || die "build output already exists: $output"
mkdir -p "$output"
failed=0
total=0
started_at=$(date +%s)
run_build() {
  local app=$1 target=$2 collector=$3 log_dir=$4 image_started image_finished status
  ((total += 1))
  image_started=$(date +%s)
  echo "[$(date -u +%FT%TZ)] BUILD $total/24 START application=$app target=$target collector=$collector"
  if "$memory_root/build.sh" --application "$app" --target "$target" \
      --collector "$collector" --log-dir "$log_dir" --stream; then
    status=0
  else
    status=$?
    ((failed += 1))
  fi
  image_finished=$(date +%s)
  echo "[$(date -u +%FT%TZ)] BUILD $total/24 DONE application=$app target=$target collector=$collector status=$status elapsed_seconds=$((image_finished - image_started)) log=$log_dir"
}
for app in console swing spring-boot quarkus; do
  for target in temurin-c2 graalvm-jit; do
    run_build "$app" "$target" default "$output/$app/$target/default"
  done
  for collector in default serial epsilon g1; do
    run_build "$app" graalvm-native "$collector" "$output/$app/graalvm-native/$collector"
  done
done
finished_at=$(date +%s)
echo "[$(date -u +%FT%TZ)] BUILDS_DONE builds=$total failures=$failed elapsed_seconds=$((finished_at - started_at)) output=$output"
((failed == 0))
