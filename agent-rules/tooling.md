# Language toolsets

Use the toolsets below to build and run benchmark targets. Install and invoke
them inside Docker as required by [docker.md](docker.md). The host only needs
Docker and the repository's orchestration scripts.

Pin every container base image and toolchain version in the benchmark's Docker
files. Record the exact version reported by the compiler or runtime in the run
log and `toolchain` result field. Record all non-default build and runtime
options in the `flags` field.

## Toolset matrix

| Targets                   | Build tooling inside Docker                                                                                                                                        |
| ------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **C and C++**             | Use CMake with Ninja and `Release`. Use GCC as the baseline. Build the required C++ Clang target from the same sources and CMake project with equivalent settings. |
| **Java**                  | Start with `javac` and `java` for dependency-free workloads. Reuse the Java sources across Temurin and GraalVM, and build the AOT executable with `native-image`.  |
| **C#**                    | Use one SDK-style `.csproj`. Build in `Release` for CoreCLR and publish a separate Native AOT executable. Include the native toolchain in the AOT builder image.   |
| **Rust and Go**           | Use `cargo build --release --locked` and `go build`. Commit `Cargo.lock` and the Go module files.                                                                  |
| **Python and JavaScript** | Run the workload directly with `python3` and `node`. The `virtual-dispatch` workload uses only built-in functionality.                                             |

## Build rules

- Keep one CMake project for the C and C++ implementations. Define a separate
  executable for each language and workload. Use CMake presets or explicit
  configure directories to keep GCC and Clang builds separate.
- Use the same C++ sources, language standard, and equivalent release settings
  for GCC and Clang. Report them as separate targets.
- Reuse the same Java sources for Temurin, GraalVM JIT, and GraalVM Native Image
  unless a documented target limitation requires a target-specific change.
- Do not add third-party workload or benchmark dependencies unless a task
  requires them. Keep dependency-backed configurations separate from the
  baseline.
- Build or publish artifacts before measurement begins. Run the already-built
  artifact during startup, warmup, and measured trials.

## Supporting tools

Follow [project-structure.md](project-structure.md) for Dockerfile, script, and
language-manifest locations. Scripts orchestrate the selected build tools inside
Docker; they do not replace those tools.

Use the container runtime to set CPU affinity and resource limits. Install any
timing, memory, or diagnostic utility that contributes report data in the
relevant image, pin it where applicable, and record it in the run log.

Diagnostic tools may differ by runtime, but they must observe the same built
artifact as the headline run. Enable intrusive diagnostics only in separate
diagnostic runs.

## References

- [CMake command-line reference](https://cmake.org/cmake/help/latest/manual/cmake.1.html)
- [.NET Native AOT deployment](https://learn.microsoft.com/en-us/dotnet/core/deploying/native-aot/)
