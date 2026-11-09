# Enum dispatch generated-code analysis

## Scope and evidence

This report analyzes diagnostic run `enum-assembly-001` for the Task 2.1
workload `size=100000`, `seed=42`, `repeats=100`, `value=7`, with 10 requested
warmup samples and 30 requested samples. These settings match the clean timing
run analyzed in [Task 2.2](enum-dispatch-test.md). Diagnostic timings are not
used. Every manifest reports a successful capture through the Docker-compatible
CLI and identifies Podman 5.7.0 as the actual engine.

The static captures use the performance optimization level. The Rust and Go
diagnostic artifacts retain symbols, and the Java GraalVM Native Image build
retains debug information and local symbols, so those are not byte-for-byte the
measured artifacts. JIT listings come from separate diagnostic processes and
show tier transitions rather than proving which tier ran during a clean timing
sample. All conclusions below are limited to these captured versions.

## Target comparison

| Target | Evidence / tier | Tag decision in the hot loop | Status |
| --- | --- | --- | --- |
| C (GCC) [`c-gcc`] | GCC 15.2, Release static disassembly | Scalar tag test and conditional branch; add/multiply paths | Usable |
| C (Clang) [`c-clang`] | Clang 21, Release static disassembly | Eight records per iteration; SSE2 multiply/add plus mask-based branchless selection; scalar tail | Usable |
| C++ (GCC) [`cpp-gcc`] | GCC 15.2, Release static disassembly | Scalar tag test and conditional branch; add/multiply paths | Usable |
| C++ (Clang) [`cpp-clang`] | Clang 21, Release static disassembly | Scalar, partially duplicated/unrolled branch paths; no SIMD | Usable |
| Rust (rustc) [`rust`] | Rust 1.90 release/LTO diagnostic artifact | Eight records per iteration; SIMD arithmetic and mask selection; branchless scalar tail | Usable |
| Go (standard toolchain) [`go`] | Go 1.25.3 symbol-retaining diagnostic artifact | Scalar conditional tag branches | Usable |
| Java (Eclipse Temurin, HotSpot C2) [`temurin-c2`] | Java 25.0.1, C1 then C2 OSR | Inlined iterator; scalar ordinal tests implementing the switch | Usable |
| Java (GraalVM JIT) [`graalvm-jit`] | Java 25.0.1, C1 then JVMCI level-4 OSR | Scalar ordinal comparisons with two-iteration duplication/unrolling | Usable |
| Java (GraalVM Native Image) [`graalvm-native`] | Java 25.0.1 Native Image `-O3`, symbol-retaining diagnostic build | Scalar enum ordinal comparisons; iterator `next` remains an out-of-line call | Usable |
| C# (.NET CoreCLR) [`coreclr`] | .NET 10.0.14, instrumented Tier 0 and Tier1 OSR | Tier1 scalar tag test/branch over packed 8-byte structs | Usable |
| C# (.NET Native AOT) [`dotnet-native`] | .NET SDK 10.0.403 static disassembly | Hot region not identifiable in the stripped 25 MB listing | Capture succeeded; evidence incomplete |
| JavaScript (Node.js/V8) [`node-v8`] | Node 26 / V8 14.6, Maglev then TurboFan OSR | TurboFan guards object maps, compares numeric tags, and branches to integer add/multiply paths | Usable |
| Python (CPython) [`cpython`] | CPython 3.14 `dis` bytecode | Attribute load, equality comparisons, conditional bytecode jumps, generic `+`/`*`, and `i32` call | Usable baseline bytecode; not warmed/specialized |

No usable hot loop contains virtual, interface, function-pointer, delegate, or
closure dispatch for the operation choice. The Java, C#, JavaScript, and Python
implementations still perform runtime object/iterator or interpreter work, but
the ADD/MUL choice itself is a tag comparison rather than dynamic method
dispatch.

## Native compiled loops

### C and C++ with GCC

GCC produces essentially the same scalar lowering for C and C++. The C loop
loads the operand and tag, tests the tag, and branches between multiply and add:

```text
mov    0x4(%rax),%ecx       # operand
mov    (%rax),%edx          # tag
test   %edx,%edx
je     add_path
imul   %r13d,%ecx           # MUL
...
add    %r13d,%ecx           # ADD
add    %ecx,%ebx            # wrapping 32-bit checksum
```

See the [C/GCC hot loop](enum-dispatch-test/assembly/c-gcc/docker/enum-assembly-001/raw.txt#L637).
The [C++/GCC hot loop](enum-dispatch-test/assembly/cpp-gcc/docker/enum-assembly-001/raw.txt#L1453)
has the same loads, tag branch, `imul`/`add`, and 32-bit accumulation. There is
no indirect call in either loop. This similarity agrees with their close Task
2.2 medians (61.832 and 60.735 ms/op respectively); it does not establish that
all remaining costs are identical.

### C and C++ with Clang

Clang's C result is fundamentally different. Its main loop loads eight
eight-byte records, rearranges operands into vectors, computes vector multiply
and add candidates, and selects with equality masks:

```text
movdqu   ...                # eight tag/operand records
pmuludq  ...                # MUL candidates
paddd    ...                # ADD candidates
pcmpeqd  ...                # tag masks
pand / pandn / por          # branchless selection
addq     $8,...             # eight records per iteration
```

The vector loads and arithmetic are in the [C/Clang loop](enum-dispatch-test/assembly/c-clang/docker/enum-assembly-001/raw.txt#L980),
and its mask selection and reduction are visible from
[line 1011](enum-dispatch-test/assembly/c-clang/docker/enum-assembly-001/raw.txt#L1011).
Only the scalar remainder uses tag branches.

The C++/Clang listing instead loads one tag and operand at a time and branches:

```text
cmpl   $1,(%rsi,%r14,8)
je     mul_path
cmpl   $0,(%rsi,%r14,8)
jne    invalid
addl   4(%rsi,%r14,8),%ebx
...
imull  4(%rsi,%r14,8),%eax
```

See the [C++/Clang scalar paths](enum-dispatch-test/assembly/cpp-clang/docker/enum-assembly-001/raw.txt#L2423),
especially the tag and operand operations at
[line 2440](enum-dispatch-test/assembly/cpp-clang/docker/enum-assembly-001/raw.txt#L2440).
The compiler duplicates some scalar paths, but emits no vector main loop.

This is the best-supported answer to why C was much faster than C++ in the
Clang results. The clean run observed 8.478 versus 71.809 ms/op. The assembly
shows that C performs eight branchless SIMD decisions at a
time, while C++ performs scalar conditional decisions over a random-looking
50/50 tag stream. Unpredictable branches are a plausible additional cost, but
the listings alone do not measure branch misses. A compiler-vectorization
remark or source-form control experiment would be needed to prove why Clang
accepted the C indexed loop but rejected the C++ range/iterator loop. The GCC
pair demonstrates that this is a compiler/source-form outcome, not an inherent
C-versus-C++ performance property.

### Rust and Go

Rust also processes eight records per vector iteration. It constructs tag
masks, loads operands, computes multiply and add candidates, and combines them
with `pand`, `pandn`, and `por`; the scalar tail uses `cmovne` rather than a
per-tag branch. See the [Rust vector body](enum-dispatch-test/assembly/rust/docker/enum-assembly-001/raw.txt#L3746)
and [mask selection](enum-dispatch-test/assembly/rust/docker/enum-assembly-001/raw.txt#L3796).
This code shape is consistent with Rust's lowest Task 2.2 median (6.782 ms/op),
but the timing still includes traversal and all arithmetic.

Go emits a scalar loop: it loads the tag and operand, tests the tag, and jumps
to either `ADDL` or `IMULL`, followed by 32-bit checksum addition. The relevant
source-mapped body begins in the [Go listing](enum-dispatch-test/assembly/go/docker/enum-assembly-001/raw.txt#L196061),
with the loads and decision at
[line 196093](enum-dispatch-test/assembly/go/docker/enum-assembly-001/raw.txt#L196093).

## Java generated code

### Eclipse Temurin / HotSpot C2

The stream contains an early C1 OSR compilation and an optimized C2 OSR
compilation. C2 inlines `ArrayList` iteration and record access, loads
`Instruction.operation`, loads the enum ordinal and operand, then implements
the two-case `lookupswitch` with scalar comparisons and branches:

```text
; getfield operation
; getfield ordinal
; getfield operand
... 83fa 01 0f84 ... 83fa 01 0f87 ...
; iadd
```

See the annotated [Java HotSpot C2 region](enum-dispatch-test/assembly/temurin-c2/docker/enum-assembly-001/raw.txt#L10935).
The add/multiply remain ordinary 32-bit Java integer operations, so overflow
wraps as required. There is no virtual operation call.

### GraalVM JIT

The Java GraalVM stream likewise progresses from C1 to JVMCI level-4 OSR. The
optimized version compares the ordinal against 0 and 1, branches to scalar
`imul` or add paths, and contains a second duplicated iteration rather than a
SIMD loop. The first decision and multiply are in the
[Java GraalVM JIT listing](enum-dispatch-test/assembly/graalvm-jit/docker/enum-assembly-001/raw.txt#L42758);
the duplicated second switch and multiply begin at
[line 42810](enum-dispatch-test/assembly/graalvm-jit/docker/enum-assembly-001/raw.txt#L42810).

### GraalVM Native Image

The focused Java Native Image symbol `EnumDispatch::run` retains an
`ArrayList$Itr::next()` call. After it obtains an `Instruction`, it loads the
operation reference and ordinal, loads the operand, compares the ordinal with
0 and 1, and branches to direct add or multiply:

```text
mov    0x10(...),%edi       # ordinal
mov    0x10(%rax),%ecx      # operand
cmp    $0,%edi
je     add_path
cmp    $1,%edi
jne    invalid
imul   %ecx,%edx            # MUL
...
add    %ecx,%edx            # ADD
```

See the [Java GraalVM Native loop](enum-dispatch-test/assembly/graalvm-native/docker/enum-assembly-001/raw.txt#L75)
and [tag/arithmetic block](enum-dispatch-test/assembly/graalvm-native/docker/enum-assembly-001/raw.txt#L97).
The out-of-line iterator and object representation help explain why this code
does more work than the flat native arrays, but assembly inspection does not
quantify each component.

## C#, JavaScript, and Python

CoreCLR first emits instrumented Tier 0 and then a smaller optimized Tier1 OSR
body. Tier1 treats each `Instruction` as an eight-byte struct, loads its tag and
operand, tests the tag, branches to add or multiply, and accumulates in a
32-bit register. See the [C# CoreCLR Tier1 OSR listing](enum-dispatch-test/assembly/coreclr/docker/enum-assembly-001/raw.txt#L146),
particularly the loads and decision at
[line 203](enum-dispatch-test/assembly/coreclr/docker/enum-assembly-001/raw.txt#L203).

The .NET Native AOT command succeeded, but the stripped listing exposes no
`Program.Run`, `Instruction`, or enum symbols and has no address-to-source map;
only the ELF identity is visible at the start of the
[C# Native AOT listing](enum-dispatch-test/assembly/dotnet-native/docker/enum-assembly-001/raw.txt#L1).
No dispatch-mechanism conclusion is made for that target.

V8 records Maglev OSR followed by TurboFan OSR for `run`. TurboFan's listing
contains object-map guards, loads the numeric operation property, compares the
two tag values, and branches into integer add or `Math.imul` paths, with
deoptimization exits for violated assumptions. The transition and source are
in the [JavaScript V8 trace](enum-dispatch-test/assembly/node-v8/docker/enum-assembly-001/raw.txt#L4799),
and the optimized guarded decision begins at
[line 4894](enum-dispatch-test/assembly/node-v8/docker/enum-assembly-001/raw.txt#L4894).
This is scalar specialized JavaScript code, not a virtual method call.

CPython bytecode performs `LOAD_ATTR operation`, loads `Operation.ADD`, uses
`COMPARE_OP` and `POP_JUMP_IF_FALSE`, and repeats the comparison for MUL. It
then loads `operand`, executes generic `BINARY_OP +` or `BINARY_OP *`, adds to
the checksum, and calls `i32` to enforce wrapping. See the
[Python CPython bytecode](enum-dispatch-test/assembly/cpython/docker/enum-assembly-001/raw.txt#L27),
the [two arithmetic paths](enum-dispatch-test/assembly/cpython/docker/enum-assembly-001/raw.txt#L61),
and [wrapping call](enum-dispatch-test/assembly/cpython/docker/enum-assembly-001/raw.txt#L122).
The capture is baseline `dis` output with empty adaptive caches, not warmed
specialized bytecode.

## Conclusions and limits

The clearest timing/code-generation relationship is the native vectorization
split: Rust and C/Clang have eight-wide branchless SIMD loops and are the two
fastest clean-run targets; GCC C/C++, C++/Clang, Go, and CoreCLR remain scalar
and branch on each tag. This is an observation across complete workloads, not
an isolated measurement of enum-dispatch cost.

In particular, C's large advantage over C++ is specific to the Clang code in
this experiment. Clang vectorized the C representation and did not vectorize
the C++ loop; GCC generated similar scalar code for both and measured them at
similar speeds. Establishing the precise optimizer inhibition would require a
matched source transformation (for example, indexed C++ access or equivalent
flat arrays) plus vectorization diagnostics and fresh clean timing trials.
