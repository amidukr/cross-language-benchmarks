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
├── build-all-assembly.sh
├── capture-all-assembly.sh
├── build-all-assembly-native.sh
├── capture-all-assembly-native.sh
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

When a workload has an assembly or code-generation analysis task, each
implementation directory must also contain these executable scripts.

- `build_assembly.sh`
- `capture_assembly.sh`
- `build_assembly_native.sh`
- `capture_assembly_native.sh`

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

## Assembly diagnostic scripts

Assembly diagnostic scripts form a separate workflow from performance build
and run scripts.

| Script | Purpose |
| --- | --- |
| `build_assembly.sh` | Prepare a container image or artifact needed for containerized assembly capture. |
| `capture_assembly.sh` | Capture assembly, bytecode, or JIT evidence in a container. |
| `build_assembly_native.sh` | Prepare a host artifact needed for native assembly capture. |
| `capture_assembly_native.sh` | Capture assembly, bytecode, or JIT evidence on the host. |

Both build scripts must accept `--target <target-id>` and
`--diagnostic-profile <id>`, defaulting the profile to `assembly`. Validate the
target for the implementation directory and keep diagnostic artifacts separate
from performance artifacts. Reuse the exact performance artifact without
rebuilding when it contains sufficient evidence. When a symbol-retaining or
otherwise modified build is required, use a target- and profile-specific image
tag or build directory and record every difference from the performance build.

Both capture scripts must accept `--target <target-id>`,
`--diagnostic-profile <id>`, `--diagnostic-run-id <id>`, the workload arguments
needed to reproduce the hot path, and an optional `--output <directory>`.
Default the profile to `assembly` and default `--output` to
`reports/<workload>-test/assembly` relative to the repository root. Write raw
evidence and a capture manifest beneath
`<output>/<target-id>/<execution-mode>/<diagnostic-run-id>/`, where execution
mode is `docker`, `podman`, or `native`. The manifest must record the exact
commands, target, diagnostic profile, diagnostic run ID, toolchain and
diagnostic-tool versions, flags, environment, execution mode, container engine
and image when applicable, artifact identity, workload arguments, capture
status, and failure or skip reason.

Diagnostic profile and run IDs must follow the identifier grammar from
[runner.md](runner.md). Reject missing values, malformed identifiers, unknown
options, and conflicting duplicates before building or capturing evidence.

Container and native captures are distinct diagnostic runs. Container scripts
must support Docker and Podman through `CONTAINER_ENGINE` under the same rules
as performance scripts. Native scripts must verify host tools and artifacts.
Capture scripts may enable diagnostic runtime flags and environment variables,
but only in the diagnostic process. They must never invoke a performance run,
append to `<target-id>-report.csv`, or place diagnostic output in clean-run
logs. A capture failure must return nonzero after writing its manifest; an
unavailable optional decoder or tool may be reported as skipped by batch
orchestration.

## Reports

Store reports under `reports/` at the repository root, with one directory per
workload, one CSV per target, and analysis Markdown files beside the workload's
report directory. Keep raw assembly and code-generation diagnostics inside the
workload's report directory, separated by target, execution mode, and
diagnostic run.

```text
reports/<workload>-test/<target-id>-report.csv
reports/<workload>-test/assembly/<target-id>/<execution-mode>/<diagnostic-run-id>/
reports/<workload>-test.md
reports/<workload>-test-assembly.md
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

Write assembly and code-generation analysis to
`reports/<workload>-test-assembly.md`. Store its raw evidence under
`reports/<workload>-test/assembly/<target-id>/<execution-mode>/<diagnostic-run-id>/`
and follow [assembly-analysis.md](assembly-analysis.md). Keep diagnostic
artifacts and their output separate from timing CSVs and clean performance-run
logs.

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

## Build and capture assembly for all targets

Keep the following executable assembly orchestration scripts directly in
`<workload>-test/` when the workload has an assembly-analysis task.

| Script | Purpose |
| --- | --- |
| `build-all-assembly.sh` | Prepare container diagnostics for every target. |
| `capture-all-assembly.sh` | Capture every target using Docker or Podman. |
| `build-all-assembly-native.sh` | Prepare native diagnostics for every target. |
| `capture-all-assembly-native.sh` | Capture every target using host tools. |

Use the canonical language-to-target mapping and run targets sequentially.
Build-all scripts delegate to the corresponding per-language assembly build
script and forward `--diagnostic-profile`. Capture-all scripts require one
`--diagnostic-run-id`, forward the diagnostic profile and common workload
arguments, select each target automatically, and honor an explicit `--output`
override.

Assembly batches must attempt every target. Report unavailable toolchains,
decoders, profilers, or artifacts as skipped; report other nonzero outcomes as
failed; record the target and reason; and continue. Print succeeded, skipped,
and failed summaries. Return nonzero when any target failed or when no target
produced usable evidence. A batch with successful and skipped targets exits
successfully.
