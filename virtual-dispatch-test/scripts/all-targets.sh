#!/usr/bin/env bash
set -euo pipefail

mode=${1:?mode is required}
shift

workload_root=$(cd -- "$(dirname -- "$0")/.." && pwd)
repository_root=$(cd -- "$workload_root/.." && pwd)
languages=(c c cpp cpp java java java rust go python csharp csharp javascript)
targets=(c-gcc c-clang cpp-gcc cpp-clang temurin-c2 graalvm-jit graalvm-native rust go cpython coreclr dotnet-native node-v8)

usage() {
    case $mode in
        build-docker|build-native)
            echo "usage: $(basename "$0") $mode" >&2
            ;;
        run-docker|run-native)
            echo "usage: $(basename "$0") $mode [benchmark runner options except --target]" >&2
            ;;
    esac
}

summarize() {
    local label=$1
    shift
    if (($# == 0)); then
        printf '%s: none\n' "$label" >&2
    else
        printf '%s (%d): %s\n' "$label" "$#" "$*" >&2
    fi
}

reason_from() {
    local file=$1
    local reason
    reason=$(sed -n '/[^[:space:]]/ { s/^[[:space:]]*//; p; q; }' "$file")
    printf '%s' "${reason:-command exited without an error message}"
}

is_native_skip() {
    local status=$1
    local file=$2
    ((status == 127)) ||
        grep -Eqi 'required command not found|not (version|GraalVM)|release version .* not supported|has not been built|native artifact not found|no compatible framework|no usable version|SDK .* not found' "$file"
}

run_docker_batch() {
    local action=$1
    shift
    local -a succeeded=() failed=()
    local index status
    for index in "${!targets[@]}"; do
        echo "$action ${targets[index]}" >&2
        set +e
        "$workload_root/${languages[index]}/$action.sh" --target "${targets[index]}" "$@"
        status=$?
        set -e
        if ((status == 0)); then
            succeeded+=("${targets[index]}")
        else
            failed+=("${targets[index]} (exit $status)")
        fi
    done
    summarize succeeded "${succeeded[@]}"
    summarize failed "${failed[@]}"
    ((${#failed[@]} == 0))
}

run_native_batch() {
    local action=$1
    shift
    local -a succeeded=() skipped=() failed=()
    local index status reason capture
    for index in "${!targets[@]}"; do
        echo "$action ${targets[index]}" >&2
        capture=$(mktemp)
        set +e
        "$workload_root/${languages[index]}/${action}_native.sh" \
            --target "${targets[index]}" "$@" 2>"$capture"
        status=$?
        set -e
        sed -n '1,$p' "$capture" >&2
        if ((status == 0)); then
            succeeded+=("${targets[index]}")
        else
            reason=$(reason_from "$capture")
            if is_native_skip "$status" "$capture"; then
                skipped+=("${targets[index]}: $reason")
            else
                failed+=("${targets[index]}: $reason")
            fi
        fi
        rm -f -- "$capture"
    done
    summarize succeeded "${succeeded[@]}"
    summarize skipped "${skipped[@]}"
    summarize failed "${failed[@]}"
    ((${#failed[@]} == 0 && ${#succeeded[@]} > 0))
}

prepare_run_arguments() {
    forwarded=()
    local output= run_id= option value
    while (($# > 0)); do
        option=$1
        [[ $option != --help ]] || { usage; exit 0; }
        (($# >= 2)) || { echo "missing value for $option" >&2; usage; exit 2; }
        value=$2
        case $option in
            --target)
                echo "--target is selected by the batch runner" >&2
                exit 2
                ;;
            --output)
                [[ -z $output ]] || { echo "duplicate --output" >&2; exit 2; }
                output=$value
                ;;
            --run-id)
                [[ -z $run_id ]] || { echo "duplicate --run-id" >&2; exit 2; }
                run_id=$value
                ;;
        esac
        forwarded+=("$option" "$value")
        shift 2
    done
    if [[ -z $output ]]; then
        output="$repository_root/reports/virtual-dispatch-test"
        forwarded+=(--output "$output")
    fi
    if [[ -z $run_id ]]; then
        run_id="run-$(date -u +%Y%m%dT%H%M%SZ)-$$"
        forwarded+=(--run-id "$run_id")
    fi
}

case $mode in
    build-docker)
        (($# == 0)) || { echo "build-all.sh accepts no arguments" >&2; usage; exit 2; }
        run_docker_batch build
        ;;
    build-native)
        (($# == 0)) || { echo "build-all-native.sh accepts no arguments" >&2; usage; exit 2; }
        run_native_batch build
        ;;
    run-docker)
        prepare_run_arguments "$@"
        run_docker_batch run "${forwarded[@]}"
        ;;
    run-native)
        prepare_run_arguments "$@"
        run_native_batch run "${forwarded[@]}"
        ;;
    *)
        echo "unknown batch mode: $mode" >&2
        exit 2
        ;;
esac
