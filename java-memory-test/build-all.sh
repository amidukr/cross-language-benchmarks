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
for app in console swing spring-boot quarkus; do
  for target in temurin-c2 graalvm-jit; do
    ((total += 1))
    echo "BUILD $total application=$app target=$target collector=runtime-selected"
    "$memory_root/build.sh" --application "$app" --target "$target" \
      --log-dir "$output/$app/$target/default" || ((failed += 1))
  done
  for collector in default serial epsilon g1; do
    ((total += 1))
    echo "BUILD $total application=$app target=graalvm-native collector=$collector"
    "$memory_root/build.sh" --application "$app" --target graalvm-native \
      --collector "$collector" --log-dir "$output/$app/graalvm-native/$collector" || ((failed += 1))
  done
done
echo "builds=$total failures=$failed output=$output"
((failed == 0))
