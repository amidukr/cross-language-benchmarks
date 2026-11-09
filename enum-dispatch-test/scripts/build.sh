#!/bin/sh
set -eu

language=${1:?language is required}
shift
target=
while [ "$#" -gt 0 ]; do
    case "$1" in
        --target)
            [ "$#" -ge 2 ] || { echo "missing value for --target" >&2; exit 2; }
            [ -z "$target" ] || { echo "duplicate --target" >&2; exit 2; }
            target=$2
            shift 2
            ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
done
[ -n "$target" ] || { echo "--target is required" >&2; exit 2; }

case "$language:$target" in
    c:c-gcc|c:c-clang|cpp:cpp-gcc|cpp:cpp-clang|java:temurin-c2|java:graalvm-jit|java:graalvm-native|rust:rust|go:go|python:cpython|csharp:coreclr|csharp:dotnet-native|javascript:node-v8) ;;
    *) echo "target '$target' is invalid for $language" >&2; exit 2 ;;
esac

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
"$container_engine" build --pull --build-arg "TARGET=$target" --file "$root/$language/Dockerfile" --tag "enum-dispatch-$target:latest" "$root"
