#!/usr/bin/env bash
set -euo pipefail
language=${1:?language required}
shift
target= run_id= profile=assembly output= size=100000 seed=42 repeats=100 value=1 warmup=5 samples=20
while (($#)); do
    key=$1
    val=${2:-}
    case $key in --target) target=$val ;; --diagnostic-run-id) run_id=$val ;; --diagnostic-profile) profile=$val ;; --output) output=$val ;; --size) size=$val ;; --seed) seed=$val ;; --repeats) repeats=$val ;; --value) value=$val ;; --warmup-samples) warmup=$val ;; --samples) samples=$val ;; --help) exit 0 ;; *)
        echo "unknown option: $key" >&2
        exit 2
        ;;
    esac
    shift 2
done
for id in "$target" "$run_id" "$profile"; do [[ $id =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || exit 2; done
root=$(cd -- "$(dirname -- "$0")/.." && pwd)
repo=$(cd -- "$root/.." && pwd)
[[ -n $output ]] || output="$repo/reports/virtual-dispatch-test/assembly"
build="$root/.native/$target"
dir="$output/$target/native/$run_id"
mkdir -p "$dir"
args=(--size "$size" --seed "$seed" --repeats "$repeats" --value "$value" --warmup-samples "$warmup" --samples "$samples" --output /tmp/diagnostic --run-id "$run_id" --trial 1 --target "$target" --config-id diagnostic)
case $target in
    c-gcc | c-clang) cmd=(objdump -d -C "$build/virtual-dispatch-c") ;; cpp-gcc | cpp-clang) cmd=(objdump -d -C "$build/virtual-dispatch-cpp") ;;
    rust) cmd=(objdump -d -C "$build/release/virtual-dispatch") ;; go) cmd=(go tool objdump "$build/virtual-dispatch") ;;
    graalvm-native) cmd=(objdump -d -C "$build/virtual-dispatch") ;; dotnet-native) cmd=(objdump -d -C "$build/VirtualDispatch") ;;
    temurin-c2 | graalvm-jit) cmd=(java -XX:+UnlockDiagnosticVMOptions -XX:+PrintCompilation -XX:+PrintAssembly -cp "$build" VirtualDispatch "${args[@]}") ;;
    coreclr) cmd=(env 'DOTNET_JitDisasm=Program:Run' dotnet "$build/VirtualDispatch.dll" "${args[@]}") ;;
    node-v8) cmd=(node --print-opt-code --trace-opt --trace-deopt "$build/virtual-dispatch.js" "${args[@]}") ;;
    cpython) cmd=(python3 -c "import dis,runpy; n=runpy.run_path('$build/virtual_dispatch.py'); dis.dis(n['run'],adaptive=True,show_caches=True); dis.dis(n['AddOperation'].process,adaptive=True,show_caches=True); dis.dis(n['MulOperation'].process,adaptive=True,show_caches=True)") ;;
    *) exit 2 ;; esac
printf '%q ' "${cmd[@]}" >"$dir/command.txt"
echo >>"$dir/command.txt"
set +e
"${cmd[@]}" >"$dir/raw.txt" 2>"$dir/stderr.txt"
status=$?
set -e
state=success
reason=
if ((status)); then
    state=failed
    reason="capture command exited $status"
elif [[ ! -s $dir/raw.txt ]]; then
    state=incomplete
    reason="no raw output"
    status=1
fi
{
    echo "target=$target"
    echo "diagnostic_profile=$profile"
    echo "diagnostic_run_id=$run_id"
    echo execution_mode=native
    echo "artifact=$build"
    echo "size=$size"
    echo "seed=$seed"
    echo "repeats=$repeats"
    echo "value=$value"
    echo "capture_status=$state"
    echo "exit_status=$status"
    echo "reason=$reason"
} >"$dir/manifest.txt"
exit "$status"
