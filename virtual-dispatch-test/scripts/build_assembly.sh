#!/usr/bin/env bash
set -euo pipefail
language=${1:?language is required}
shift

target=
profile=assembly
while (($# > 0)); do
    case $1 in
        --target)
            [[ -z $target ]] || {
                echo "duplicate --target" >&2
                exit 2
            }
            target=${2:?missing value for --target}
            shift 2
            ;;
        --diagnostic-profile)
            profile=${2:?missing value for --diagnostic-profile}
            shift 2
            ;;
        --help)
            echo "usage: build_assembly.sh LANGUAGE --target ID [--diagnostic-profile ID]"
            exit 0
            ;;
        *)
            echo "unknown option: $1" >&2
            exit 2
            ;;
    esac
done

identifier='^[A-Za-z0-9][A-Za-z0-9._-]*$'
[[ $target =~ $identifier && $profile =~ $identifier ]] || {
    echo "missing or invalid identifier" >&2
    exit 2
}

case "$language:$target" in
    c:c-gcc | c:c-clang | cpp:cpp-gcc | cpp:cpp-clang | \
        java:temurin-c2 | java:graalvm-jit | java:graalvm-native | \
        rust:rust | go:go | python:cpython | \
        csharp:coreclr | csharp:dotnet-native | javascript:node-v8) ;;
    *)
        echo "target '$target' is invalid for $language" >&2
        exit 2
        ;;
esac

engine=${CONTAINER_ENGINE:-docker}
case $engine in
    docker | podman) ;;
    *)
        echo "unsupported container engine: $engine" >&2
        exit 2
        ;;
esac
command -v "$engine" >/dev/null || {
    echo "container engine not found: $engine" >&2
    exit 127
}
root=$(cd -- "$(dirname -- "$0")/.." && pwd)
case $target in
    c-gcc | c-clang | cpp-gcc | cpp-clang) stage="build-$target" ;;
    temurin-c2) stage=build-temurin ;;
    graalvm-jit) stage=build-graal-jit ;;
    graalvm-native) stage=build-graal-native ;;
    coreclr) stage=build-coreclr ;;
    dotnet-native) stage=build-native ;;
    *) stage=assembly ;;
esac
tag="virtual-dispatch-$target-$profile:latest"
"$engine" build --pull \
    --build-arg "TARGET=$target" \
    --target "$stage" \
    --file "$root/$language/Dockerfile" \
    --tag "$tag" \
    "$root"
echo "built $tag from stage $stage" >&2
