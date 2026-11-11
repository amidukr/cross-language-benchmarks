# Cross-language benchmarks

This project compares equivalent workloads across programming languages,
compilers, and runtimes under documented, reproducible conditions. It keeps
clean timing runs separate from generated-code diagnostics and preserves the
CSV data, logs, commands, manifests, and analysis used for each conclusion.

The completed work currently covers two related workloads:

- **Virtual dispatch:** prepared objects select addition or multiplication
  through a virtual, interface, trait, or function-pointer call.
- **Enum dispatch:** prepared records contain an operation tag, and the timed
  loop selects addition or multiplication with a switch or branch.

These are complete-workload comparisons, not isolated measurements of one
dispatch instruction. Their representations, traversal costs, optimizer
decisions, and generated code can differ. The exact contracts are in
[`agent-tasks/`](agent-tasks/), and the shared measurement rules are in
[`agent-rules/`](agent-rules/).

Tasks 1.x, 2.x, and 3.1 are implemented and analyzed. Task 4.1's
[Java RSS-memory workload](java-memory-test/) is implemented, with the
measurement matrix narrowed to five selected heap profiles and three trials.
Its full container collection and analysis have not been completed. See the
[task execution matrix](agent-tasks/task-execution.md) for current status.

## Evidence map

| Subject | Workload | Analysis | Raw evidence | Commands |
| --- | --- | --- | --- | --- |
| Tasks 1.1–1.2: virtual-dispatch implementation and timing | [`virtual-dispatch-test/`](virtual-dispatch-test/) | [Timing analysis](reports/virtual-dispatch-test.md) | [`reports/virtual-dispatch-test/`](reports/virtual-dispatch-test/) | [Virtual-dispatch README](virtual-dispatch-test/README.md) |
| Task 1.3: virtual-dispatch generated code | [`virtual-dispatch-test/`](virtual-dispatch-test/) | [Generated-code analysis](reports/virtual-dispatch-test-assembly.md) | [`reports/virtual-dispatch-test/assembly/`](reports/virtual-dispatch-test/assembly/) | [Assembly instructions](virtual-dispatch-test/README.md#capture-assembly-diagnostics) |
| Tasks 2.1–2.2: enum-dispatch implementation and timing | [`enum-dispatch-test/`](enum-dispatch-test/) | [Timing analysis](reports/enum-dispatch-test.md) | [`reports/enum-dispatch-test/`](reports/enum-dispatch-test/) | [Enum-dispatch README](enum-dispatch-test/README.md) |
| Tasks 2.3–2.4: enum generated code and vectorization | [`enum-dispatch-test/`](enum-dispatch-test/) | [Generated-code analysis](reports/enum-dispatch-test-assembly.md) | [`reports/enum-dispatch-test/assembly/`](reports/enum-dispatch-test/assembly/) | [Assembly and vectorization instructions](enum-dispatch-test/README.md#capture-assembly-diagnostics) |
| Task 3.1: matched virtual-versus-enum validation | Both workloads | [Matched five-trial analysis](reports/dispatch-differences-analysis.md) | [`reports/task-3.1/dispatch-validation-001/`](reports/task-3.1/dispatch-validation-001/) | [Collection script](task-scripts/3.1-collect.sh) |

The Markdown analyses are the entry points for results. The directories contain
the underlying target CSVs and run logs; assembly directories additionally
contain the exact diagnostic command, manifest, standard error, and raw output
where retained. Diagnostic timings are not performance measurements and are
not included in the timing CSV comparisons.

## Workloads

Both workloads prepare their data outside the timed region. One timed sample
runs the full prepared collection for the requested number of repeats and
accumulates a wrapping signed 32-bit checksum.

For virtual dispatch, each inner iteration invokes the selected operation's
`process` behavior. Its reported time includes collection traversal, dynamic
dispatch or any optimized replacement, arithmetic, loop control, and checksum
accumulation.

For enum dispatch, each inner iteration reads an operation tag and selects the
addition or multiplication path directly. Its reported time includes record
traversal, tag loading and control flow, arithmetic, loop control, and checksum
accumulation.

Implementations use the language's specified random-number generator. A common
seed therefore produces the required operation and operand distributions, but
not necessarily byte-identical prepared sequences or checksums across all
languages. The workloads are equivalent under their task contracts rather than
source-identical.

## Targets

The same canonical target IDs are used in commands, artifacts, logs, and CSVs.

| Language and execution mode | Target ID |
| --- | --- |
| Java (Eclipse Temurin, HotSpot C2 JIT) | `temurin-c2` |
| Java (GraalVM JIT) | `graalvm-jit` |
| Java (GraalVM Native Image AOT) | `graalvm-native` |
| C++ (GCC) | `cpp-gcc` |
| C++ (Clang) | `cpp-clang` |
| C (GCC) | `c-gcc` |
| C (Clang) | `c-clang` |
| Rust (rustc) | `rust` |
| Go (standard toolchain) | `go` |
| Python (CPython) | `cpython` |
| C# (.NET CoreCLR JIT) | `coreclr` |
| C# (.NET Native AOT) | `dotnet-native` |
| JavaScript (Node.js/V8 JIT) | `node-v8` |

JIT targets optimize while the process runs; the captured Java JIT and
JavaScript JIT listings include tiering or OSR transitions. Native AOT and
conventional native targets execute code produced before launch. These modes
have different warmup and code-generation behavior and should not be treated
as interchangeable merely because they implement the same workload.

## What the current results support

The original [virtual-dispatch](reports/virtual-dispatch-test.md) and
[enum-dispatch](reports/enum-dispatch-test.md) timing analyses each contain one
fresh-process trial per target. They retain slow samples and transitions, but
their measured source rows remain `unclassified`; a later descriptive
stability check does not silently turn those rows into source
`steady_state` data. Those reports are useful observations from their recorded
host and configuration, not general language rankings.

The [Task 3.1 matched analysis](reports/dispatch-differences-analysis.md) is the
preferred virtual-versus-enum comparison for C, C++, and Java. It uses the same
workload settings and five fresh-process trials for each target:

- Java (Eclipse Temurin, HotSpot C2) is effectively tied across the two
  complete workloads at the target-level median. Java (GraalVM JIT) shows a
  small, repeatable enum advantage, and Java (GraalVM Native Image) shows a
  somewhat larger but still modest and consistent enum advantage.
- Both C++ compiler targets show a materially larger enum advantage in every
  paired trial, although several enum trials do not pass the conservative
  final-window stability check.
- C (Clang) shows the largest separation because the captured enum loop uses
  branchless SIMD while its virtual loop retains an indirect function-pointer
  call. C (GCC) is less conclusive because one retained enum trial reverses the
  usual direction.

These comparisons still do not measure the latency of one indirect call. In
particular, the generated-code evidence shows that Java (Eclipse Temurin,
HotSpot C2) and Java (GraalVM JIT) use guarded polymorphic inlining and direct
arithmetic in the captured optimized virtual hot paths. Their comparison is
not simply “indirect call versus enum branch.” Java (GraalVM Native Image)
retains an indirect interface call in the captured diagnostic build, while its
enum implementation retains iterator and object machinery.

The [enum generated-code analysis](reports/enum-dispatch-test-assembly.md)
shows branchless SIMD enum loops for Rust and C compiled with Clang in the
captured configuration. GCC's C and C++ loops, C++ compiled with Clang, Go,
and the captured C# (.NET CoreCLR) optimized loop remain scalar and branch on
the tag. These code shapes help explain complete-workload observations; an
instruction listing alone does not measure execution frequency or establish
the cost of one instruction.

One compiler question remains unresolved. Clang reports the C loop as
profitable to vectorize at width 4 with interleave count 2 and reports the C++
loop as not beneficial. Its published optimization remarks do not identify the
specific C++ intermediate-representation operation responsible for that cost
decision. Controlled C++ variants or deeper LLVM cost-model diagnostics are
still needed. The GCC pair also shows that the measured split is not an
inherent C-versus-C++ performance property.

## Quick start

### Prerequisites

Use Linux with Bash and either Docker Engine or Podman. Container builds pin
their base images and toolchains; native workflows additionally require the
matching compilers and runtimes on the host. CPU affinity uses Docker's
`--cpuset-cpus` where available or host `taskset` for rootless Podman, so the
selected logical CPU must be available.

The following example builds and runs Java (Eclipse Temurin, HotSpot C2) for
the virtual-dispatch workload. Choose a new run ID and an unused output
directory for each collection.

```sh
./virtual-dispatch-test/java/build.sh --target temurin-c2

./virtual-dispatch-test/java/run.sh \
  --target temurin-c2 \
  --size 100000 --seed 42 --repeats 100 --value 7 \
  --warmup-samples 10 --samples 30 \
  --output ./results/virtual-dispatch-test \
  --run-id my-virtual-run-001 --trial 1 --config-id default
```

Scripts use `docker` by default. To invoke Podman directly, set the same engine
for both build and run commands:

```sh
CONTAINER_ENGINE=podman ./virtual-dispatch-test/java/build.sh \
  --target temurin-c2

CONTAINER_ENGINE=podman ./virtual-dispatch-test/java/run.sh \
  --target temurin-c2 \
  --size 100000 --seed 42 --repeats 100 --value 7 \
  --warmup-samples 10 --samples 30 \
  --output ./results/virtual-dispatch-test \
  --run-id my-virtual-podman-run-001 --trial 1 --config-id default
```

The scripts also detect when the `docker` command is Podman's compatibility
wrapper and record Podman as the actual runtime. Keep Docker Engine, Podman,
and native-host results in separate comparison groups even if the generic CSV
execution label is `docker`.

See the [virtual-dispatch instructions](virtual-dispatch-test/README.md) and
[enum-dispatch instructions](enum-dispatch-test/README.md) for all-target,
native, assembly, and vectorization-diagnostic workflows.

### Repeat the matched Task 3.1 collection

Run the matched C, C++, and Java comparison from the repository root. Replace
the example with a comparison ID that has never been used; the script refuses
to overwrite an existing output directory.

```sh
./task-scripts/3.1-collect.sh dispatch-validation-002
```

This performs 14 builds and 70 sequential measured runs. Avoid compilation,
interactive agent work, or other substantial host activity until collection
finishes because competing load can affect scheduling, shared caches, memory
bandwidth, temperature, and turbo frequency. The script uses the
Docker-compatible `docker` command and automatically follows a Podman
compatibility wrapper when that is what the command provides.

## Outputs and interpretation

Normal timing runs write one `<target-id>-report.csv` plus target/run logs
beneath `reports/<workload>-test/` by default. Task 3.1 writes its two workload
sets beneath `reports/task-3.1/<comparison-id>/`. Generated-code captures live
under `reports/<workload>-test/assembly/<target-id>/<execution-mode>/<diagnostic-run-id>/`.
The human-readable analyses are the top-level Markdown files in
[`reports/`](reports/).

CSV phases have literal meanings. `warmup` contains requested warmup windows;
`unclassified` contains retained measured windows that were not proven stable
under a predefined collection-time criterion. Analyses may apply a documented
descriptive check, but preserve the source phase and keep startup, warmup,
unclassified, and steady-state data separate.

Current conclusions are limited to the recorded hosts, architectures,
toolchains, execution engines, inputs, and resource controls. Some original
runs lack complete runtime-feature provenance or compilation diagnostics, and
some diagnostic artifacts differ from measured binaries to retain symbols.
The assembly reports document those cases individually.

Most importantly, no current control holds the flat data representation,
traversal, and loop body constant while changing only the dispatch expression.
The next performance follow-up proposed by
[Task 3.1](agent-tasks/3.1-validate-dispatch-difference.md) is such a controlled
benchmark, ideally with hardware branch, cache, and cycle counters. Until then,
the results support claims about these complete workloads, not a universal
cost for virtual or enum dispatch.

## Repository guide

- [`agent-tasks/`](agent-tasks/) contains task specifications and acceptance
  criteria.
- [`agent-rules/`](agent-rules/) contains shared target, runner, reporting,
  analysis, and generated-code rules.
- [`virtual-dispatch-test/`](virtual-dispatch-test/) and
  [`enum-dispatch-test/`](enum-dispatch-test/) contain implementations and
  orchestration scripts.
- [`task-scripts/`](task-scripts/) contains cross-workload collection scripts.
- [`reports/`](reports/) contains raw evidence and human-readable analysis.

See [LICENSE](LICENSE) for licensing terms.
