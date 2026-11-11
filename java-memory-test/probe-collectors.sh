#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "$0")/scripts/common.sh"

output=
output_seen=false
while (($#)); do
  case "$1" in
    --output) (($# >= 2)) || die "missing value for $1"; [[ $output_seen == false ]] || die "duplicate $1"; output_seen=true; output=$2; shift 2 ;;
    --help) echo "Usage: $0 --output DIR"; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
done
[[ -n $output ]] || die "--output is required"
[[ ! -e $output ]] || die "probe output already exists: $output"
output=$(absolute_directory "$output")
select_engine
echo $'target\tcollector\tstatus\texit_status\tevidence' >"$output/support.tsv"
echo $'target\toption\tstatus\texit_status\tevidence' >"$output/heap-options.tsv"
probe_index=0
probe_total=24

for target in temurin-c2 graalvm-jit; do
  image=$(image_for console "$target" default)
  for collector in default serial parallel g1 zgc shenandoah epsilon; do
    dir="$output/$target/$collector"
    mkdir -p "$dir"
    case "$collector" in
      default) options=(-Xlog:gc+init=info) ;;
      serial) options=(-XX:+UseSerialGC -Xlog:gc+init=info) ;;
      parallel) options=(-XX:+UseParallelGC -Xlog:gc+init=info) ;;
      g1) options=(-XX:+UseG1GC -Xlog:gc+init=info) ;;
      zgc) options=(-XX:+UseZGC -Xlog:gc+init=info) ;;
      shenandoah) options=(-XX:+UseShenandoahGC -Xlog:gc+init=info) ;;
      epsilon) options=(-XX:+UnlockExperimentalVMOptions -XX:+UseEpsilonGC -Xlog:gc+init=info) ;;
    esac
    printf '%q ' "$container_engine" run --rm --entrypoint java "$image" "${options[@]}" -version >"$dir/command.txt"; echo >>"$dir/command.txt"
    ((probe_index += 1))
    echo "PROBE [$probe_index/$probe_total] target=$target collector=$collector"
    set +e
    "$container_engine" run --rm --memory 1g --cpus 1 --entrypoint java "$image" \
      "${options[@]}" -version >"$dir/stdout.txt" 2>"$dir/stderr.txt"
    status=$?
    set -e
    result=unsupported
    ((status != 0)) || result=supported
    {
      echo "target=$target"
      echo "collector=$collector"
      echo "image=$image"
      echo "container_engine=$container_engine"
      echo "container_engine_version=$container_engine_version"
      echo "exit_status=$status"
      echo "status=$result"
    } >"$dir/manifest.txt"
    printf '%s\t%s\t%s\t%s\t%s\n' "$target" "$collector" "$result" "$status" "$dir" >>"$output/support.tsv"
    echo "RESULT [$probe_index/$probe_total] target=$target collector=$collector status=$result exit=$status"
  done
done

for target in temurin-c2 graalvm-jit; do
  image=$(image_for console "$target" default)
  for option in xms xmx; do
    dir="$output/$target/heap-$option"
    mkdir -p "$dir"
    if [[ $option == xms ]]; then heap_option=-Xms1m; else heap_option=-Xmx4m; fi
    printf '%q ' "$container_engine" run --rm --memory 1g --cpus 1 --entrypoint java "$image" "$heap_option" -version >"$dir/command.txt"; echo >>"$dir/command.txt"
    ((probe_index += 1))
    echo "PROBE [$probe_index/$probe_total] target=$target option=$heap_option"
    set +e
    "$container_engine" run --rm --memory 1g --cpus 1 --entrypoint java "$image" \
      "$heap_option" -version >"$dir/stdout.txt" 2>"$dir/stderr.txt"
    status=$?
    set -e
    result=unsupported
    ((status != 0)) || result=supported
    printf 'target=%s\noption=%s\nrequested=%s\nexit_status=%s\nstatus=%s\n' \
      "$target" "$option" "$heap_option" "$status" "$result" >"$dir/manifest.txt"
    printf '%s\t%s\t%s\t%s\t%s\n' "$target" "$option" "$result" "$status" "$dir" >>"$output/heap-options.tsv"
    echo "RESULT [$probe_index/$probe_total] target=$target option=$heap_option status=$result exit=$status"
  done
done

command -v timeout >/dev/null 2>&1 || die "timeout is required to probe Native Image runtime heap options"
for option in xms xmx; do
  image=$(image_for console graalvm-native default)
  dir="$output/graalvm-native/heap-$option"
  mkdir -p "$dir"
  if [[ $option == xms ]]; then heap_option=-Xms1m; else heap_option=-Xmx4m; fi
  printf '%q ' timeout 5 "$container_engine" run --rm --memory 1g --cpus 1 --entrypoint /opt/apps/app "$image" "$heap_option" >"$dir/command.txt"; echo >>"$dir/command.txt"
  ((probe_index += 1))
  echo "PROBE [$probe_index/$probe_total] target=graalvm-native option=$heap_option (5-second timeout)"
  set +e
  timeout 5 "$container_engine" run --rm --memory 1g --cpus 1 --entrypoint /opt/apps/app "$image" \
    "$heap_option" >"$dir/stdout.txt" 2>"$dir/stderr.txt"
  status=$?
  set -e
  result=unsupported
  if [[ $status == 124 ]] && grep -q '^MEMORY_TEST_READY ' "$dir/stdout.txt"; then result=supported; fi
  printf 'target=graalvm-native\noption=%s\nrequested=%s\nexit_status=%s\nstatus=%s\n' \
    "$option" "$heap_option" "$status" "$result" >"$dir/manifest.txt"
  printf 'graalvm-native\t%s\t%s\t%s\t%s\n' "$option" "$result" "$status" "$dir" >>"$output/heap-options.tsv"
  echo "RESULT [$probe_index/$probe_total] target=graalvm-native option=$heap_option status=$result exit=$status"
done

for collector in default serial epsilon g1; do
  image=$(image_for console graalvm-native "$collector")
  dir="$output/graalvm-native/$collector"
  mkdir -p "$dir"
  printf '%q ' "$container_engine" image inspect "$image" >"$dir/command.txt"; echo >>"$dir/command.txt"
  ((probe_index += 1))
  echo "PROBE [$probe_index/$probe_total] target=graalvm-native collector=$collector (image check)"
  set +e
  "$container_engine" image inspect "$image" >"$dir/stdout.txt" 2>"$dir/stderr.txt"
  status=$?
  set -e
  result=unsupported
  ((status != 0)) || result=supported
  {
    echo "target=graalvm-native"
    echo "collector=$collector"
    echo "image=$image"
    echo "probe=successful native-image build artifact"
    echo "container_engine=$container_engine"
    echo "container_engine_version=$container_engine_version"
    echo "exit_status=$status"
    echo "status=$result"
  } >"$dir/manifest.txt"
  printf 'graalvm-native\t%s\t%s\t%s\t%s\n' "$collector" "$result" "$status" "$dir" >>"$output/support.tsv"
  echo "RESULT [$probe_index/$probe_total] target=graalvm-native collector=$collector status=$result exit=$status"
done
