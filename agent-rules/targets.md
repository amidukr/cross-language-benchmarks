# Benchmark targets and measurement

## Comparison targets

| Language   | Target ID        | Runtime or toolchain                                    |
| ---------- | ---------------- | ------------------------------------------------------- |
| Java       | `temurin-c2`     | Eclipse Temurin JDK 25 LTS with HotSpot and its C2 JIT  |
| Java       | `graalvm-jit`    | GraalVM for JDK 25 in JVM mode with the Graal JIT       |
| Java       | `graalvm-native` | GraalVM for JDK 25 Native Image, compiled ahead of time |
| C++        | `cpp-gcc`        | GCC compiled in an optimized release build              |
| C++        | `cpp-clang`      | Clang compiled in an optimized release build            |
| C          | `c-gcc`          | C compiled with GCC in an optimized release build       |
| Rust       | `rust`           | Rust compiled in an optimized release build             |
| Go         | `go`             | Go compiled with the standard Go toolchain              |
| Python     | `cpython`        | CPython                                                 |
| C#         | `coreclr`        | .NET 10 LTS with the CoreCLR JIT                        |
| C#         | `dotnet-native`  | .NET 10 LTS Native AOT                                  |
| JavaScript | `node-v8`        | Node.js 26 LTS with the V8 JIT                          |

Use these target IDs in command-line arguments, image and artifact names,
result rows, and run logs.

Use JDK 25 as the common Java baseline. Reuse the Java workload source across the three Java targets where possible. Record the exact JDK distribution and build, including the GraalVM distribution or edition, and use matching JDK patch releases where available.

Reuse the same C++ workload source for GCC and Clang. Compile both with the same C++ language standard and equivalent optimized release settings. Report the exact compiler versions and flags as separate targets.

Use the same workload, inputs, correctness checks, and timing boundaries across targets. Record exact toolchain versions, compiler and runtime flags, hardware, and operating system. Report profile-guided builds or other tuned configurations as separate results.

## Measurement phases

Use the same timing boundaries for every target and repeat measurements in
independent processes. Build or publish the workload before the timed runs.

1. **Fresh-process runtime.** Use an external timer to measure process launch
   through exit for one invocation. Use the same workload and I/O boundaries
   for each target. Document the relevant cache state.
2. **Warmup.** Start a fresh process and repeat the workload in that process.
   Record elapsed time and per-window latency or throughput from the first
   window. Retain the time series for JIT, interpreted, and native targets.
3. **Steady state.** Continue the workload in the same process. Define the
   measurement window, stability tolerance, and maximum warmup budget in the
   workload spec before running it. Apply the same criterion across targets
   and allow each target to stabilize at its own pace. Report a distribution
   across measurement windows and independent runs. If a target fails to
   stabilize within the budget, report that outcome.

## Runtime-specific checks

Keep default runtime behavior for the baseline and label tuned configurations
separately. Run compilation diagnostics separately from headline timing runs.
Use the same build, inputs, and execution settings for diagnostics, apart from
the diagnostic options. Report compilation evidence separately from observed
steady-state performance. A compilation event alone does not establish
stability.

### Java on HotSpot and GraalVM

- Keep tiered compilation enabled. Inspect compilation events using
  `-XX:+PrintCompilation` or Java Flight Recorder.
- For Temurin, check that the hot path reaches HotSpot tier 4 (C2) before the
  planned steady-state window. Inspect the compiled caller if the workload was
  inlined. Check for on-stack replacement (OSR) when a long-running loop
  transitions to optimized code during execution.
- For GraalVM JVM mode, confirm the active top-tier compiler using
  `-Djdk.graal.ShowConfiguration=info` and verify optimized compilation of the
  hot path before the planned steady-state window.

### .NET CoreCLR

- Build in `Release` and time the already-built application. Use default tiered
  compilation, Dynamic PGO, and ReadyToRun behavior. Record any overrides and
  whether the application was published with ReadyToRun.
- In a diagnostic run, check for optimized Tier 1 code on the hot path. For
  long-running loops, check whether the active invocation transitions to
  optimized code through OSR. Inspect the caller if the workload was inlined.

### Node.js and V8

- Record the exact Node.js and V8 versions. Keep default V8 optimization
  settings for the baseline.
- In a diagnostic run, inspect optimization and deoptimization of the hot
  path. Use `--trace-opt` and `--trace-deopt` if the installed build lists them
  in `node --v8-options`.
- For fresh-process measurements, record whether the module compile cache is
  enabled and whether it is empty or populated.

### CPython

- Use a standard CPython build with the GIL enabled and the experimental JIT
  disabled for the baseline. Record the exact version and build.
- Report free-threaded builds and runs with the experimental JIT enabled as
  separate configurations.

### Native builds

- Apply the same timing boundaries and stability criterion to C, C++, Rust,
  Go, GraalVM Native Image, and .NET Native AOT. JIT compilation checks apply
  only to JIT configurations.
- Report builds that use an offline training profile as separate
  configurations. Default runtime profiling, such as CoreCLR Dynamic PGO,
  belongs to the default runtime configuration.

## Workload equivalence

Match the algorithm, numeric semantics, and amount of work when comparing
implementations. For example, use exact integer arithmetic in `edigits`,
including `BigInt` in JavaScript when the values exceed the safe integer range
of `Number`. If an implementation delegates the core algorithm to an external
native library, report it as a separate library-backed configuration.

## References

- [Eclipse Temurin JDK](https://adoptium.net/)
- [How tiered compilation works in OpenJDK](https://devblogs.microsoft.com/java/how-tiered-compilation-works-in-openjdk/)
- [Graal JIT Compiler Operations Manual](https://www.graalvm.org/jdk25/reference-manual/compiler/operations/)
- [Microsoft .NET compilation settings](https://learn.microsoft.com/en-us/dotnet/core/runtime-config/compilation)
- [Performance improvements in .NET 10](https://devblogs.microsoft.com/dotnet/performance-improvements-in-net-10/)
- [Node.js V8 options](https://nodejs.org/docs/latest-v26.x/api/v8.html)
- [Node.js module compile cache](https://nodejs.org/docs/latest-v26.x/api/module.html#module-compile-cache)
- [CPython build configuration](https://docs.python.org/3.14/using/configure.html)
