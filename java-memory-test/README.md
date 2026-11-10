# Java minimum-RSS benchmark

This workload implements [Task 4.1](../agent-tasks/4.1-java-minimum-rss.md).
It measures process RSS, process high-water RSS, container cgroup memory,
readiness time, and effective heap settings for four small Java applications:

- `console`: prints and retains `Hello World`, then blocks.
- `swing`: displays a visible `JFrame` with a `Hello World` label under Xvfb.
- `spring-boot`: Spring Boot 4.1.2 with only `GET /hello-world`.
- `quarkus`: Quarkus 3.40.1.1 LTS with only `GET /hello-world`.

The Java targets are Java (Eclipse Temurin, HotSpot C2) [`temurin-c2`], Java
(GraalVM JIT) [`graalvm-jit`], and Java (GraalVM Native Image)
[`graalvm-native`]. Framework, Maven, JDK, GraalVM, base-image, and plugin
versions are pinned in the Dockerfile, Maven wrapper properties, and POMs.
Every image records its resolved OS package and Xvfb versions.

RSS is whole-process resident memory; it is not Java heap usage. The sampler
therefore keeps process RSS, cgroup memory, peak RSS, and `MemoryMXBean` heap
values distinct.

## Prerequisites

Use Linux with Bash, `taskset`, and Docker or Podman. Native framework builds
are expensive and can require several CPUs and multiple gigabytes while
building; the measured containers themselves are limited to one logical CPU
and 1 GiB. Avoid other substantial host work while collecting measurements.

Scripts use Docker by default. Select Podman consistently with:

```sh
export CONTAINER_ENGINE=podman
```

## Build

Build every application and JVM target, then attempt the Native Image default,
Serial, Epsilon, and G1 artifacts. Use a new build ID; existing output is never
overwritten.

```sh
./java-memory-test/build-all.sh memory-build-001
```

Build logs and unsupported native configurations are retained under
`reports/java-memory-test/build/memory-build-001/`. A nonzero batch status means
at least one requested artifact failed or was unsupported; inspect the retained
manifest and standard error rather than deleting it.

One artifact can be built directly:

```sh
./java-memory-test/build.sh \
  --application console \
  --target temurin-c2

./java-memory-test/build.sh \
  --application spring-boot \
  --target graalvm-native \
  --collector serial
```

JVM collectors are runtime selections, so JVM images are built with collector
`default`. Native Image collectors are build-time selections and have separate
images.

## Probe support

The full matrix probes support automatically. To collect only collector and
heap-option probes into a new directory:

```sh
./java-memory-test/probe-collectors.sh \
  --output reports/java-memory-test/probe-001
```

The JVM probes attempt default, Serial, Parallel, G1, ZGC, Shenandoah, and
Epsilon collectors against the exact image. Native support is based on the
successful collector-specific Native Image artifact. `-Xms` and `-Xmx` are
also probed and their commands, output, status, and runtime versions retained.

## Run one explicit trial

The following example performs one complete default-memory trial:

```sh
./java-memory-test/run-one.sh \
  --application spring-boot \
  --target temurin-c2 \
  --collector g1 \
  --heap-profile default \
  --run-id memory-001 \
  --trial 1
```

Heap settings are optional and explicit:

```sh
./java-memory-test/run-one.sh \
  --application console \
  --target graalvm-jit \
  --collector serial \
  --heap-profile combined-1m-16m \
  --xms 1m --xmx 16m \
  --run-id memory-001 \
  --trial 1
```

An existing trial directory is rejected. Different configurations and trials
may share the same new run ID because their paths cannot collide.

## Run the complete staged matrix

After building, choose a run ID that does not exist:

```sh
./java-memory-test/run-matrix.sh memory-001
```

The script runs sequentially and prints the application, target, collector,
heap profile, candidate values, and trial. For every supported combination it:

1. Runs five default-setting trials.
2. Tests the ordered `-Xms` grid until the smallest successful value, then
   completes five trials for that value.
3. Tests the descending `-Xmx` grid and completes five trials for the smallest
   successful value.
4. Searches for the smallest successful combined pair and completes five
   trials.
5. Runs five fixed-heap trials with `-Xms` equal to the smallest viable
   `-Xmx`.

Failed candidates are evidence and remain in place with their failure reason.
The boundary file means “smallest successful tested grid value under this
environment,” not a universal lower bound.

This is a large experiment: every successful trial contains two 30-second
sampling windows plus readiness, REST exercise, settling, and shutdown. Plan
for a long unattended run.

## Measurement sequence

Each fresh measured container:

1. Starts one application and records its PID start ticks.
2. Waits up to 120 seconds for `MEMORY_TEST_READY`.
3. Samples 300 times at 100 ms during `ready-idle`.
4. Sends 1,000 sequential exact-response checks to REST applications.
5. Waits 10 seconds without forcing GC.
6. Samples another 300 times during `post-exercise-idle`.
7. Sends `SIGTERM`, waits up to 10 seconds, and records any forced `SIGKILL`.

The primary RSS source is `/proc/<pid>/smaps_rollup`; `VmRSS` is a labeled
fallback. Every sample records `VmHWM`, cgroup `memory.current`, a monotonic
timestamp, phase, and PID start ticks. Xvfb is a separate process: Java process
RSS excludes it, while cgroup memory includes it. Client activity can affect
the `exercise` cgroup samples; the two idle phases are the footprint comparison
windows.

No `System.gc()`, `jcmd GC.run`, compilation logging, or runtime attachment is
used. Effective heap values are emitted by the application through
`MemoryMXBean` at readiness.

## Validate and summarize

After collection:

```sh
./java-memory-test/validate.sh memory-001
./java-memory-test/summarize.sh memory-001
```

Validation checks successful trials for required provenance, readiness,
correctness, and exactly 300 samples in each idle phase. Expected failed heap
candidates are reported as retained failures rather than discarded outliers.

`summary.csv` reports every valid trial before aggregation, including minimum,
10th percentile, median, maximum, range, and final-window range for both idle
phases. Raw ordered samples and slow/high-memory observations are never
deleted.

## Output layout

```text
reports/java-memory-test/<run-id>/
  probes/
  <application>/<target>/<collector>/<heap-profile>/<trial>/
    manifest.txt
    host-manifest.txt
    raw-samples.csv
    results.csv
    app.stdout
    app.stderr
```

Use the phase median and 10th percentile as the primary stable-footprint
statistics. Treat the absolute minimum as secondary, and never describe
`-Xmx` as a process-memory limit.
