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

The separate `enum-vectorization-001` diagnostic build supplies GCC's direct
reason for this outcome. GCC 15.2 reports `unsupported control flow in loop`
for both the outer and inner timed loops in C
(`c-gcc/docker/enum-vectorization-001/raw.txt`, lines 32–35)
and for the corresponding C++ loops
(`cpp-gcc/docker/enum-vectorization-001/raw.txt`, lines 902–905).
Thus GCC did not if-convert this ADD/MUL switch into a vector mask operation in
either language. The diagnostic identifies the rejected construct, but does
not say whether a small source rewrite would enable GCC's vectorizer.

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

#### Vectorization diagnostics

Task 2.4 adds diagnostic run `enum-vectorization-001` for all four C and C++
targets using diagnostic profile `vectorization`. These builds preserve the
Release optimization settings `-O3 -DNDEBUG` and add compiler reporting flags.
GCC 15.2 uses:

```text
-fopt-info-vec-all=/src/vectorization.txt
```

Clang 21 uses:

```text
-Rpass=loop-vectorize
-Rpass-missed=loop-vectorize
-Rpass-analysis=loop-vectorize
-fsave-optimization-record
-foptimization-record-file=/src/vectorization.yaml
```

The GCC flag records optimized, missed, and analysis notes from its vectorizer.
The Clang flags record successful, missed, and explanatory loop-vectorizer
remarks plus the complete YAML optimization record. Each capture also
disassembles the linked diagnostic executable so the remarks can be checked
against generated code. These reporting-enabled builds are diagnostic
artifacts, not the binaries used for Task 2.2 timing, and no timings from them
are used here.

GCC gives the same direct reason for the timed inner loop in C and C++:

```text
/src/c/main.c:133:28: missed: couldn't vectorize loop
/src/c/main.c:133:28: missed: not vectorized: unsupported control flow in loop.

/src/cpp/main.cpp:122:29: missed: couldn't vectorize loop
/src/cpp/main.cpp:122:29: missed: not vectorized: unsupported control flow in loop.
```

Clang reports opposite profitability decisions for the two source forms:

```text
../c/main.c:133:5: remark: vectorized loop (vectorization width: 4, interleaved count: 2) [-Rpass=loop-vectorize]

../cpp/main.cpp:122:5: remark: the cost-model indicates that vectorization is not beneficial [-Rpass-missed=loop-vectorize]
../cpp/main.cpp:122:5: remark: the cost-model indicates that interleaving is not beneficial [-Rpass-missed=loop-vectorize]
```

The excerpts come from the locally generated `enum-vectorization-001/raw.txt`
files. The large vectorization output directories are excluded from Git, so
the exact decisive compiler output is retained here to keep the published
report self-contained.

The `enum-vectorization-001` compiler remarks make the Clang distinction more
precise. For C, Clang 21 explicitly reports that the inner loop was vectorized
with vectorization width 4 and interleave count 2
(`c-clang/docker/enum-vectorization-001/raw.txt`, line 81).
This agrees with the eight-record main loop in the disassembly. For C++, Clang
does not report an illegal iterator, unsupported switch, or other legality
failure at the timed loop. It instead reports that its cost model considers
both vectorization and interleaving not beneficial
(`cpp-clang/docker/enum-vectorization-001/raw.txt`, lines 224–227).
In other words, Clang formed or considered vector plans but selected scalar
execution as the estimated cheapest plan for this C++ intermediate
representation.

This is the best-supported answer to why C was much faster than C++ in the
Clang results. The clean run observed 8.478 versus 71.809 ms/op. The assembly
shows that C performs eight branchless SIMD decisions at a
time, while C++ performs scalar conditional decisions over a random-looking
50/50 tag stream. Unpredictable branches are a plausible additional cost, but
the listings alone do not measure branch misses. The compiler remarks explain
the immediate decisions—Clang found C profitable and C++ unprofitable—but not
why its estimated costs differ so sharply for these logically equivalent
loops. In particular, the ordinary remarks contain no per-instruction scalar
and vector cost breakdown. Controlled C++ variants (`const auto&`, indexed
access, and raw pointer plus size), optionally forced-vector diagnostic builds,
or LLVM internal cost-model debugging are still needed to isolate the decisive
IR or cost estimate. This remaining question must not be presented as solved.
The GCC pair demonstrates that the measured gap is a compiler/source-form
outcome, not an inherent C-versus-C++ performance property.

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

### Relationship to C++ performance

The clean Task 2.2 medians were 60.735 ms/op for C++ with GCC, 71.809 ms/op
for C++ with Clang, 96.068 ms/op for Java with Eclipse Temurin/HotSpot C2,
106.103 ms/op for Java with GraalVM JIT, and 167.491 ms/op for Java with
GraalVM Native Image. These are complete-workload observations from one trial,
not measurements of cache misses or isolated iterator costs.

C++ stores each `Instruction` value directly in a contiguous `std::vector`.
The captured scalar loops can therefore obtain the tag and operand from one
eight-byte record before branching to add or multiply. For example, the
[C++/GCC loop](enum-dispatch-test/assembly/cpp-gcc/docker/enum-assembly-001/raw.txt#L1453)
loads both fields from the current record without following an object
reference.

Java's `ArrayList<Instruction>` instead contains a contiguous array of object
references. Each reference points to a separately allocated `Instruction`
record, whose operation field points to an enum object. This representation
has a larger working set and requires dependent reference loads before the
operand and ordinal are available. It therefore has less spatial locality than
the C++ value array. The listings establish the additional load chain, but do
not contain hardware-counter data proving how many cache misses it caused.

The Java JIT compilers remove much of the abstraction overhead without
changing that underlying object layout. HotSpot C2 inlines the `ArrayList`
iterator, record accessors, enum ordinal access, and arithmetic in the
[optimized Java region](enum-dispatch-test/assembly/temurin-c2/docker/enum-assembly-001/raw.txt#L10930).
The Java GraalVM JIT listing similarly contains the iterator checks, field
loads, switch, and arithmetic in one optimized body
([JVMCI region](enum-dispatch-test/assembly/graalvm-jit/docker/enum-assembly-001/raw.txt#L42735)).
Escape analysis can eliminate the short-lived iterator object and inlining can
remove calls, but neither captured JIT turns the `ArrayList` of separately
allocated records into a flat array of tag/operand values. Thus the JIT
versions retain the pointer-chasing/locality disadvantage while avoiding much
of the iterator call and allocation overhead.

The captured Java GraalVM Native Image code retains more machinery. It creates
an `ArrayList$Itr` for a pass and calls `ArrayList$Itr::next()` out of line
([Native Image iterator path](enum-dispatch-test/assembly/graalvm-native/docker/enum-assembly-001/raw.txt#L45),
[call site](enum-dispatch-test/assembly/graalvm-native/docker/enum-assembly-001/raw.txt#L75)).
It also retains iterator-state, type, safepoint, and allocation checks around
the scalar ordinal branch. This provides a code-generation explanation for why
Native Image can do more work than the two optimized JIT versions in this
case. It does not prove that any single check or cache effect accounts for a
specific fraction of the measured gap.

The comparison can therefore be summarized as:

```text
C++ value vector:
  contiguous tag/operand record -> scalar branch -> arithmetic

Java JIT ArrayList:
  reference array -> Instruction object -> enum/operand loads
  + mostly inlined/eliminated iterator machinery -> scalar branch -> arithmetic

Java Native Image ArrayList:
  same reference/object layout
  + retained iterator allocation/call and additional checks -> scalar branch -> arithmetic
```

This result is not evidence that Java JIT or Native Image is intrinsically
slower than C++ by these ratios. A controlled layout comparison would use Java
primitive tag and operand arrays, an indexed loop, fresh clean timing trials,
and preferably hardware counters. That would remove record-object pointer
chasing and test the compiler/runtime code generation on a representation
closer to the C++ `vector<Instruction>`.

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
similar speeds. The compiler diagnostics resolve one level of explanation:
GCC rejects both loops because of unsupported control flow, while Clang reports
C as profitable at width 4 with interleave count 2 and C++ as legal enough to
cost but not beneficial.

One important mystery remains unresolved. Clang's public optimization remarks
do not explain why the vector cost model reaches opposite profitability
decisions for the C and C++ source forms, nor which C++ IR operation accounts
for the estimated cost. Claims that the range iterator, value copy, switch, or
another particular construct is the cause would therefore be speculative.
Resolving it requires controlled C++ source variants and comparison of their
remarks and generated code; forced-vectorization or a debug LLVM cost trace can
then show whether Clang avoided genuinely expensive vector code or made a
conservative estimate. Any performance effect of such a rewrite requires new
clean timing trials separate from these diagnostic builds.

## Code under test

These examples include the operation/tag declarations needed to read the measured function.

### C

Source: [enum-dispatch-test/c/main.c](../enum-dispatch-test/c/main.c), declarations and function `run`.

```c
typedef enum { OP_ADD, OP_MUL } Operation;
typedef struct {
  Operation operation;
  int32_t operand;
} Instruction;

static int32_t run(const Instruction *ops, uint32_t size, uint32_t repeats,
                   int32_t value) {
  uint32_t sum = 0;
  for (uint32_t n = 0; n < repeats; n++)
    for (uint32_t i = 0; i < size; i++) {
      uint32_t operand = (uint32_t)ops[i].operand;
      switch (ops[i].operation) {
      case OP_ADD:
        sum += (uint32_t)value + operand;
        break;
      case OP_MUL:
        sum += (uint32_t)value * operand;
        break;
      }
    }
  return (int32_t)sum;
}
```

### C++

Source: [enum-dispatch-test/cpp/main.cpp](../enum-dispatch-test/cpp/main.cpp), declarations and function `run`.

```cpp
enum class Operation { Add, Mul };
struct Instruction {
  Operation operation;
  std::int32_t operand;
};

static std::int32_t run(const std::vector<Instruction> &ops,
                        std::uint32_t repeats, std::int32_t value) {
  std::uint32_t sum = 0;
  for (std::uint32_t n = 0; n < repeats; n++)
    for (auto instruction : ops) {
      auto operand = static_cast<std::uint32_t>(instruction.operand);
      switch (instruction.operation) {
      case Operation::Add:
        sum += static_cast<std::uint32_t>(value) + operand;
        break;
      case Operation::Mul:
        sum += static_cast<std::uint32_t>(value) * operand;
        break;
      }
    }
  return static_cast<std::int32_t>(sum);
}
```

### Java

Source: [enum-dispatch-test/java/EnumDispatch.java](../enum-dispatch-test/java/EnumDispatch.java), declarations and function `run`.

```java
  enum Operation { ADD, MUL }
  record Instruction(Operation operation, int operand) {}

  static int run(List<Instruction> operations, int repeats, int value) {
    int checksum = 0;
    for (int n = 0; n < repeats; n++)
      for (Instruction instruction : operations)
        checksum += switch (instruction.operation()) {
          case ADD -> value + instruction.operand();
          case MUL -> value *instruction.operand();
        };
    return checksum;
  }
```

### Rust

Source: [enum-dispatch-test/rust/src/main.rs](../enum-dispatch-test/rust/src/main.rs), declarations and function `run`.

```rust
#[derive(Clone, Copy)]
enum Operation {
    Add,
    Mul,
}
#[derive(Clone, Copy)]
struct Instruction {
    operation: Operation,
    operand: i32,
}

fn run(ops: &[Instruction], repeats: u32, value: i32) -> i32 {
    let mut sum = 0i32;
    for _ in 0..repeats {
        for instruction in ops {
            let result = match instruction.operation {
                Operation::Add => value.wrapping_add(instruction.operand),
                Operation::Mul => value.wrapping_mul(instruction.operand),
            };
            sum = sum.wrapping_add(result)
        }
    }
    sum
}
```

### Go

Source: [enum-dispatch-test/go/main.go](../enum-dispatch-test/go/main.go), declarations and function `run`.

```go
type Operation uint8

const (
	Add Operation = iota
	Mul
)

type Instruction struct {
	operation Operation
	operand   int32
}

func run(ops []Instruction, repeats int, value int32) int32 {
	var sum uint32
	for n := 0; n < repeats; n++ {
		for _, instruction := range ops {
			switch instruction.operation {
			case Add:
				sum += uint32(value) + uint32(instruction.operand)
			case Mul:
				sum += uint32(value) * uint32(instruction.operand)
			}
		}
	}
	return int32(sum)
}
```

### Python

Source: [enum-dispatch-test/python/enum_dispatch.py](../enum-dispatch-test/python/enum_dispatch.py), declarations and function `run`.

```python
class Operation(IntEnum):
    ADD = 0
    MUL = 1


@dataclass(frozen=True, slots=True)
class Instruction:
    operation: Operation
    operand: int

def run(operations, repeats, value):
    checksum = 0
    for _ in range(repeats):
        for instruction in operations:
            match instruction.operation:
                case Operation.ADD:
                    result = value + instruction.operand
                case Operation.MUL:
                    result = value * instruction.operand
            checksum = i32(checksum + result)
    return checksum
```

### C#

Source: [enum-dispatch-test/csharp/Program.cs](../enum-dispatch-test/csharp/Program.cs), declarations and function `Run`.

```csharp
enum Operation { Add, Mul }
readonly record struct Instruction(Operation Operation, int Operand);

  static int Run(Instruction[] ops, int repeats, int value) {
    var sum = 0;
    unchecked {
      for (var n = 0; n < repeats; n++)
        foreach (var instruction in ops)
          sum += instruction.Operation switch {
            Operation.Add => value + instruction.Operand,
            Operation.Mul => value * instruction.Operand,
            _ => throw new InvalidOperationException()
          };
    }
    return sum;
  }
```

### JavaScript

Source: [enum-dispatch-test/javascript/enum-dispatch.js](../enum-dispatch-test/javascript/enum-dispatch.js), declarations and function `run`.

```javascript
const Operation = Object.freeze({ADD : 0, MUL : 1});

    operations.push({
      operation : add ? Operation.ADD : Operation.MUL,
      operand,
    });

function run(operations, repeats, value) {
  let checksum = 0;
  for (let n = 0; n < repeats; n++)
    for (const instruction of operations) {
      let result;
      switch (instruction.operation) {
        case Operation.ADD:
          result = (value + instruction.operand) | 0;
          break;
        case Operation.MUL:
          result = Math.imul(value, instruction.operand);
          break;
        default:
          throw new Error('invalid operation');
      }
      checksum = (checksum + result) | 0;
    }
  return checksum;
}
```
