# Matched virtual-versus-enum dispatch validation

## Scope and validation

This analysis covers Task 3.1 run `dispatch-validation-001` for C, C++, and
Java. Both workloads used `size=100000`, `seed=42`, `repeats=100`, `value=7`,
10 warmup samples, 30 measured samples, and five fresh-process trials. Every
run used the Docker-compatible command under Podman 5.7.0, logical CPU 0, no
memory limit, x86-64 Linux, and the same recorded host.

All 14 CSVs are present. Each contains exactly 200 data rows: five trials with
10 `warmup` and 30 `unclassified` samples. Trial numbers are 1 through 5,
sample indices are 1 through 40, and there are no duplicate rows, schema
errors, target/configuration mismatches, or invalid metric/unit fields.

All 70 trial-specific logs are present. Every log records the matched settings,
Podman execution through the Docker-compatible CLI, CPU and memory controls,
the expected trial and target, successful checksum validation, and exit status
0. C and C++ report checksum `373840100`; Java reports `375564700` for both
workloads. The rerun therefore fixes the first collection's overwritten-log
provenance defect.

## Method

For each target, workload, and trial, the primary observation is the median of
the 30 source samples labeled `unclassified`. Target-level workload medians and
IQRs are calculated across the five independent trial medians rather than by
pooling the 150 within-process samples.

The paired difference is `enum median - virtual median` for the same trial; a
negative value means enum dispatch completed the whole workload faster. The
ratio is `enum median / virtual median`; a value below 1 likewise favors enum.
The table reports the median paired result and its minimum-to-maximum range.

For a descriptive stability check, a trial passes when its final 10 measured
samples satisfy both conditions used in the earlier enum report: the medians
of the first and second five-sample windows differ by at most 5% of the final-10
median, and the final-10 IQR is at most 10% of that median. This check does not
relabel the source `unclassified` samples.

## Results

| Target | Virtual median, ms (trial IQR) | Enum median, ms (trial IQR) | Paired enum−virtual, ms median [range] | Paired enum/virtual median [range] | Stable trials, virtual / enum |
| --- | ---: | ---: | ---: | ---: | ---: |
| C (GCC) [`c-gcc`] | 71.051 (0.467) | 61.741 (10.443) | -9.377 [-9.958, +9.557] | 0.868 [0.860, 1.134] | 3/5 / 3/5 |
| C (Clang) [`c-clang`] | 78.807 (1.286) | 7.932 (0.346) | -71.007 [-71.076, -69.015] | 0.102 [0.098, 0.103] | 2/5 / 2/5 |
| C++ (GCC) [`cpp-gcc`] | 93.632 (1.369) | 61.098 (1.147) | -32.257 [-33.623, -30.844] | 0.653 [0.645, 0.671] | 5/5 / 2/5 |
| C++ (Clang) [`cpp-clang`] | 92.754 (2.482) | 72.095 (2.514) | -20.658 [-24.305, -16.943] | 0.777 [0.748, 0.818] | 4/5 / 2/5 |
| Java (Eclipse Temurin, HotSpot C2) [`temurin-c2`] | 94.723 (5.542) | 95.015 (2.117) | +0.292 [-0.305, +11.685] | 1.003 [0.997, 1.138] | 5/5 / 5/5 |
| Java (GraalVM JIT) [`graalvm-jit`] | 106.243 (0.861) | 104.785 (1.000) | -0.948 [-1.887, -0.573] | 0.991 [0.982, 0.995] | 5/5 / 5/5 |
| Java (GraalVM Native Image) [`graalvm-native`] | 173.384 (0.436) | 166.726 (0.493) | -6.667 [-6.957, -6.562] | 0.962 [0.960, 0.962] | 5/5 / 5/5 |

## Interpretation

### Java

Java with Eclipse Temurin/HotSpot C2 is effectively tied at the target-level
median: enum is 0.3% slower. Four paired trials differ by less than roughly 2
ms, while one pair has virtual at 84.500 ms and enum at 96.185 ms, producing
the upper ratio of 1.138. All ten Java HotSpot trials pass the stated stability
check, so this is between-process variation rather than a failed final-window
check. Five trials do not support a meaningful general enum advantage.

Java with GraalVM JIT has enum faster in all five pairs, but only slightly: the
median ratio is 0.991, with a narrow range of 0.982–0.995. This is a repeatable
approximately 0.9% complete-workload difference, not evidence of a large
indirect-call penalty.

These JIT results agree with the generated-code evidence. The optimized Java
virtual-dispatch loops use guarded polymorphic inlining and direct arithmetic,
not an indirect interface call for every item. Both Java workloads also retain
the `ArrayList` and object-layout costs. The optimized comparison is therefore
not simply “indirect call versus enum branch.”

Java with GraalVM Native Image has a highly consistent enum advantage. Its
median ratio is 0.962, and every paired ratio is between 0.960 and 0.962: about
3.8% lower complete-workload time. Native Image retains an indirect interface
call in virtual dispatch, but its enum workload also retains substantial
iterator and object machinery. The net difference cannot be assigned entirely
to the indirect call.

### C and C++

C++ shows a clear, consistent enum advantage in every paired trial:

- C++ with GCC has a median ratio of 0.653, about 34.7% lower enum workload
  time, with paired ratios from 0.645 to 0.671.
- C++ with Clang has a median ratio of 0.777, about 22.3% lower enum workload
  time, with paired ratios from 0.748 to 0.818.

The direction and separation are robust across processes, although only two
of five enum trials for each C++ compiler pass the conservative final-window
stability check. This weakens claims about an exact steady-state ratio but does
not erase the observed separation between the paired trial medians.

C with Clang again shows the largest difference: a median ratio of 0.102, or
about 89.8% lower enum workload time. Every paired ratio is between 0.098 and
0.103. This is explained primarily by the known code-generation split: enum
dispatch uses an eight-record branchless SIMD loop, while virtual dispatch
retains an indirect function-pointer call. It cannot isolate indirect-call
latency.

C with GCC usually favors enum by about 13%, but enum trial 5 is anomalous at
80.861 ms versus approximately 61 ms for the other four enum trials. That pair
has a ratio of 1.134 and favors virtual dispatch, while the other four ratios
are 0.860–0.871. The anomaly is retained, not excluded. The target-level
median still favors enum, but the wide IQR and crossed paired range require
more caution than the C++ results.

## Conclusions and next step

The interference-controlled rerun strengthens the central conclusion:

- Java JIT virtual and enum workloads are nearly equal because optimized
  virtual dispatch is devirtualized and inlined in the captured hot paths.
- Java Native Image shows a small, consistent enum advantage.
- C++ shows a materially larger and consistent enum advantage.
- C/Clang is dominated by enum SIMD vectorization, while C/GCC contains one
  retained anomalous trial.

None of these pairs isolates the latency of an indirect call. A controlled
follow-up should use an identical flat dataset and loop body and vary only the
dispatch expression, while verifying that virtual dispatch remains indirect
and that enum dispatch does not gain unrelated vectorization. Hardware branch,
cache, and cycle counters would further separate branch prediction, call
overhead, and memory-layout effects. Existing Task 1.x and 2.x reports should
be updated only under a separately requested Task 3.2.

## Code under test

These examples include the operation/tag declarations needed to read the measured functions.

### Virtual dispatch

#### C

Source: [virtual-dispatch-test/c/main.c](../virtual-dispatch-test/c/main.c), declarations and function `run`.

```c
typedef struct Operation Operation;
struct Operation {
  int32_t (*process)(const Operation *, int32_t);
  int32_t operand;
};

static int32_t add(const Operation *o, int32_t v) {
  return (int32_t)((uint32_t)v + (uint32_t)o->operand);
}
static int32_t mul(const Operation *o, int32_t v) {
  return (int32_t)((uint32_t)v * (uint32_t)o->operand);
}

static int32_t run(const Operation *ops, uint32_t size, uint32_t repeats,
                   int32_t value) {
  uint32_t sum = 0;
  for (uint32_t n = 0; n < repeats; n++)
    for (uint32_t i = 0; i < size; i++)
      sum += (uint32_t)ops[i].process(&ops[i], value);
  return (int32_t)sum;
}
```

#### C++

Source: [virtual-dispatch-test/cpp/main.cpp](../virtual-dispatch-test/cpp/main.cpp), declarations and function `run`.

```cpp
struct Operation {
  virtual std::int32_t process(std::int32_t) const = 0;
  virtual ~Operation() = default;
};
struct Add final : Operation {
  std::int32_t x;
  explicit Add(std::int32_t v) : x(v) {}
  std::int32_t process(std::int32_t v) const override {
    return static_cast<std::int32_t>(static_cast<std::uint32_t>(v) +
                                     static_cast<std::uint32_t>(x));
  }
};
struct Mul final : Operation {
  std::int32_t x;
  explicit Mul(std::int32_t v) : x(v) {}
  std::int32_t process(std::int32_t v) const override {
    return static_cast<std::int32_t>(static_cast<std::uint32_t>(v) *
                                     static_cast<std::uint32_t>(x));
  }
};

static std::int32_t run(const std::vector<std::unique_ptr<Operation>> &ops,
                        std::uint32_t repeats, std::int32_t value) {
  std::uint32_t sum = 0;
  for (std::uint32_t n = 0; n < repeats; n++)
    for (const auto &o : ops)
      sum += static_cast<std::uint32_t>(o->process(value));
  return static_cast<std::int32_t>(sum);
}
```

#### Java

Source: [virtual-dispatch-test/java/VirtualDispatch.java](../virtual-dispatch-test/java/VirtualDispatch.java), declarations and function `run`.

```java
  interface Operation {
    int process(int value);
  }
  record AddOperation(int operand) implements Operation {
    public int process(int value) { return value + operand; }
  }
  record MulOperation(int operand) implements Operation {
    public int process(int value) { return value * operand; }
  }

  static int run(List<Operation> operations, int repeats, int value) {
    int checksum = 0;
    for (int n = 0; n < repeats; n++)
      for (Operation operation : operations)
        checksum += operation.process(value);
    return checksum;
  }
```

### Enum dispatch

#### C

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

#### C++

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

#### Java

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
