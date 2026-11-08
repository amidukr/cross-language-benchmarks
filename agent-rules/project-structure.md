# Project structure

Place each benchmark workload in a directory named `<workload>-test/` at the
repository root. Use one implementation directory per language required by the
task. Put the scripts that build and run all targets in the workload root.

```text
<workload>-test/
├── build-all.sh
├── run-all.sh
├── build-all-native.sh
├── run-all-native.sh
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

## Per-language scripts

`build.sh` builds the implementation's Docker image and compiles or publishes
the workload. `run.sh` runs the already-built workload image with the supplied
benchmark arguments and writes results and logs to the configured output
directory. Follow [runner.md](runner.md) for the common command-line interface.
Both scripts must return a nonzero exit status when their operation fails.

`build_native.sh` builds or publishes the selected target with toolchains
installed on the host. `run_native.sh` runs the already-built host artifact
without rebuilding it. It accepts the same runner arguments as `run.sh` and
writes results and logs only to the selected `--output` directory. Both native
scripts must return a nonzero exit status when their operation fails.

Both build scripts must accept `--target <target-id>` and reject target IDs
that are invalid for the implementation directory. Use the canonical IDs from
[targets.md](targets.md) in image tags and artifact names so multiple targets
from one language directory cannot overwrite each other.

The native scripts must use the same sources, release settings, timing
boundaries, correctness checks, and target IDs as the Docker path. Keep host
build artifacts in a workload-local ignored directory, separated by target.
Report a clear error when a required host toolchain is missing or incompatible,
or when `run_native.sh` cannot find the artifact produced by `build_native.sh`.

Native and Docker executions are distinct trials. Record `execution_mode` as
`native` or `docker` in the run log, along with the exact host toolchain and
resource controls. Retain that provenance when combining samples.

## Reports

Store reports under `reports/` at the repository root, with one directory per
workload, one CSV per target, and the workload analysis in a Markdown file
beside the workload's report directory.

```text
reports/<workload>-test/<target-id>-report.csv
reports/<workload>-test.md
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
Write analysis tasks to `reports/<workload>-test.md` and follow
[analysis.md](analysis.md).

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

## Build and run all targets

Keep the following executable scripts directly in `<workload>-test/`.
Each script identifies its workload from its own location, so callers can
invoke it from the repository root or another working directory.

| Script                | Purpose                                     |
| --------------------- | ------------------------------------------- |
| `build-all.sh`        | Build every Docker target for the workload. |
| `run-all.sh`          | Run every previously built Docker target.   |
| `build-all-native.sh` | Build every target using host toolchains.   |
| `run-all-native.sh`   | Run every previously built host target.     |

Use the canonical language-to-target mapping from [targets.md](targets.md).
Select the targets for the workload's implementation directories and delegate
to their per-language scripts. Run targets sequentially.

The run scripts must pass the corresponding `--target` for each invocation and
forward the caller's benchmark arguments. Default `--output` to
`reports/<workload>-test/` relative to the repository root and honor an explicit
`--output` override. Run previously built targets without rebuilding them.

A Docker build or run failure must produce a nonzero batch exit status.

Native batches must attempt every target even when a target cannot build or run.
If a host toolchain is missing or incompatible, or a native build artifact is
missing, report the target as skipped. If a build or run fails for another
reason, report it as failed. In either case, record the target ID and reason,
then continue to the next target.

After a native batch, print a summary of successful, skipped, and failed
targets. Return a nonzero exit status if any target failed or no target
succeeded. A batch with successful and skipped targets exits successfully.
