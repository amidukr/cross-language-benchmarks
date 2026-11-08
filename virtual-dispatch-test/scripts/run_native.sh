#!/usr/bin/env bash
set -euo pipefail

language=${1:?language is required}
shift
target=
output=
run_id=
declare -a forwarded=()
while (($# > 0)); do
    option=$1
    (($# >= 2)) || { echo "missing value for $option" >&2; exit 2; }
    value=$2
    case $option in
        --target) [[ -z $target ]] || { echo "duplicate --target" >&2; exit 2; }; target=$value ;;
        --output) [[ -z $output ]] || { echo "duplicate --output" >&2; exit 2; }; output=$value ;;
        --run-id) [[ -z $run_id ]] || { echo "duplicate --run-id" >&2; exit 2; }; run_id=$value ;;
    esac
    forwarded+=("$option" "$value")
    shift 2
done
[[ -n $target ]] || { echo "--target is required" >&2; exit 2; }
[[ -n $output ]] || { echo "--output is required" >&2; exit 2; }
case "$language:$target" in
    c:c-gcc|c:c-clang|cpp:cpp-gcc|cpp:cpp-clang|java:temurin-c2|java:graalvm-jit|java:graalvm-native|rust:rust|go:go|python:cpython|csharp:coreclr|csharp:dotnet-native|javascript:node-v8) ;;
    *) echo "target '$target' is invalid for $language" >&2; exit 2 ;;
esac
if [[ -z $run_id ]]; then
    run_id="run-$(date -u +%Y%m%dT%H%M%SZ)-$$"
    forwarded+=(--run-id "$run_id")
fi

root=$(cd -- "$(dirname -- "$0")/.." && pwd)
build_dir="$root/.native/$target"
[[ -d $build_dir ]] || {
    echo "native target '$target' has not been built; run build_native.sh first" >&2
    exit 2
}
mkdir -p "$output"
output=$(cd -- "$output" && pwd)
for ((i = 0; i < ${#forwarded[@]}; i += 2)); do
    [[ ${forwarded[i]} != --output ]] || forwarded[i + 1]=$output
done

require_command() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "required command not found: $1" >&2
        exit 127
    }
}
require_file() {
    [[ -f $1 ]] || {
        echo "native artifact not found: $1; run build_native.sh first" >&2
        exit 2
    }
}

declare -a command
case $target in
    c-gcc|c-clang)
        require_file "$build_dir/virtual-dispatch-c"
        command=("$build_dir/virtual-dispatch-c")
        ;;
    cpp-gcc|cpp-clang)
        require_file "$build_dir/virtual-dispatch-cpp"
        command=("$build_dir/virtual-dispatch-cpp")
        ;;
    temurin-c2|graalvm-jit)
        require_command java
        require_file "$build_dir/VirtualDispatch.class"
        java_version=$(java -version 2>&1)
        [[ $target != graalvm-jit || $java_version == *GraalVM* ]] || { echo "installed java is not GraalVM" >&2; exit 2; }
        command=(java -cp "$build_dir" VirtualDispatch)
        ;;
    graalvm-native)
        require_file "$build_dir/virtual-dispatch"
        command=("$build_dir/virtual-dispatch")
        ;;
    rust)
        require_file "$build_dir/release/virtual-dispatch"
        command=("$build_dir/release/virtual-dispatch")
        ;;
    go)
        require_file "$build_dir/virtual-dispatch"
        command=("$build_dir/virtual-dispatch")
        ;;
    cpython)
        require_command python3
        require_file "$build_dir/virtual_dispatch.py"
        command=(python3 "$build_dir/virtual_dispatch.py")
        ;;
    coreclr)
        require_command dotnet
        require_file "$build_dir/VirtualDispatch.dll"
        [[ $(dotnet --version) == 10.* ]] || { echo "installed dotnet runtime is not version 10" >&2; exit 2; }
        command=(dotnet "$build_dir/VirtualDispatch.dll")
        ;;
    dotnet-native)
        require_file "$build_dir/VirtualDispatch"
        command=("$build_dir/VirtualDispatch")
        ;;
    node-v8)
        require_command node
        require_file "$build_dir/virtual-dispatch.js"
        [[ $(node --version) == v26.* ]] || { echo "installed Node.js is not version 26" >&2; exit 2; }
        command=(node "$build_dir/virtual-dispatch.js")
        ;;
esac

require_command taskset
cpu=${BENCH_CPU:-0}
environment="$(uname -srmo); $(sed -n 's/^model name[[:space:]]*: //p' /proc/cpuinfo | sed -n '1p')"
log="$output/$target-$run_id.log"
{
    echo "run_id=$run_id"
    echo "target=$target"
    echo "execution_mode=native"
    echo "build_directory=$build_dir"
    echo "cpu=$cpu"
    echo "cpu_limit=one logical CPU"
    echo "memory_limit=none"
    echo "architecture=$(uname -m)"
    echo "environment=$environment"
    if [[ -f $build_dir/build_toolchain.txt ]]; then
        echo "build_toolchain=$(<"$build_dir/build_toolchain.txt")"
    fi
    echo "started_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} >"$log"

set +e
BENCH_ENVIRONMENT=$environment taskset -c "$cpu" \
    "${command[@]}" "${forwarded[@]}" 2>>"$log"
status=$?
set -e
echo "exit_status=$status" >>"$log"
exit "$status"
