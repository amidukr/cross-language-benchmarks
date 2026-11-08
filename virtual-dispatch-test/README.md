# Virtual dispatch benchmark

This workload implements Task 1.1 for all targets in `agent-rules/targets.md`.
Each language directory has a `build.sh` and `run.sh`; both scripts use Docker,
and `run.sh` pins the container to one logical CPU (`BENCH_CPU`, default `0`).
Each directory also has `build_native.sh` and `run_native.sh`. The first builds
the target with host-installed tools; the second runs that already-built target
without Docker and applies the same CPU pinning.

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

The native scripts fail when the requested toolchain or built artifact is
unavailable. Java native builds accept an installed JDK that supports
`--release 25`; Temurin JDK 25 remains preferred, and GraalVM targets still
require the corresponding GraalVM runtime or `native-image` tool.

The application appends successful samples to `results.csv`. Warmup samples use
phase `warmup`; retained measurement samples use `unclassified`. Diagnostics,
effective arguments, checksum, toolchain, image, and execution state are written
to the target/run-specific log in the selected output directory.
