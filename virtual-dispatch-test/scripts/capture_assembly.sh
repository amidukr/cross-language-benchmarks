#!/usr/bin/env bash
set -euo pipefail
language=${1:?language is required}
shift
target= run_id= profile=assembly output= size=100000 seed=42 repeats=100 value=1 warmup=5 samples=20
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
[[ -n $output ]] || output="$repo/reports/virtual-dispatch-test/assembly"
dir="$output/$target/$engine/$run_id"
mkdir -p "$dir"
tag="virtual-dispatch-$target-$profile:latest"
args=(--size "$size" --seed "$seed" --repeats "$repeats" --value "$value" --warmup-samples "$warmup" --samples "$samples" --output /tmp/diagnostic --run-id "$run_id" --trial 1 --target "$target" --config-id diagnostic)
case $target in
    c-gcc) cmd=("$engine" run --rm --entrypoint objdump "$tag" -d -C /src/build/virtual-dispatch-c) ;;
    c-clang) cmd=("$engine" run --rm --entrypoint llvm-objdump "$tag" -d -C /src/build/virtual-dispatch-c) ;;
    cpp-gcc) cmd=("$engine" run --rm --entrypoint objdump "$tag" -d -C /src/build/virtual-dispatch-cpp) ;;
    cpp-clang) cmd=("$engine" run --rm --entrypoint llvm-objdump "$tag" -d -C /src/build/virtual-dispatch-cpp) ;;
    rust) cmd=("$engine" run --rm --entrypoint objdump "$tag" -d -C /src/target/release/virtual-dispatch) ;;
    go) cmd=("$engine" run --rm --entrypoint go "$tag" tool objdump /virtual-dispatch) ;;
    graalvm-native) cmd=("$engine" run --rm --entrypoint objdump "$tag" -d -C /build/virtual-dispatch) ;;
    dotnet-native) cmd=("$engine" run --rm --entrypoint objdump "$tag" -d -C /app/VirtualDispatch) ;;
    temurin-c2 | graalvm-jit) cmd=("$engine" run --rm --entrypoint java "$tag" -XX:+UnlockDiagnosticVMOptions -XX:+PrintCompilation -XX:+PrintAssembly -cp /build VirtualDispatch "${args[@]}") ;;
    coreclr) cmd=("$engine" run --rm -e 'DOTNET_JitDisasm=VirtualDispatch:*' --entrypoint dotnet "$tag" /app/VirtualDispatch.dll "${args[@]}") ;;
    node-v8) cmd=("$engine" run --rm --entrypoint node "$tag" --print-opt-code --trace-opt --trace-deopt /benchmark/virtual-dispatch.js "${args[@]}") ;;
    cpython) cmd=("$engine" run --rm --entrypoint python3 "$tag" -c 'import dis,runpy; n=runpy.run_path("/benchmark/virtual_dispatch.py"); dis.dis(n["run"],adaptive=True,show_caches=True); dis.dis(n["AddOperation"].process,adaptive=True,show_caches=True); dis.dis(n["MulOperation"].process,adaptive=True,show_caches=True)') ;;
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
