# Assembly analysis rules

Analyze the code generated for the benchmark's timed region. Collect
performance metrics in clean runs with the benchmark configuration's normal
JIT settings. Enable JIT disassembly, tracing, and other assembly diagnostics
only in separate diagnostic processes. Exclude all diagnostic-run timings
from the benchmark CSVs and performance comparisons. Follow the clean
performance-run requirements in [targets.md](targets.md); diagnostic flags and
environment variables must never leak into startup, warmup, or retained timing
samples.

## Collect evidence

- Use the assembly diagnostic scripts defined by
  [project-structure.md](project-structure.md). Select the container or native
  path explicitly and do not mix their evidence without retaining execution
  provenance. Pass representative workload arguments and a stable diagnostic
  run ID to every target capture.
- Prefer the exact optimized artifact used in the benchmark. For JIT targets,
  use the same runtime, inputs, and optimization settings, with disassembly
  enabled in a separate process. Record the exact command, target ID,
  toolchain, flags, architecture, and execution mode.
- If symbols or tools are missing, try to locate the code by address or use a
  diagnostic build that retains symbols. Record every difference from the
  measured configuration. Label forced compilation, disabled inlining, and
  other optimization changes as separate configurations.
- For JIT code, record the tier, whether the compilation used on-stack
  replacement (OSR), and any relevant recompilation or deoptimization.
  Distinguish code that was emitted from code observed executing. A listing
  from a separate run cannot establish which instructions ran in a timed
  sample or whether performance was stable.
- Keep the raw output and identify the symbol or address range in each cited
  excerpt. If native code cannot be captured, report what evidence is
  available and why capture was unavailable.
- Verify each capture manifest before using its evidence. A diagnostic command
  that exits successfully but does not identify the requested hot region is an
  incomplete capture, not a successful assembly result.

## Collection methods

| Targets | Preferred evidence |
| --- | --- |
| C and C++ with GCC or Clang, Rust | Disassemble the linked executable with GNU `objdump` or `llvm-objdump`. Inspect the optimized caller if the workload was inlined. |
| Go | Use `go tool objdump` on the executable. If the benchmark build strips symbols and the hot region cannot be located reliably, capture a separate build with symbols retained. |
| GraalVM Native Image and .NET Native AOT | Disassemble the native executable. Use matching symbols or a symbol-retaining diagnostic build if needed. |
| HotSpot C2 and GraalVM JIT | Use HotSpot assembly and compilation diagnostics where supported, such as `-XX:+UnlockDiagnosticVMOptions -XX:+PrintAssembly` with an available `hsdis` decoder. Verify the compiler and tier that produced the listing. |
| .NET CoreCLR | Use `DOTNET_JitDisasm` with a method filter. Include the caller when the workload is inlined and identify Tier 0, Tier 1, or OSR versions as applicable. |
| Node.js / V8 | Inspect `node --v8-options` for optimized-code printing and filters, such as `--print-opt-code`. Use optimization and deoptimization traces as supporting evidence. Record the actual V8 version and flags. |
| CPython baseline | Use `dis` on the workload functions. Capture adaptive bytecode after warmup where supported. Label this evidence as Python bytecode and keep it separate from native assembly. |

## Interpret the output

Map the hot loop and call sites back to source. Identify direct and indirect
calls, guarded fast paths, inlined operations, and fallback paths only where
the listing supports them. Include relevant loop, arithmetic, and memory
access instructions. Report uncertainty when the evidence cannot distinguish
two explanations. Instruction listings alone do not establish execution
frequency or the cost of an individual operation.

## Present findings

- Follow the human-readable target naming rules in [report.md](report.md).
  In Markdown generated-code and assembly reports, first mentions, target
  comparison tables, charts, and target-specific headings must identify the
  implementation language as well as the runtime or toolchain.
- Use labels such as `Java (Eclipse Temurin, HotSpot C2)`,
  `Java (GraalVM JIT)`, `Java (GraalVM Native Image)`, and
  `C# (.NET CoreCLR)`, rather than using `Temurin`, `GraalVM`, or `CoreCLR`
  alone. When multiple targets use the same language, retain the qualifier so
  readers can distinguish their code-generation modes.
- Keep canonical target IDs unchanged in capture paths, manifests, commands,
  raw-file links, and other artifact references. Include the ID alongside the
  human-readable label when it helps connect a conclusion to its evidence.

## References

- [GNU objdump](https://sourceware.org/binutils/docs/binutils/objdump.html)
- [Go objdump](https://pkg.go.dev/cmd/objdump)
- [JDK 25 Java launcher options](https://docs.oracle.com/en/java/javase/25/docs/specs/man/java.html)
- [CoreCLR JIT disassembly](https://github.com/dotnet/runtime/blob/main/docs/design/coreclr/jit/viewing-jit-dumps.md)
- [Node.js V8 options](https://nodejs.org/dist/latest/docs/api/v8.html)
- [CPython bytecode disassembly](https://docs.python.org/3.14/library/dis.html)
