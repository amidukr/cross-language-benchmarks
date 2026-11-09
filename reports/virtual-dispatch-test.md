# Virtual dispatch benchmark analysis

## Scope and inputs

This analysis uses the single container run
`run-20261108T172840Z-63943`. All targets ran sequentially under Podman 5.7.0
on Linux 7.0.0-42-generic, x86-64, on an Intel Core i7-1255U. The runner used
host `taskset` to restrict each container to logical CPU 0 and recorded no
memory limit. Although the logs retain `execution_mode=docker` as the generic
container-mode label, `container_runtime=podman` identifies this comparison as
a Podman group. No native or Docker-engine results are mixed into it.

The following source pairs were selected.

| Target | CSV | Run log |
| --- | --- | --- |
| `c-gcc` | `virtual-dispatch-test/c-gcc-report.csv` | `virtual-dispatch-test/c-gcc-run-20261108T172840Z-63943.log` |
| `c-clang` | `virtual-dispatch-test/c-clang-report.csv` | `virtual-dispatch-test/c-clang-run-20261108T172840Z-63943.log` |
| `cpp-gcc` | `virtual-dispatch-test/cpp-gcc-report.csv` | `virtual-dispatch-test/cpp-gcc-run-20261108T172840Z-63943.log` |
| `cpp-clang` | `virtual-dispatch-test/cpp-clang-report.csv` | `virtual-dispatch-test/cpp-clang-run-20261108T172840Z-63943.log` |
| Java (Eclipse Temurin, HotSpot C2) [`temurin-c2`] | `virtual-dispatch-test/temurin-c2-report.csv` | `virtual-dispatch-test/temurin-c2-run-20261108T172840Z-63943.log` |
| Java (GraalVM JIT) [`graalvm-jit`] | `virtual-dispatch-test/graalvm-jit-report.csv` | `virtual-dispatch-test/graalvm-jit-run-20261108T172840Z-63943.log` |
| Java (GraalVM Native Image) [`graalvm-native`] | `virtual-dispatch-test/graalvm-native-report.csv` | `virtual-dispatch-test/graalvm-native-run-20261108T172840Z-63943.log` |
| `rust` | `virtual-dispatch-test/rust-report.csv` | `virtual-dispatch-test/rust-run-20261108T172840Z-63943.log` |
| `go` | `virtual-dispatch-test/go-report.csv` | `virtual-dispatch-test/go-run-20261108T172840Z-63943.log` |
| `cpython` | `virtual-dispatch-test/cpython-report.csv` | `virtual-dispatch-test/cpython-run-20261108T172840Z-63943.log` |
| `coreclr` | `virtual-dispatch-test/coreclr-report.csv` | `virtual-dispatch-test/coreclr-run-20261108T172840Z-63943.log` |
| `dotnet-native` | `virtual-dispatch-test/dotnet-native-report.csv` | `virtual-dispatch-test/dotnet-native-run-20261108T172840Z-63943.log` |
| `node-v8` | `virtual-dispatch-test/node-v8-report.csv` | `virtual-dispatch-test/node-v8-run-20261108T172840Z-63943.log` |

All paths in this table are relative to `reports/`.

## Validation and comparability

The 13 CSVs contain 325 rows: 5 `warmup` and 20 `unclassified` samples for
each target. Every row uses schema version 2, metric `time_per_op`, and unit
`ns/op`. Sample indices are contiguous from 1 through 25, elapsed time is
strictly increasing within every trial, and there are no duplicate rows,
duplicate trials, missing targets, incomplete trials, extra targets, or failed
runs. The two C# files begin with a UTF-8 byte-order mark; decoding them as
UTF-8 with a signature produces the required schema header, but consumers that
require the first field to be byte-for-byte `schema_version` need to account
for the mark.

All logs report `size=100000`, `repeats=100`, `value=1`, 5 warmup samples, 20
measured samples, trial 1, configuration `default`, a successful checksum, and
exit status 0. Each benchmark operation therefore contains 10,000,000 calls to
`Operation.process`. Seeds and checksums differ by target because Task 1.1
permits each language to use its own random-number generator. The generated
sequences are not identical, but they follow the same operation and operand
distributions and are treated as equivalent workloads.

The reports identify toolchain versions and principal build options. Some
provenance remains incomplete: the C and C++ `flags` fields do not list every
actual compiler option, and the logs do not explicitly record CPython GIL/JIT
state, CoreCLR ReadyToRun/Dynamic PGO state, or Node's module compile-cache
state. These omissions do not invalidate this in-process comparison, but they
reduce reproducibility and prevent analysis of those runtime features.

## Method

The primary result is `time_per_op` for the 20 samples that remain labeled
`unclassified` in the source CSVs. The table reports the median and interquartile
range (IQR, using medians of the lower and upper halves). No samples, including
spikes, were excluded. Because there is only one trial per target, the median
is a within-trial summary, not independent replication.

Time per dispatch is a derived descriptive metric:

```text
median ns/dispatch = median time_per_op / (100000 * 100)
```

It includes collection traversal, loop control, integer arithmetic, and
checksum accumulation as well as dynamic dispatch. It is not an isolated
measurement of dispatch overhead.

Task 1.1 did not define a post-run stability criterion. For this analysis, a
trial demonstrates stability only when it has at least 10 measured samples and,
over its final 10 samples, both of the following hold:

1. The medians of the first and second consecutive five-sample windows differ
   by no more than 5% of the final-10 median.
2. The final-10 IQR is no more than 10% of the final-10 median.

This is an analysis check, not a relabeling of the raw samples. All measured
samples remain `unclassified`; none are reported as source `steady_state` data.

## Results

| Target | Trials | Unclassified samples | Median (ms/op) | IQR (ms/op) | Median (ns/dispatch) | Stability check |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| `c-gcc` | 1 | 20 | 70.364 | 7.810 | 7.036 | No |
| `c-clang` | 1 | 20 | 81.541 | 24.097 | 8.154 | Yes |
| `dotnet-native` | 1 | 20 | 84.224 | 3.608 | 8.422 | Yes |
| `rust` | 1 | 20 | 90.460 | 6.271 | 9.046 | Yes |
| `cpp-gcc` | 1 | 20 | 92.844 | 0.727 | 9.284 | Yes |
| Java (Eclipse Temurin, HotSpot C2) [`temurin-c2`] | 1 | 20 | 96.107 | 4.853 | 9.611 | Yes |
| `cpp-clang` | 1 | 20 | 96.108 | 8.924 | 9.611 | Yes |
| `go` | 1 | 20 | 100.623 | 11.745 | 10.062 | Yes |
| Java (GraalVM JIT) [`graalvm-jit`] | 1 | 20 | 104.341 | 2.237 | 10.434 | Yes |
| `node-v8` | 1 | 20 | 111.522 | 8.102 | 11.152 | Yes |
| `coreclr` | 1 | 20 | 114.917 | 7.695 | 11.492 | No |
| Java (GraalVM Native Image) [`graalvm-native`] | 1 | 20 | 176.672 | 10.939 | 17.667 | Yes |
| `cpython` | 1 | 20 | 2654.789 | 10.249 | 265.479 | Yes |

The table is ordered by the unclassified-sample median. `c-gcc` has the lowest
overall median, but it did not satisfy the stability check: its final two
five-sample medians were 79.827 and 70.009 ms/op (13.18% apart), and the final
10 IQR was 35.01% of their median. Its late series contains 95.979, 106.164,
and 108.871 ms spikes. Among trials that pass the stated check, `c-clang` has
the lowest median, but its full measured IQR is wide because samples 4 through
9 rise as high as 133.996 ms before the final window settles.

`coreclr` also fails the stability check. Its final two five-sample medians are
114.759 and 106.486 ms/op, 7.45% apart, indicating a late downward shift rather
than a stable final level. No diagnostic data is available to attribute that
shift to tiered compilation, dynamic PGO, OSR, or another cause.

Several other trials show transitions or spikes before their stable-check
window. `cpp-clang` reaches 146.026 ms, Go reaches 146.848 ms, and Java
(GraalVM Native Image) reaches 245.338 ms early in the measured phase. These
observations are retained in the medians and IQRs. In contrast, `cpp-gcc` is
especially tight after its first measured samples, with a 0.727 ms full-phase
IQR. The first two warmup samples for Java (GraalVM JIT) fall from 210.239 to
160.378 ms before later values cluster near 103--105 ms; Java (Eclipse
Temurin, HotSpot C2) similarly drops from 190.496 to 141.160 ms and then to
roughly 96 ms. Those shapes are consistent with runtime warmup, but without
compilation logs they are not confirmation of JIT events.

The within-language results are also single-trial observations. Clang's C
median is higher than GCC's, while the two C++ medians are effectively equal.
For Java, Eclipse Temurin with HotSpot C2 is lower than GraalVM JIT in this
run, and both are lower than GraalVM Native Image. .NET Native AOT is lower
than CoreCLR, though the CoreCLR trial lacks stability. These differences
describe the complete workload on the recorded configurations; no matched
non-virtual control exists to assign them specifically to dispatch.

## Conclusions and limitations

This run supports a provisional ordering for the complete virtual-dispatch
workload under one Podman configuration. It does not support claims about
cross-machine performance, independent-run distributions, startup cost, or
isolated dispatch overhead. Eleven of 13 trials satisfy the declared
final-window check, but every numerical comparison is based on one process
trial and all source measurement phases remain unclassified.

There are no startup rows, separately classified steady-state rows, compilation
or deoptimization diagnostics, garbage-collection diagnostics, or matched
non-virtual controls. Stronger conclusions require multiple fresh-process
trials per target with the same case and controls, separate startup trials,
and runtime-specific diagnostic runs. A matched direct-call workload would be
needed before attributing target differences to virtual dispatch itself.
