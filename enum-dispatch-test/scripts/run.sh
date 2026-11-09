#!/bin/sh
set -eu

language=${1:?language is required}
shift
target=
output=
run_id=
forward=
while [ "$#" -gt 0 ]; do
    option=$1
    [ "$#" -ge 2 ] || { echo "missing value for $option" >&2; exit 2; }
    value=$2
    case "$option" in
        --target) [ -z "$target" ] || { echo "duplicate --target" >&2; exit 2; }; target=$value ;;
        --output) [ -z "$output" ] || { echo "duplicate --output" >&2; exit 2; }; output=$value ;;
        --run-id) [ -z "$run_id" ] || { echo "duplicate --run-id" >&2; exit 2; }; run_id=$value ;;
    esac
    forward="$forward
$option
$value"
    shift 2
done
[ -n "$target" ] || { echo "--target is required" >&2; exit 2; }
[ -n "$output" ] || { echo "--output is required" >&2; exit 2; }
case "$language:$target" in
    c:c-gcc|c:c-clang|cpp:cpp-gcc|cpp:cpp-clang|java:temurin-c2|java:graalvm-jit|java:graalvm-native|rust:rust|go:go|python:cpython|csharp:coreclr|csharp:dotnet-native|javascript:node-v8) ;;
    *) echo "target '$target' is invalid for $language" >&2; exit 2 ;;
esac

if [ -z "$run_id" ]; then
    run_id="run-$(date -u +%Y%m%dT%H%M%SZ)-$$"
    forward="$forward
--run-id
$run_id"
fi
mkdir -p "$output"
output=$(CDPATH= cd -- "$output" && pwd)
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
container_engine=${CONTAINER_ENGINE:-docker}
case "$container_engine" in
    docker|podman) ;;
    *) echo "unsupported container engine: $container_engine (expected docker or podman)" >&2; exit 2 ;;
esac
command -v "$container_engine" >/dev/null 2>&1 || {
    echo "container engine not found: $container_engine" >&2
    exit 127
}
container_engine_version=$("$container_engine" --version 2>&1)
case "$container_engine:$container_engine_version" in
    podman:*|*:*[Pp]odman*) container_runtime=podman ;;
    *) container_runtime=docker ;;
esac
host_uid=$(id -u)
host_gid=$(id -g)
cpu=${BENCH_CPU:-0}
if [ "$container_runtime" = podman ]; then
    command -v taskset >/dev/null 2>&1 || {
        echo "required command not found: taskset" >&2
        exit 127
    }
    cpu_control=taskset
else
    cpu_control=container-cpuset
fi
environment="$(uname -srmo); $(sed -n 's/^model name[[:space:]]*: //p' /proc/cpuinfo | sed -n '1p')"
args=
old_ifs=$IFS
IFS='
'
set -f
set -- $forward
IFS=$old_ifs
while [ "$#" -gt 0 ]; do
    if [ "$1" = "--output" ]; then
        shift 2
        args="$args
--output
/output"
    else
        args="$args
$1
$2"
        shift 2
    fi
done
IFS='
'
set -- $args
IFS=$old_ifs

log="$output/$target-$run_id.log"
{
    echo "run_id=$run_id"
    echo "target=$target"
    echo "execution_mode=docker"
    echo "container_engine=$container_engine"
    echo "container_engine_version=$container_engine_version"
    echo "container_runtime=$container_runtime"
    echo "image=enum-dispatch-$target:latest"
    echo "cpu=$cpu"
    echo "cpu_control=$cpu_control"
    echo "cpu_limit=one logical CPU"
    echo "memory_limit=none"
    echo "architecture=$(uname -m)"
    echo "environment=$environment"
    echo "started_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} >"$log"

cd "$root"
set +e
if [ "$container_runtime" = podman ]; then
    taskset -c "$cpu" "$container_engine" run --rm \
        --userns keep-id \
        --volume "$output:/output" \
        --env "BENCH_ENVIRONMENT=$environment" \
        "enum-dispatch-$target:latest" "$@" 2>>"$log"
else
    "$container_engine" run --rm --cpuset-cpus "$cpu" \
        --user "$host_uid:$host_gid" \
        --volume "$output:/output" \
        --env "BENCH_ENVIRONMENT=$environment" \
        "enum-dispatch-$target:latest" "$@" 2>>"$log"
fi
status=$?
set -e
echo "exit_status=$status" >>"$log"
exit "$status"
