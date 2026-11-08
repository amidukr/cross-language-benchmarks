# Benchmark targets and measurement

## Comparison targets

| Language | Runtime or toolchain |
| --- | --- |
| Java | Eclipse Temurin JDK 25 LTS with HotSpot and its C2 JIT |
| Java | GraalVM for JDK 25 in JVM mode with the Graal JIT |
| Java | GraalVM for JDK 25 Native Image, compiled ahead of time |
| C++ | C++ compiled in an optimized release build |
| C | C compiled in an optimized release build |
| Rust | Rust compiled in an optimized release build |
| Go | Go compiled with the standard Go toolchain |
| Python | CPython |
| C# | .NET 10 LTS with the CoreCLR JIT |
| C# | .NET 10 LTS Native AOT |
| JavaScript | Node.js 26 LTS with the V8 JIT |

Use JDK 25 as the common Java baseline. Reuse the Java workload source across the three Java targets where possible. Record the exact JDK distribution and build, including the GraalVM distribution or edition, and use matching JDK patch releases where available.

Use the same workload, inputs, correctness checks, and timing boundaries across targets. Record exact toolchain versions, compiler and runtime flags, hardware, and operating system. Report profile-guided builds or other tuned configurations as separate results.

## JVM measurements

Measure the Temurin and GraalVM JVM targets in fresh processes across repeated runs. Report these phases separately.

1. **Fresh-process runtime.** Use an external timer to measure one invocation from process launch to exit when the task calls for startup-inclusive timing.
2. **Warmup.** Start with a fresh JVM and record elapsed time and per-iteration latency or throughput as the workload repeats in that process. Retain the time series so startup effects and transitions during JIT compilation are visible.
3. **Steady state.** Continue the same workload in the same process after warmup. Define and document the stability window and tolerance for the benchmark. Report a distribution across measurement iterations and independent JVM runs. If the workload fails to stabilize within the run budget, report that outcome.

### Verify top-tier compilation

- Leave tiered compilation enabled for the baseline. Run a diagnostic pass with the same workload and settings, using `-XX:+PrintCompilation` or Java Flight Recorder to inspect compilation events. Collect headline timings in separate runs without compilation logging.
- For Temurin, verify that the code executing the hot path reaches HotSpot tier 4 (C2) by the planned measurement window. Inspect the compiled caller if the workload was inlined. For long-running loops, check whether the relevant compilation used on-stack replacement (OSR).
- For GraalVM JVM mode, confirm that Graal is the active top-tier compiler with `-Djdk.graal.ShowConfiguration=info` in the diagnostic pass. Verify compilation of the hot path before the planned measurement window.
- Use both compilation evidence and the timing series to identify the measurement window. A tier 4 event confirms a compilation occurred. If the hot path continues to deoptimize or recompile, or performance continues to shift, extend the run and reassess. Report steady-state timing and top-tier verification separately if either remains inconclusive.
- Use the same steady-state measurement boundaries for non-JVM targets where applicable. The JVM compilation checks apply only to the JVM targets.

## References

- [Eclipse Temurin JDK](https://adoptium.net/)
- [How tiered compilation works in OpenJDK](https://devblogs.microsoft.com/java/how-tiered-compilation-works-in-openjdk/)
- [Graal JIT Compiler Operations Manual](https://www.graalvm.org/jdk25/reference-manual/compiler/operations/)
