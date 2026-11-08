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
- a Dockerfile containing the required build and runtime toolchain; and
- shell scripts to build and run the implementation.

Keep language-specific manifests and build definitions beside the
implementation, including `Cargo.toml`, `go.mod`, and an SDK-style `.csproj`
where applicable. Commit generated lock files when required by
[tooling.md](tooling.md).

Keep the shared C and C++ `CMakeLists.txt` in the workload root. Define separate
C and C++ executables for the workload. Support the GCC baseline and required
Clang C++ target with separate build directories so their artifacts and cached
configuration cannot overlap.

Repository-level orchestration may invoke the per-language scripts to build and
run complete target matrices. Keep workload-independent orchestration outside
the workload directories and reuse it across tasks.
