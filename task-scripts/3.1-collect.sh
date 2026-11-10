#!/usr/bin/env bash
set -euo pipefail

comparison_id=${1:-dispatch-validation-002}
if [[ ! $comparison_id =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
  echo "invalid comparison ID: $comparison_id" >&2
  exit 2
fi

virtual_output="reports/task-3.1/$comparison_id/virtual-dispatch-test"
enum_output="reports/task-3.1/$comparison_id/enum-dispatch-test"

if [[ -e $virtual_output || -e $enum_output ]]; then
  echo "comparison output already exists; choose a new comparison ID" >&2
  exit 2
fi

targets=(
  "c c-gcc"
  "c c-clang"
  "cpp cpp-gcc"
  "cpp cpp-clang"
  "java temurin-c2"
  "java graalvm-jit"
  "java graalvm-native"
)

echo "[$(date -u +%FT%TZ)] Starting Task 3.1 collection"
echo "  comparison_id=$comparison_id"
echo "  trials=5 targets=${#targets[@]} workloads=2 total_runs=70"
echo "  cpu=0 size=100000 seed=42 repeats=100 value=7 warmup=10 samples=30"

build_index=0
for entry in "${targets[@]}"; do
  read -r language target <<<"$entry"
  for workload in virtual-dispatch enum-dispatch; do
    ((build_index += 1))
    echo "[$(date -u +%FT%TZ)] BUILD $build_index/14 workload=$workload target=$target"
    CONTAINER_ENGINE=docker \
      "./$workload-test/$language/build.sh" --target "$target"
  done
done

run_index=0
for trial in 1 2 3 4 5; do
  for entry in "${targets[@]}"; do
    read -r language target <<<"$entry"
    for workload in virtual-dispatch enum-dispatch; do
      ((run_index += 1))
      if [[ $workload == virtual-dispatch ]]; then
        output=$virtual_output
      else
        output=$enum_output
      fi

      echo "[$(date -u +%FT%TZ)] RUN $run_index/70 trial=$trial/5 workload=$workload target=$target"
      run_started=$(date +%s)
      CONTAINER_ENGINE=docker BENCH_CPU=0 \
        "./$workload-test/$language/run.sh" \
        --target "$target" \
        --size 100000 --seed 42 --repeats 100 --value 7 \
        --warmup-samples 10 --samples 30 \
        --output "$output" \
        --run-id "$comparison_id" --trial "$trial" --config-id default

      source_log="$output/$target-$comparison_id.log"
      trial_log="$output/$target-$comparison_id-trial-$trial.log"
      if [[ ! -f $source_log ]]; then
        echo "expected run log was not produced: $source_log" >&2
        exit 1
      fi
      cp -- "$source_log" "$trial_log"

      run_finished=$(date +%s)
      echo "[$(date -u +%FT%TZ)] DONE $run_index/70 trial=$trial workload=$workload target=$target elapsed_seconds=$((run_finished - run_started))"
    done
  done
done

echo "[$(date -u +%FT%TZ)] Task 3.1 collection complete"
echo "  virtual_output=$virtual_output"
echo "  enum_output=$enum_output"
