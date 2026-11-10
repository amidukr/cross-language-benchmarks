#!/usr/bin/env bash
set -euo pipefail
language=${1:?language is required}
shift
target= run_id= profile=assembly output= size=100000 seed=42 repeats=100 value=7 warmup=10 samples=30
while (($#)); do
    key=$1
    (($# >= 2)) || {
        [[ $key == --help ]] && {
            echo "usage: capture_assembly.sh LANGUAGE --target ID --diagnostic-run-id ID [options]"
            exit 0
        }
        echo "missing value for $key" >&2
        exit 2
    }
    val=$2
    case $key in --target) target=$val ;; --diagnostic-run-id) run_id=$val ;; --diagnostic-profile) profile=$val ;; --output) output=$val ;; --size) size=$val ;; --seed) seed=$val ;; --repeats) repeats=$val ;; --value) value=$val ;; --warmup-samples) warmup=$val ;; --samples) samples=$val ;; *)
        echo "unknown option: $key" >&2
        exit 2
        ;;
    esac
    shift 2
done
for id in "$target" "$run_id" "$profile"; do [[ $id =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || {
    echo "missing or invalid identifier" >&2
    exit 2
}; done
engine=${CONTAINER_ENGINE:-docker}
case $engine in docker | podman) ;; *)
    echo "unsupported container engine: $engine" >&2
    exit 2
    ;;
esac
command -v "$engine" >/dev/null || exit 127
root=$(cd -- "$(dirname -- "$0")/.." && pwd)
repo=$(cd -- "$root/.." && pwd)
[[ -n $output ]] || output="$repo/reports/enum-dispatch-test/assembly"
dir="$output/$target/$engine/$run_id"
mkdir -p "$dir"
tag="enum-dispatch-$target-$profile:latest"
args=(--size "$size" --seed "$seed" --repeats "$repeats" --value "$value" --warmup-samples "$warmup" --samples "$samples" --output /tmp/diagnostic --run-id "$run_id" --trial 1 --target "$target" --config-id diagnostic)
case $target:$profile in
    c-gcc:vectorization)
        cmd=("$engine" run --rm --entrypoint sh "$tag" -c '
set -eu
echo "===== GCC vectorization remarks ====="
cat /src/vectorization.txt
echo
echo "===== linked executable disassembly ====="
objdump -d -C /src/build-vectorization/enum-dispatch-c
')
        ;;
    cpp-gcc:vectorization)
        cmd=("$engine" run --rm --entrypoint sh "$tag" -c '
set -eu
echo "===== GCC vectorization remarks ====="
cat /src/vectorization.txt
echo
echo "===== linked executable disassembly ====="
objdump -d -C /src/build-vectorization/enum-dispatch-cpp
')
        ;;
    c-clang:vectorization)
        cmd=("$engine" run --rm --entrypoint sh "$tag" -c '
set -eu
echo "===== Clang vectorization remarks ====="
cat /src/vectorization-build.txt
echo
echo "===== Clang optimization record ====="
cat /src/vectorization.yaml
echo
echo "===== linked executable disassembly ====="
llvm-objdump -d -C /src/build-vectorization/enum-dispatch-c
')
        ;;
    cpp-clang:vectorization)
        cmd=("$engine" run --rm --entrypoint sh "$tag" -c '
set -eu
echo "===== Clang vectorization remarks ====="
cat /src/vectorization-build.txt
echo
echo "===== Clang optimization record ====="
cat /src/vectorization.yaml
echo
echo "===== linked executable disassembly ====="
llvm-objdump -d -C /src/build-vectorization/enum-dispatch-cpp
')
        ;;
    c-gcc:* | c-clang:* | cpp-gcc:* | cpp-clang:*)
        case $target in
    c-gcc) cmd=("$engine" run --rm --entrypoint objdump "$tag" -d -C /src/build/enum-dispatch-c) ;;
    c-clang) cmd=("$engine" run --rm --entrypoint llvm-objdump "$tag" -d -C /src/build/enum-dispatch-c) ;;
    cpp-gcc) cmd=("$engine" run --rm --entrypoint objdump "$tag" -d -C /src/build/enum-dispatch-cpp) ;;
    cpp-clang) cmd=("$engine" run --rm --entrypoint llvm-objdump "$tag" -d -C /src/build/enum-dispatch-cpp) ;;
        esac
        ;;
    rust:*) cmd=("$engine" run --rm --entrypoint objdump "$tag" -d -C /src/target/release/enum-dispatch) ;;
    go:*) cmd=("$engine" run --rm --entrypoint go "$tag" tool objdump /enum-dispatch) ;;
    graalvm-native:*)
        cmd=("$engine" run --rm --entrypoint sh "$tag" -c '
binary=$1
ranges=/tmp/enum-dispatch-ranges.txt
nm -n -C --defined-only "$binary" | awk '\''
  pending && $1 != start {
    print start, $1, name
    pending = 0
  }
  /EnumDispatch.*run/ {
    start = $1
    name = $0
    sub(/^[^ ]+ [^ ]+ /, "", name)
    pending = 1
  }
'\'' > "$ranges"
if [ ! -s "$ranges" ]; then
  echo "no retained EnumDispatch hot-method symbols found" >&2
  exit 3
fi
while read -r start stop name; do
  echo
  echo "===== $name [$start,$stop) ====="
  objdump -d -C --start-address="0x$start" --stop-address="0x$stop" "$binary"
done < "$ranges"
' sh /build/enum-dispatch)
        ;;
    dotnet-native:*) cmd=("$engine" run --rm --entrypoint objdump "$tag" -d -C /app/EnumDispatch) ;;
    temurin-c2:* | graalvm-jit:*) cmd=("$engine" run --rm --entrypoint java "$tag" -XX:+UnlockDiagnosticVMOptions -XX:+PrintCompilation -XX:+PrintAssembly -cp /build EnumDispatch "${args[@]}") ;;
    coreclr:*) cmd=("$engine" run --rm -e 'DOTNET_JitDisasm=Program:Run' --entrypoint dotnet "$tag" /app/EnumDispatch.dll "${args[@]}") ;;
    node-v8:*) cmd=("$engine" run --rm --entrypoint node "$tag" --print-opt-code --trace-opt --trace-deopt /benchmark/enum-dispatch.js "${args[@]}") ;;
    cpython:*) cmd=("$engine" run --rm --entrypoint python3 "$tag" -c 'import dis,runpy; n=runpy.run_path("/benchmark/enum_dispatch.py"); dis.dis(n["run"],adaptive=True,show_caches=True)') ;;
    *)
        echo "unsupported target" >&2
        exit 2
        ;;
esac
printf '%q ' "${cmd[@]}" >"$dir/command.txt"
echo >>"$dir/command.txt"
set +e
"${cmd[@]}" >"$dir/raw.txt" 2>"$dir/stderr.txt"
status=$?
set -e
capture_status=success
reason=
if ((status)); then
    capture_status=failed
    reason="capture command exited $status"
elif [[ ! -s $dir/raw.txt ]]; then
    capture_status=incomplete
    reason="capture produced no raw output"
    status=1
elif [[ $target == graalvm-native ]] && ! grep -q 'EnumDispatch.*run' "$dir/raw.txt"; then
    capture_status=incomplete
    reason="capture did not identify the EnumDispatch.run hot region"
    status=1
fi
{
    echo "target=$target"
    echo "diagnostic_profile=$profile"
    echo "diagnostic_run_id=$run_id"
    echo "execution_mode=$engine"
    echo "container_engine=$engine"
    echo "container_engine_version=$($engine --version 2>&1 | tail -1)"
    echo "image=$tag"
    echo "size=$size"
    echo "seed=$seed"
    echo "repeats=$repeats"
    echo "value=$value"
    echo "warmup_samples=$warmup"
    echo "samples=$samples"
    echo "capture_status=$capture_status"
    echo "exit_status=$status"
    echo "reason=$reason"
} >"$dir/manifest.txt"
exit "$status"
