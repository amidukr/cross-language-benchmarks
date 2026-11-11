# Enum dispatch benchmark analysis

## Scope and inputs

This analysis uses the single container run `example-all-docker-001`. All
targets ran sequentially through the Docker-compatible CLI under Podman 5.7.0
on Linux 7.0.0-42-generic, x86-64, on an Intel Core i7-1255U. Host `taskset`
restricted every container to logical CPU 0; no memory limit was configured.
Although the logs retain `execution_mode=docker` and `container_engine=docker`,
the recorded engine output and `container_runtime=podman` identify this as one
Podman comparison group. No native or Docker-engine results are mixed into it.

The following source pairs were selected. All paths are relative to `reports/`.

| Target | CSV | Run log |
| --- | --- | --- |
| C (GCC) [`c-gcc`] | `enum-dispatch-test/c-gcc-report.csv` | `enum-dispatch-test/c-gcc-example-all-docker-001.log` |
| C (Clang) [`c-clang`] | `enum-dispatch-test/c-clang-report.csv` | `enum-dispatch-test/c-clang-example-all-docker-001.log` |
| C++ (GCC) [`cpp-gcc`] | `enum-dispatch-test/cpp-gcc-report.csv` | `enum-dispatch-test/cpp-gcc-example-all-docker-001.log` |
| C++ (Clang) [`cpp-clang`] | `enum-dispatch-test/cpp-clang-report.csv` | `enum-dispatch-test/cpp-clang-example-all-docker-001.log` |
| Java (Eclipse Temurin, HotSpot C2) [`temurin-c2`] | `enum-dispatch-test/temurin-c2-report.csv` | `enum-dispatch-test/temurin-c2-example-all-docker-001.log` |
| Java (GraalVM JIT) [`graalvm-jit`] | `enum-dispatch-test/graalvm-jit-report.csv` | `enum-dispatch-test/graalvm-jit-example-all-docker-001.log` |
| Java (GraalVM Native Image) [`graalvm-native`] | `enum-dispatch-test/graalvm-native-report.csv` | `enum-dispatch-test/graalvm-native-example-all-docker-001.log` |
| Rust (rustc) [`rust`] | `enum-dispatch-test/rust-report.csv` | `enum-dispatch-test/rust-example-all-docker-001.log` |
| Go (standard toolchain) [`go`] | `enum-dispatch-test/go-report.csv` | `enum-dispatch-test/go-example-all-docker-001.log` |
| Python (CPython) [`cpython`] | `enum-dispatch-test/cpython-report.csv` | `enum-dispatch-test/cpython-example-all-docker-001.log` |
| C# (.NET CoreCLR) [`coreclr`] | `enum-dispatch-test/coreclr-report.csv` | `enum-dispatch-test/coreclr-example-all-docker-001.log` |
| C# (.NET Native AOT) [`dotnet-native`] | `enum-dispatch-test/dotnet-native-report.csv` | `enum-dispatch-test/dotnet-native-example-all-docker-001.log` |
| JavaScript (Node.js/V8) [`node-v8`] | `enum-dispatch-test/node-v8-report.csv` | `enum-dispatch-test/node-v8-example-all-docker-001.log` |

## Validation and comparability

The 13 CSVs contain 520 data rows: 10 `warmup` and 30 `unclassified`
samples for each target. Every row uses schema version 2, benchmark
`enum-dispatch`, metric `time_per_op`, and unit `ns/op`. Within each trial,
sample indices are contiguous from 1 through 40 and elapsed time is strictly
increasing. There are no duplicate rows or trials, incomplete trials, missing
or extra targets, unsuccessful runs, or missing required fields. The two C#
CSVs begin with a UTF-8 byte-order mark; decoding them as UTF-8 with a
signature yields the required schema header.

Every log records `size=100000`, `seed=42`, `repeats=100`, `value=7`, 10
warmup samples, 30 measured samples, trial 1, configuration `default`, a
checksum, and exit status 0. Each benchmark operation is one complete call to
`run` and contains 10,000,000 tag-dispatch decisions. The C, C++, Rust, Go,
C#, and JavaScript implementations report checksum `373840100`; the three
Java targets report `375564700`; Python reports `376167700`. Task 2.1 permits
language-specific random-number generators, so those differences are expected:
the generated sequences need not be identical, but they use the same operation
and operand distributions and are treated as equivalent workloads.

The reports and logs identify exact toolchain versions and principal build or
runtime options. Some runtime provenance required for deeper interpretation is
not explicit: the logs do not record CPython GIL/JIT state, CoreCLR
ReadyToRun/Dynamic PGO state, or the Node.js module compile-cache state. No
diagnostic logs accompany this timing run. These omissions limit explanations
of runtime behavior but do not invalidate the recorded in-process comparison.

## Method

The primary result is `time_per_op` for the 30 source samples labeled
`unclassified`. The table reports each single trial's median and interquartile
range (IQR), calculated as the median of the upper half minus the median of the
lower half. No samples or spikes were excluded. Because there is only one
trial per target, these are within-trial summaries, not independent
replication.

Time per tag-dispatch decision is a derived descriptive metric:

```text
median ns/tag decision = median time_per_op / (100000 * 100)
```

It includes collection traversal, tag loading and control flow, integer
addition or multiplication, loop control, and wrapping checksum accumulation.
It is not an isolated measurement of tag-dispatch overhead.

Task 2.1 does not define a post-run stability criterion. For this analysis, a
trial demonstrates final-window stability only when it has at least 10
measured samples and, over its final 10 samples, both of the following hold:

1. The medians of the first and second consecutive five-sample windows differ
   by no more than 5% of the final-10 median.
2. The final-10 IQR is no more than 10% of the final-10 median.

This check does not relabel the source data. All 30 measured samples remain
`unclassified`; none are presented as source `steady_state` measurements.

## Results

| Target | Trials | Unclassified samples | Median (ms/op) | IQR (ms/op) | Median (ns/tag decision) | Stability check |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| Rust (rustc) [`rust`] | 1 | 30 | 6.782 | 0.094 | 0.678 | Yes |
| C (Clang) [`c-clang`] | 1 | 30 | 8.478 | 1.686 | 0.848 | Yes |
| C++ (GCC) [`cpp-gcc`] | 1 | 30 | 60.735 | 1.054 | 6.073 | Yes |
| C (GCC) [`c-gcc`] | 1 | 30 | 61.832 | 6.012 | 6.183 | Yes |
| C# (.NET Native AOT) [`dotnet-native`] | 1 | 30 | 70.527 | 4.810 | 7.053 | No |
| C++ (Clang) [`cpp-clang`] | 1 | 30 | 71.809 | 2.769 | 7.181 | Yes |
| C# (.NET CoreCLR) [`coreclr`] | 1 | 30 | 77.896 | 6.523 | 7.790 | Yes |
| Go (standard toolchain) [`go`] | 1 | 30 | 78.013 | 6.354 | 7.801 | Yes |
| Java (Eclipse Temurin, HotSpot C2) [`temurin-c2`] | 1 | 30 | 96.068 | 5.494 | 9.607 | Yes |
| Java (GraalVM JIT) [`graalvm-jit`] | 1 | 30 | 106.103 | 1.907 | 10.610 | Yes |
| JavaScript (Node.js/V8) [`node-v8`] | 1 | 30 | 118.879 | 3.777 | 11.888 | Yes |
| Java (GraalVM Native Image) [`graalvm-native`] | 1 | 30 | 167.491 | 3.397 | 16.749 | Yes |
| Python (CPython) [`cpython`] | 1 | 30 | 2275.403 | 26.677 | 227.540 | Yes |

The table is ordered by the unclassified-sample median. Rust has the lowest
complete-workload median in this single trial, followed by C compiled with
Clang. The large difference between the C Clang and C GCC results is an
observation about these complete compiled workloads; without generated-code
evidence or a matched control, this report does not assign it to tag dispatch,
vectorization, branching, layout, or another compiler decision. The same
caution applies to differences between languages and runtimes.

C# (.NET Native AOT) is the only trial that fails the stated check. Its two
final five-sample medians are 72.871 and 68.892 ms/op, a difference of about
5.6% of the final-10 median; the final-10 IQR is about 6.0%. The IQR condition
passes, but the consecutive-window condition does not. Its median is therefore
shown for completeness but should not be treated as a demonstrated stable
level.

The ordered samples also contain retained transitions and spikes. Java
(Eclipse Temurin, HotSpot C2) falls from 188.118 ms/op in its first warmup
sample to 97.630 ms/op in its tenth, while Java (GraalVM JIT) falls from
213.483 to 128.024 ms/op over the same warmup positions. Those shapes are
consistent with warmup, but without compilation diagnostics they do not
confirm JIT events. Among measured samples, C# (.NET CoreCLR) reaches 98.616
ms/op at sample 24, C++ (Clang) reaches 93.677 ms/op at sample 27, Java
(GraalVM Native Image) reaches 190.404 ms/op at sample 18, and Go reaches
91.566 ms/op at the final sample. All remain included in the summaries.

The within-language results are also single-trial observations. C with Clang
has a much lower median than C with GCC, whereas C++ with GCC is lower than
C++ with Clang. For Java, Eclipse Temurin with HotSpot C2 is lower than
GraalVM JIT, and both are lower than GraalVM Native Image. C# Native AOT is
lower than CoreCLR in the full-sample medians, but the Native AOT trial does
not pass the stability check. These relationships describe this run and do
not isolate the reason for any difference.

## Relationship to the virtual-dispatch report

No numerical Task 1.2 comparison is made. The existing virtual-dispatch run
uses the same host and Podman resource controls, but it records `value=1`, 5
warmup samples, and 20 measured samples rather than `value=7`, 10, and 30.
The two workloads also deliberately use different data representations and
control flow. Consequently, subtracting their medians would not isolate enum
tag dispatch from virtual dispatch. A controlled comparison requires matching
workload settings, run conditions, trial counts, and timing configurations;
generated-code evidence from Task 2.3 can then describe, but not by itself
quantify, the mechanisms involved.

## Conclusions and limitations

This run supports a provisional ordering for the complete enum-dispatch
workload under one Podman configuration. Twelve of 13 trials satisfy the
declared final-window check, but every result comes from one process trial and
all source measurement samples remain `unclassified`. The data do not support
claims about independent-run distributions, startup performance,
cross-machine behavior, or isolated tag-dispatch cost.

There are no startup rows, source-classified steady-state rows, runtime
diagnostics, independent process repetitions, or matched controls. Stronger
conclusions require multiple fresh-process trials per target, a predefined
stability rule, explicit runtime-feature provenance, and a matched control
that holds traversal, arithmetic, data layout, and checksum work constant.

## Code under test

The following source excerpts show the measured benchmark function.

### C

Source: [enum-dispatch-test/c/main.c](../enum-dispatch-test/c/main.c), function `run`.

```c
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

Source: [enum-dispatch-test/cpp/main.cpp](../enum-dispatch-test/cpp/main.cpp), function `run`.

```cpp
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

Source: [enum-dispatch-test/java/EnumDispatch.java](../enum-dispatch-test/java/EnumDispatch.java), function `run`.

```java
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

Source: [enum-dispatch-test/rust/src/main.rs](../enum-dispatch-test/rust/src/main.rs), function `run`.

```rust
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

Source: [enum-dispatch-test/go/main.go](../enum-dispatch-test/go/main.go), function `run`.

```go
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

Source: [enum-dispatch-test/python/enum_dispatch.py](../enum-dispatch-test/python/enum_dispatch.py), function `run`.

```python
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

Source: [enum-dispatch-test/csharp/Program.cs](../enum-dispatch-test/csharp/Program.cs), function `Run`.

```csharp
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

Source: [enum-dispatch-test/javascript/enum-dispatch.js](../enum-dispatch-test/javascript/enum-dispatch.js), function `run`.

```javascript
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
