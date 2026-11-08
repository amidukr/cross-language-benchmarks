# Virtual dispatch benchmark

This workload implements Task 1.1 for all targets in `agent-rules/targets.md`.
Each language directory has a `build.sh` and `run.sh`; both scripts use Docker,
and `run.sh` pins the container to one logical CPU (`BENCH_CPU`, default `0`).
Each directory also has `build_native.sh` and `run_native.sh`. The first builds
the target with host-installed tools; the second runs that already-built target
without Docker and applies the same CPU pinning.

The workload root also provides `build-all.sh`, `run-all.sh`,
`build-all-native.sh`, and `run-all-native.sh` for processing the full target
matrix sequentially. The run-all scripts default to
`reports/virtual-dispatch-test/` and accept the standard runner options except
`--target`, which they select for each invocation.

## Benchmark targets

Use the language directory and its corresponding `--target` value.

| #   | Language directory | `--target` value |
| --- | ------------------ | ---------------- |
| 1   | `c`                | `c-gcc`          |
| 2   | `c`                | `c-clang`        |
| 3   | `cpp`              | `cpp-gcc`        |
| 4   | `cpp`              | `cpp-clang`      |
| 5   | `java`             | `temurin-c2`     |
| 6   | `java`             | `graalvm-jit`    |
| 7   | `java`             | `graalvm-native` |
| 8   | `rust`             | `rust`           |
| 9   | `go`               | `go`             |
| 10  | `python`           | `cpython`        |
| 11  | `csharp`           | `coreclr`        |
| 12  | `csharp`           | `dotnet-native`  |
| 13  | `javascript`       | `node-v8`        |

## Usage

Example:

```sh
./virtual-dispatch-test/java/build.sh --target temurin-c2
./virtual-dispatch-test/java/run.sh \
  --target temurin-c2 --size 100000 --seed 42 --repeats 100 \
  --value 7 --warmup-samples 10 --samples 30 \
  --output ./results --run-id example-001 --trial 1 --config-id default
```

For a native run, use the corresponding two-phase host workflow:

```sh
./virtual-dispatch-test/java/build_native.sh --target temurin-c2
./virtual-dispatch-test/java/run_native.sh \
  --target temurin-c2 --size 100000 --seed 42 --repeats 100 \
  --value 7 --warmup-samples 10 --samples 30 \
  --output ./results --run-id example-native-001 --trial 1 \
  --config-id default
```

### Run all targets with Docker

Build the complete Docker target matrix, then run the previously built images:

```sh
./virtual-dispatch-test/build-all.sh
./virtual-dispatch-test/run-all.sh \
  --size 100000 --seed 42 --repeats 100 --value 7 \
  --warmup-samples 10 --samples 30 \
  --run-id example-all-docker-001 --trial 1 --config-id default
```

The container scripts use `docker` by default. To use Podman, set
`CONTAINER_ENGINE=podman` for both commands:

```sh
CONTAINER_ENGINE=podman ./virtual-dispatch-test/build-all.sh
CONTAINER_ENGINE=podman ./virtual-dispatch-test/run-all.sh \
  --size 100000 --seed 42 --repeats 100 --value 7 \
  --warmup-samples 10 --samples 30 \
  --run-id example-all-podman-001 --trial 1 --config-id default
```

Rootless Podman may not expose the cgroup `cpuset` controller. The Podman path
therefore applies one-CPU affinity with host `taskset`; Docker continues to use
`--cpuset-cpus`. The runner also detects when the `docker` command is Podman's
Docker-CLI compatibility wrapper and automatically uses the Podman path. Set
`BENCH_CPU` to select the logical CPU in either mode.

### Run all targets natively

Build every target supported by the host, then run the artifacts that were
built successfully:

```sh
./virtual-dispatch-test/build-all-native.sh
./virtual-dispatch-test/run-all-native.sh \
  --size 100000 --seed 42 --repeats 100 --value 7 \
  --warmup-samples 10 --samples 30 \
  --run-id example-all-native-001 --trial 1 --config-id default
```

Both run-all commands write to `reports/virtual-dispatch-test/` by default. Add
`--output <directory>` to use another location. Do not pass `--target`; the
batch scripts select each target automatically. Native batches skip targets
whose required host toolchains or previously built artifacts are unavailable,
continue through the matrix, and print a summary.

The native scripts fail when the requested toolchain or built artifact is
unavailable. Java native builds accept an installed JDK that supports
`--release 25`; Temurin JDK 25 remains preferred, and GraalVM targets still
require the corresponding GraalVM runtime or `native-image` tool.

The application appends successful samples to `<target-id>-report.csv` (for
example, `temurin-c2-report.csv`). Warmup samples use phase `warmup`; retained
measurement samples use `unclassified`. Diagnostics, effective arguments,
checksum, toolchain, image, and execution state are written to the
target/run-specific log in the selected output directory.
