# Project structure

Place each benchmark workload in a directory named `<workload>-test/` at the
repository root. Use one implementation directory per language required by the
task.

```text
<workload>-test/
├── c/
├── cpp/
├── csharp/
├── go/
├── java/
├── javascript/
├── python/
└── rust/
```

Omit a language directory only when the workload task does not target that
language. Use the directory names shown above consistently across workloads.

Each implementation directory must contain all of the following.

- Its language-specific source code
- A `Dockerfile` containing the required build and runtime toolchain
- An executable `build.sh` script
- An executable `run.sh` script
- An executable `build_native.sh` script
- An executable `run_native.sh` script

`build.sh` builds the implementation's Docker image and compiles or publishes
the workload. `run.sh` runs the already-built workload image with the supplied
benchmark arguments and writes results and logs to the configured output
directory. Follow [runner.md](runner.md) for the common command-line interface.
Both scripts must fail with a nonzero exit code when their operation does not
complete successfully.

`build_native.sh` builds or publishes the selected target with toolchains
installed on the host. Like `build.sh`, it accepts `--target <target-id>` and
rejects invalid targets. `run_native.sh` runs the already-built host artifact
without rebuilding it. Like `run.sh`, it accepts the standard runner arguments
and writes results and logs only to the selected `--output` directory. Both
native scripts must fail with a nonzero exit status when their operation does
not complete successfully.

The native scripts must use the same sources, release settings, timing
boundaries, correctness checks, and target IDs as the Docker path. Keep host
build artifacts in a workload-local ignored directory, separated by target so
toolchains cannot overwrite one another. Fail clearly when a required host
toolchain is missing, does not match the requested target, or when
`run_native.sh` cannot find an artifact previously produced by
`build_native.sh`.

Native and Docker executions are distinct trials. Record `execution_mode` as
`native` or `docker` in the run log, along with the exact host toolchain and
resource controls. Retain that provenance when combining samples.

`build.sh` must accept `--target <target-id>`. Reject a target ID that is not
valid for the implementation directory. Use the canonical IDs from
[targets.md](targets.md) in image tags and artifact names so multiple targets
from one language directory cannot overwrite each other.

## Reports

Store reports under `reports/` at the repository root, with one directory per
workload and one CSV per target.

```text
reports/<workload>-test/<target-id>-report.csv
```

For standard repository runs, pass `--output reports/<workload>-test` to
`run.sh` or `run_native.sh`. Both scripts must write `<target-id>-report.csv`
directly in the selected output directory, using the canonical ID passed via
`--target`. For example, the `cpp-gcc` and `temurin-c2` targets for
`virtual-dispatch-test` write these files.

```text
reports/virtual-dispatch-test/cpp-gcc-report.csv
reports/virtual-dispatch-test/temurin-c2-report.csv
```

Append subsequent samples to the report for the selected target. Pass separate
`--output` directories when Docker and native runs need separate report files.

## Build definitions

Keep language-specific manifests and build definitions beside the
implementation, including `Cargo.toml`, `go.mod`, and an SDK-style `.csproj`
where applicable. Commit generated lock files when required by
[tooling.md](tooling.md).

Keep the shared C and C++ `CMakeLists.txt` in the workload root. Define separate
C and C++ executables for the workload. Support GCC and Clang targets for both
languages with separate build directories so their artifacts and cached
configuration cannot overlap.

Use the workload directory as the Docker build context for every implementation
and select the implementation Dockerfile with `--file`. For example, build the
C++ image from the repository root with the following command.

```sh
docker build --file <workload>-test/cpp/Dockerfile <workload>-test/
```

This context gives Dockerfiles access to workload-level build definitions and
shared files.

Repository-level orchestration may invoke the per-language scripts to build and
run complete target matrices. Keep workload-independent orchestration outside
the workload directories and reuse it across tasks.
