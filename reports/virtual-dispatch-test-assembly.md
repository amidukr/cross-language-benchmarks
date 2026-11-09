# Virtual dispatch generated-code analysis

## Scope and evidence

This report analyzes diagnostic run `assembly-001` for the Task 1.1 case
`size=100000`, `seed=42`, `repeats=100`, `value=1`, with 5 requested warmup
samples and 20 requested samples. The diagnostic commands are recorded beside
each raw file. They are separate from the clean timing runs and none of their
timings are used here.

All captures were invoked through the `docker` command, but every manifest
records `podman version 5.7.0` as the engine version and stderr says that Podman
was emulating the Docker CLI. The artifacts and manifests use the directory and
execution-mode label `docker`; the actual engine was Podman. This provenance
disagreement prevents treating the directory label as proof of a Docker run.

The C, C++, Rust, Go, and AOT captures are static disassemblies. The configured
compiler/runtime versions come from their pinned build images: GCC 15.2.0,
Clang 21, Rust 1.90.0, Go 1.25.3, GraalVM Native Image 25.0.1, and .NET SDK
10.0.403 Native AOT. The runtime diagnostics identify Temurin 25.0.1+8,
GraalVM 25.0.1+8-jvmci-b01, .NET 10.0.14, Node 26.0.0 with V8
14.6.202.33-node.19, and CPython 3.14.0. The manifests do not contain artifact
hashes or diagnostic-tool versions, so exact artifact identity and decoder
provenance cannot be reconstructed from this collection.

The checksum is `90108500` for implementations using the shared SplitMix-like
generator and `90028900` for Java's `SplittableRandom`. Task 1.1 permits each
language to use its standard generator, so the generated type/operand sequence
need not be identical even with the same seed.

## Target comparison

| Target | Evidence and configuration | Observed dispatch in the hot loop | Capture assessment |
| --- | --- | --- | --- |
| `c-gcc` | GNU `objdump`, GCC 15.2.0, CMake Release | Inlined `run` in `main`; function pointer loaded from each 16-byte record and called indirectly; returned 32-bit value added to the checksum | Usable |
| `c-clang` | `llvm-objdump`, Clang 21, CMake Release | Same record-function-pointer indirect call as GCC | Usable |
| `cpp-gcc` | GNU `objdump`, GCC 15.2.0, CMake Release | Inlined `run`; object pointer loaded, vptr loaded, then indirect call through vtable slot 0 | Usable |
| `cpp-clang` | `llvm-objdump`, Clang 21, CMake Release | Same vtable dispatch as GCC; no devirtualization in the captured hot loop | Usable |
| `rust` | GNU `objdump`, Rust 1.90.0 release with LTO | Inlined `run`; data pointer and vtable pointer loaded from each 16-byte trait object, then indirect call through vtable offset `0x18` | Usable |
| `go` | `go tool objdump`, Go 1.25.3 assembly build with symbols retained | `main.run`; interface itab and data loaded, method pointer loaded from itab offset `0x18`, indirect `CALL CX`, then 32-bit `ADDL` | Usable |
| `temurin-c2` | HotSpot `PrintAssembly`, Temurin 25.0.1+8 | C1 begins with interface dispatch; level-4 C2 OSR uses receiver-class guards for `AddOperation`/`MulOperation`, inlines operand loads and add/multiply, and retains uncommon-trap fallback paths | Usable; C1 and C2/OSR captured |
| `graalvm-jit` | HotSpot/JVMCI `PrintAssembly`, GraalVM 25.0.1+8-jvmci-b01 | Level-4 JVMCI OSR uses guarded polymorphic inlining of both operation classes, with direct operand arithmetic and deoptimization paths | Usable; C1 and JVMCI/OSR captured |
| `graalvm-native` | GNU `objdump`, Native Image 25.0.1 `-O3` | Not determined: the 71.7 MB listing has no workload symbol or reliable address-to-source mapping | Command succeeded, evidence incomplete |
| `cpython` | CPython 3.14 bytecode via `dis` | `LOAD_ATTR process`, generic `CALL`, generic integer `BINARY_OP +`, then call to `i32`; process bodies load `operand` and use `BINARY_OP +` or `*` | Usable baseline bytecode; not warmed/specialized |
| `coreclr` | `DOTNET_JitDisasm=Program:Run`, .NET 10.0.14 Release | Instrumented Tier 0 profiles receiver classes and uses an interface call; Tier1 OSR still uses an indirect `IOperation.Process` interface call and 32-bit accumulation | Usable; Tier 0 and Tier1 OSR captured |
| `dotnet-native` | GNU `objdump`, .NET SDK 10.0.403 Native AOT | Not determined: the 25.5 MB stripped listing exposes no `Program.Run`, interface, or operation symbols and has no reliable address-to-source mapping | Command succeeded, evidence incomplete |
| `node-v8` | V8 `--print-opt-code --trace-opt --trace-deopt`, Node 26.0.0 / V8 14.6 | TurboFan OSR guards the two receiver maps and the two `process` function identities, then inlines add/multiply fast paths; mismatches branch to deoptimization exits | Usable; Maglev/TurboFan transitions and TurboFan code captured |

“Usable” means that the requested hot region can be identified in the raw
evidence. It does not mean that the diagnostic listing proves which version
executed during any clean timing sample.

## Native indirect dispatch

### C

GCC inlines `run` into `main`. The inner loop passes the record address and
value, calls the function pointer at offset zero, advances by 16 bytes, and
adds the returned low 32 bits:

```text
4019a0: mov    %r14,%rdi
4019a3: mov    %r12d,%esi
4019aa: call   *(%r14)
4019ad: add    $0x10,%r14
4019b1: add    %eax,%ebx
```

This is visible in the [GCC C listing](virtual-dispatch-test/assembly/c-gcc/docker/assembly-001/raw.txt#L638).
The two possible callees load the operand at record offset 8 and use `add` or
`imul` ([GCC C callees](virtual-dispatch-test/assembly/c-gcc/docker/assembly-001/raw.txt#L1133)).

Clang emits the same structure: `callq *(%r12)`, `addl %eax,%r14d`, and a
16-byte record stride in the [Clang C hot loop](virtual-dispatch-test/assembly/c-clang/docker/assembly-001/raw.txt#L891).
Its callees likewise load offset 8 and perform 32-bit add/multiply in the
[Clang C listing](virtual-dispatch-test/assembly/c-clang/docker/assembly-001/raw.txt#L1184).
Because x86 32-bit `add` and `imul` retain the low 32 bits, the code implements
the required wrapping checksum without an extra masking instruction.

### C++

GCC loads an object pointer, loads its vptr, and calls vtable slot zero before
accumulating the return value:

```text
403a40: mov    (%r15),%rdi
403a45: mov    (%rdi),%rax
403a48: call   *(%rax)
403a4e: add    %eax,%ebx
```

See the [GCC C++ hot loop](virtual-dispatch-test/assembly/cpp-gcc/docker/assembly-001/raw.txt#L1717).
The out-of-line `Add::process` and `Mul::process` bodies load operand offset 8
and perform `add`/`imul` ([GCC C++ callees](virtual-dispatch-test/assembly/cpp-gcc/docker/assembly-001/raw.txt#L5511)).

Clang has the same vptr call and 32-bit accumulator in the
[Clang C++ hot loop](virtual-dispatch-test/assembly/cpp-clang/docker/assembly-001/raw.txt#L2272),
with corresponding [Clang C++ callees](virtual-dispatch-test/assembly/cpp-clang/docker/assembly-001/raw.txt#L6965).
Neither listing contains a type guard or direct call in the timed loop.

### Rust

The release build inlines `run` into `virtual_dispatch::main`. Each
`Box<dyn Operation>` is represented in the slice by a data pointer and vtable
pointer. The hot loop loads both, passes the value, and calls vtable offset
`0x18`:

```text
16b00: mov    (%r14),%rdi
16b03: mov    0x8(%r14),%rax
16b07: mov    %r15d,%esi
16b0a: call   *0x18(%rax)
16b0d: add    $0x10,%r14
16b11: add    %eax,%ebx
```

See the [Rust hot loop](virtual-dispatch-test/assembly/rust/docker/assembly-001/raw.txt#L3834).
The concrete [Rust process bodies](virtual-dispatch-test/assembly/rust/docker/assembly-001/raw.txt#L1780)
load the operand through the data pointer and perform 32-bit `add` or `imul`.

### Go

Go retains a separately named `main.run`. The interface value supplies an itab
and data pointer; the method pointer is loaded from itab offset `0x18`:

```text
main.go:130  MOVQ 0(AX), CX
main.go:130  MOVQ 0x8(AX), AX
main.go:131  MOVQ 0x18(CX), CX
main.go:131  MOVL SI, BX
main.go:131  CALL CX
main.go:131  ADDL AX, DX
```

See the [Go `main.run` listing](virtual-dispatch-test/assembly/go/docker/assembly-001/raw.txt#L195650).
The concrete process functions are a single `ADDL` or `IMULL` followed by
return ([Go process bodies](virtual-dispatch-test/assembly/go/docker/assembly-001/raw.txt#L194814)).

## Managed JIT dispatch

### HotSpot C2

The diagnostic stream first records a level-3 C1 OSR compilation of `run`, then
a level-4 C2 OSR compilation and invalidation of the lower-level OSR version
([HotSpot compilation events](virtual-dispatch-test/assembly/temurin-c2/docker/assembly-001/raw.txt#L12985)).

The C2 OSR body contains receiver-class checks for both concrete records. On
the multiply path it loads operand offset `0x0c`, performs `imul`, and adds the
result to the checksum:

```text
; VirtualDispatch$MulOperation::process@2
; VirtualDispatch::run@45
... 458b 5a0c | 440f af5c | 2404 4403
```

The add path is also inlined after an `AddOperation` metadata guard and loads
the same operand field before direct addition. These paths and their uncommon
trap fallback are in the [HotSpot C2 OSR listing](virtual-dispatch-test/assembly/temurin-c2/docker/assembly-001/raw.txt#L13637),
with the multiply and add source mappings at [line 13673](virtual-dispatch-test/assembly/temurin-c2/docker/assembly-001/raw.txt#L13673)
and [line 13823](virtual-dispatch-test/assembly/temurin-c2/docker/assembly-001/raw.txt#L13823).
Thus the optimized hot path is guarded polymorphic inlining, not an interface
call on every iteration.

### GraalVM JIT

The stream records C1 level-3 code, a level-4 JVMCI OSR compilation, an uncommon
trap that makes that version not entrant, and a later level-4 JVMCI OSR
recompilation ([GraalVM compilation events](virtual-dispatch-test/assembly/graalvm-jit/docker/assembly-001/raw.txt#L32213)).

The JVMCI OSR listing compares receiver metadata for the two record classes.
Matching paths inline operand loads and `imul`/`iadd`; nonmatching states lead
to lookup, uncommon-trap, or deoptimization stubs. The annotated multiply and
add paths are visible in the [GraalVM OSR listing](virtual-dispatch-test/assembly/graalvm-jit/docker/assembly-001/raw.txt#L34225),
including multiply at [line 34363](virtual-dispatch-test/assembly/graalvm-jit/docker/assembly-001/raw.txt#L34363)
and add at [line 34496](virtual-dispatch-test/assembly/graalvm-jit/docker/assembly-001/raw.txt#L34496).

### CoreCLR

Instrumented Tier 0 loads each array receiver, updates class-profile counters,
and invokes `IOperation.Process` indirectly:

```text
mov      rdi, gword ptr [rbp-0x60]
call     CORINFO_HELP_CLASSPROFILE32
...
call     [r11]IOperation:Process(int):int:this
add      eax, dword ptr [rbp-0x3C]
```

See the [Tier 0 listing](virtual-dispatch-test/assembly/coreclr/docker/assembly-001/raw.txt#L1)
and call site at [line 57](virtual-dispatch-test/assembly/coreclr/docker/assembly-001/raw.txt#L57).
The captured Tier1 OSR version still loads an interface-call cell into `r11`,
calls through it, and adds the returned 32-bit value; no inlined Add/Mul body or
receiver guard is present in this version ([Tier1 OSR listing](virtual-dispatch-test/assembly/coreclr/docker/assembly-001/raw.txt#L118),
[call site](virtual-dispatch-test/assembly/coreclr/docker/assembly-001/raw.txt#L155)).

### V8

The trace shows `run` entering Maglev through OSR, then TurboFan OSR
compilation, with deoptimizations and a later TurboFan recompilation
([V8 transitions](virtual-dispatch-test/assembly/node-v8/docker/assembly-001/raw.txt#L4865)).

TurboFan's `run` code compares the receiver map against the two observed maps,
selects the corresponding `process` function identity, checks that identity,
then executes an inlined arithmetic path. For example:

```text
cmpq r9,r11                 ; first receiver map
...
cmpq r15,r9                 ; second receiver map
...
movq r14,<process function>
cmpq r14,r15                ; expected process identity
...
addl r9,r12                 ; inlined add path
```

See the [TurboFan OSR block](virtual-dispatch-test/assembly/node-v8/docker/assembly-001/raw.txt#L5512),
especially its receiver/function guards at [line 5575](virtual-dispatch-test/assembly/node-v8/docker/assembly-001/raw.txt#L5575).
Guard failures branch to recorded deoptimization exits. The listing therefore
supports guarded polymorphic inlining, while the trace also shows that multiple
optimized versions and deoptimizations occurred during this diagnostic process.

## CPython bytecode

The `run` bytecode iterates the operation list, performs `LOAD_ATTR process`,
issues a generic one-argument `CALL`, adds with `BINARY_OP +`, and calls `i32`
to enforce signed 32-bit wrapping ([CPython `run`](virtual-dispatch-test/assembly/cpython/docker/assembly-001/raw.txt#L23)).
`AddOperation.process` and `MulOperation.process` load `self.operand`, execute
generic `BINARY_OP +` or `BINARY_OP *`, and call `i32`
([process bytecode](virtual-dispatch-test/assembly/cpython/docker/assembly-001/raw.txt#L78)).

Although `dis` was requested with `adaptive=True`, the collection command only
loaded the module and disassembled the functions; it did not warm them first.
The zero versions and low cache counters show that this is baseline adaptive
bytecode, not a post-warmup specialized form. It is sufficient to identify the
lookup and call mechanism but not to characterize CPython's warmed adaptive
specializations.

## Incomplete AOT captures

The GraalVM Native Image and .NET Native AOT commands both exited successfully
and produced nonempty full-binary disassemblies. However, their raw files do
not expose `run`, `Program.Run`, `VirtualDispatch`, `Operation`, or the concrete
operation names. There is no symbol/address map connecting an anonymous range
to the timed loop. Under the assembly-analysis rule, a successful decoder exit
without identification of the requested hot region is incomplete evidence.

- [GraalVM Native raw listing](virtual-dispatch-test/assembly/graalvm-native/docker/assembly-001/raw.txt#L1)
- [.NET Native AOT raw listing](virtual-dispatch-test/assembly/dotnet-native/docker/assembly-001/raw.txt#L1)

A future diagnostic build should retain symbols or emit a linker map while
recording that difference from the measured artifact. No dispatch conclusion
is made for these two targets from the current anonymous listings.

## Conclusions and limitations

The static native implementations that retain identifiable code all preserve
dynamic dispatch in the hot loop: a C function pointer, C++ vtable slot, Rust
trait-object vtable slot, or Go interface itab slot. Their concrete callees use
32-bit add/multiply and their callers use 32-bit checksum addition, naturally
retaining the low 32 bits on x86-64.

HotSpot C2, GraalVM JVMCI, and V8 instead produce guarded paths for the two
observed receiver types and inline the concrete arithmetic, with uncommon-trap
or deoptimization fallbacks. The captured CoreCLR Tier1 OSR version retains an
interface call. These are observations about separate diagnostic processes;
they do not prove which generated version executed during a clean timing
sample, how frequently each path ran, or that one dispatch mechanism caused a
timing difference.

No Task 1.2 timing values are compared here. Such a comparison would also need
matched host, execution engine, resource controls, exact artifacts, and clean
runtime settings. The current manifests omit artifact hashes, diagnostic-tool
versions, flags/environment details, and mislabel the Podman shim as Docker.
Those omissions limit reproducibility but do not change the instruction-level
conclusions for the eleven identifiable captures.
