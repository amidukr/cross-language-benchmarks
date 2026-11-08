# Project structure

Place each benchmark workload in a directory named `<workload>-test/` at the
repository root. Use one implementation directory per language required by the
task:

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

Each implementation directory must contain:

- its language-specific source code;
- a Dockerfile containing the required build and runtime toolchain;
- an executable `build.sh` script; and
- an executable `run.sh` script.

`build.sh` builds the implementation's Docker image and compiles or publishes
the workload. `run.sh` runs the already-built workload image with the supplied
benchmark arguments and writes results and logs to the configured output
directory. Follow [runner.md](runner.md) for the common command-line interface.
Both scripts must fail with a nonzero exit code when their operation does not
complete successfully.

`build.sh` must accept `--target <target-id>`. Reject a target ID that is not
valid for the implementation directory. Use the canonical IDs from
[targets.md](targets.md) in image tags and artifact names so multiple targets
from one language directory cannot overwrite each other.

Keep language-specific manifests and build definitions beside the
implementation, including `Cargo.toml`, `go.mod`, and an SDK-style `.csproj`
where applicable. Commit generated lock files when required by
[tooling.md](tooling.md).

Keep the shared C and C++ `CMakeLists.txt` in the workload root. Define separate
C and C++ executables for the workload. Support GCC and Clang targets for both
languages with separate build directories so their artifacts and cached
configuration cannot overlap.

Use the workload directory as the Docker build context for every implementation
and select the implementation Dockerfile with `--file`. For example:

```sh
docker build --file <workload>-test/cpp/Dockerfile <workload>-test/
```

This context allows Dockerfiles to access workload-level build definitions and
shared files without accessing unrelated repository content.

Repository-level orchestration may invoke the per-language scripts to build and
run complete target matrices. Keep workload-independent orchestration outside
the workload directories and reuse it across tasks.
