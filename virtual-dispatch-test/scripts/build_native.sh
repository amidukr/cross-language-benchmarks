#!/usr/bin/env bash
set -euo pipefail

language=${1:?language is required}
shift
target=
while (($# > 0)); do
    case $1 in
        --target)
            (($# >= 2)) || { echo "missing value for --target" >&2; exit 2; }
            [[ -z $target ]] || { echo "duplicate --target" >&2; exit 2; }
            target=$2
            shift 2
            ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
done
[[ -n $target ]] || { echo "--target is required" >&2; exit 2; }

case "$language:$target" in
    c:c-gcc|c:c-clang|cpp:cpp-gcc|cpp:cpp-clang|java:temurin-c2|java:graalvm-jit|java:graalvm-native|rust:rust|go:go|python:cpython|csharp:coreclr|csharp:dotnet-native|javascript:node-v8) ;;
    *) echo "target '$target' is invalid for $language" >&2; exit 2 ;;
esac

root=$(cd -- "$(dirname -- "$0")/.." && pwd)
build_dir="$root/.native/$target"
mkdir -p "$build_dir"
log="$build_dir/build.log"
: >"$log"

require_command() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "required command not found: $1" | tee -a "$log" >&2
        exit 127
    }
}

check_javac() {
    require_command javac
    local version
    version=$(javac -version 2>&1)
    echo "$version" >>"$log"
    printf '%s\n' "$version" >"$build_dir/build_toolchain.txt"
}

case $target in
    c-gcc|c-clang|cpp-gcc|cpp-clang)
        require_command cmake
        require_command ninja
        if [[ $target == *-gcc ]]; then
            require_command gcc
            require_command g++
            c_compiler=gcc
            cpp_compiler=g++
        else
            require_command clang
            require_command clang++
            c_compiler=clang
            cpp_compiler=clang++
        fi
        cmake -S "$root" -B "$build_dir" -G Ninja \
            -DCMAKE_BUILD_TYPE=Release \
            -DCMAKE_C_COMPILER="$c_compiler" \
            -DCMAKE_CXX_COMPILER="$cpp_compiler" >>"$log" 2>&1
        if [[ $target == c-* ]]; then
            cmake --build "$build_dir" --target virtual-dispatch-c >>"$log" 2>&1
        else
            cmake --build "$build_dir" --target virtual-dispatch-cpp >>"$log" 2>&1
        fi
        ;;
    temurin-c2|graalvm-jit)
        check_javac
        javac --release 25 -d "$build_dir" "$root/java/VirtualDispatch.java" >>"$log" 2>&1
        ;;
    graalvm-native)
        check_javac
        require_command native-image
        native_version=$(native-image --version 2>&1)
        [[ $native_version == *GraalVM* ]] || {
            echo "installed native-image is not GraalVM" | tee -a "$log" >&2
            exit 2
        }
        javac --release 25 -d "$build_dir" "$root/java/VirtualDispatch.java" >>"$log" 2>&1
        native-image --no-fallback -O3 -cp "$build_dir" \
            -o "$build_dir/virtual-dispatch" VirtualDispatch >>"$log" 2>&1
        ;;
    rust)
        require_command cargo
        require_command rustc
        rust_version=$(rustc --version)
        RUSTC_VERSION=${rust_version#rustc } CARGO_TARGET_DIR="$build_dir" \
            cargo build --release --locked \
            --manifest-path "$root/rust/Cargo.toml" >>"$log" 2>&1
        ;;
    go)
        require_command go
        (
            cd "$root/go"
            CGO_ENABLED=0 go build -trimpath -ldflags='-s -w' \
                -o "$build_dir/virtual-dispatch" .
        ) >>"$log" 2>&1
        ;;
    cpython)
        require_command python3
        PYTHONPYCACHEPREFIX="$build_dir/pycache" \
            python3 -m py_compile "$root/python/virtual_dispatch.py" >>"$log" 2>&1
        cp "$root/python/virtual_dispatch.py" "$build_dir/virtual_dispatch.py"
        ;;
    coreclr)
        require_command dotnet
        [[ $(dotnet --version) == 10.* ]] || {
            echo "installed dotnet SDK is not version 10" | tee -a "$log" >&2
            exit 2
        }
        dotnet publish "$root/csharp/VirtualDispatch.csproj" -c Release \
            --no-self-contained -o "$build_dir" >>"$log" 2>&1
        ;;
    dotnet-native)
        require_command dotnet
        [[ $(dotnet --version) == 10.* ]] || {
            echo "installed dotnet SDK is not version 10" | tee -a "$log" >&2
            exit 2
        }
        dotnet publish "$root/csharp/VirtualDispatch.csproj" -c Release \
            -r linux-x64 -p:PublishAot=true -o "$build_dir" >>"$log" 2>&1
        ;;
    node-v8)
        require_command node
        [[ $(node --version) == v26.* ]] || {
            echo "installed Node.js is not version 26" | tee -a "$log" >&2
            exit 2
        }
        node --check "$root/javascript/virtual-dispatch.js" >>"$log" 2>&1
        cp "$root/javascript/virtual-dispatch.js" "$build_dir/virtual-dispatch.js"
        ;;
esac

echo "native target '$target' built in $build_dir" >&2
