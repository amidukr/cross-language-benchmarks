# Java application RSS analysis

## Scope and source data

This report analyzes the completed 10-second survey run memory-002. Each successful trial sampled survey-idle 100 times at 100 ms intervals after readiness. Every trial is shown separately.

Both runs used Podman 5.7.0 on x86-64 Linux 7.0.0-42-generic with an Intel Core i7-1255U, one logical CPU, and a 1 GiB container memory limit. The JVM target used Eclipse Temurin JDK 25.0.1+8. Successful Native Image trials used GraalVM Native Image 25.0.4.1.1. The JVM default collector was Serial in the GC logs; the Native Image default artifact reports Serial GC in its toolchain record. JVM collector choices are runtime options; Native Image collector choices are build-time artifacts.

| Run | Collection scope | Attempts | Successful | Failed | Source summary | Matrix manifest |
| --- | --- | ---: | ---: | ---: | --- | --- |
| memory-002 | All probed, available collector images | 200 | 181 | 19 | [summary.csv](java-memory-test/memory-002/summary.csv) | [matrix-manifest.txt](java-memory-test/memory-002/matrix-manifest.txt) |

The underlying source files for each trial are manifest.txt, raw-samples.csv, results.csv, app.stdout, app.stderr, and (for JVM trials) gc.log, beneath java-memory-test/<run-id>/<application>/<target>/<collector>/<heap-profile>/1/. Probe evidence is in each run’s probes/support.tsv, probes/heap-options.tsv, and target/collector probe directories.

## Validation and coverage

The matrix manifest ends in status=complete. The 181 successful trial directories each have 100 ordered survey samples and 100 RSS, peak-RSS, and cgroup-memory result samples. Recomputing minimum, P10, median, maximum, range, and final-window range from the ordered raw records matched every summary row. All successful REST trials recorded 1,000 requests and zero correctness failures. Failed trials have no successful RSS summary rows.

The 19 failed attempts fall into three groups:

- F1 — Swing Native Image AOT, 15 profiles across the default, Serial, and Epsilon collectors: the app did not emit readiness. Captured native failures include missing sun/awt/X11/XErrorHandlerUtil and an unavailable awt library. These are AWT/native-library initialization failures, not low-RSS successes.
- F2 — three 16 MiB maximum-heap JVM profiles: Spring Boot with Temurin/Epsilon, Quarkus with Temurin/Epsilon, and Spring Boot with Temurin/ZGC terminated with OutOfMemoryError before completing readiness.
- F3 — Spring Boot Native Image AOT with Epsilon and -Xms1m -Xmx16m: it became ready, then OOM errors in HTTP worker threads caused REST checks to time out; the controller exited with curl status 28. This profile is invalid.

GraalVM JIT has no trial results: its probes could not find the expected application images. Native Image G1 likewise had no available image. The probe records therefore establish missing artifacts for these matrix cells, not that the runtime or collector itself is unsupported. All attempted Native Image default, Serial, and Epsilon profiles for Swing failed as F1.

### Unavailable target configurations

| Runtime configuration | Result | Evidence |
| --- | --- | --- |
| Java (GraalVM JIT) [graalvm-jit], all four applications | No trial data | Probes could not find the expected application images. |
| Java (GraalVM Native Image) [graalvm-native], G1 | No trial data | The expected G1 image was not present; no runtime support conclusion can be drawn. |
| Java (GraalVM Native Image) [graalvm-native], Swing with default, Serial, or Epsilon build | Failed [F1] | AWT initialization failed before readiness; details are in the Swing profile table and trial stderr. |

No full-duration trial was present in either completed run. Results below describe the 10-second survey only, not the separate ready-idle and post-exercise phases in Task 4.1 full mode.

## Cross-application summary: default heap profile

Cells show median / P10 process RSS in MiB, with 100 raw samples per value. Rows retain the run and trial identity. Default is reported separately from an explicitly selected Serial collector even where both resolve to Serial.

| Run / trial | Execution target and kind | Collector | Console | Swing | Spring Boot | Quarkus |
| --- | --- | --- | --- | --- | --- | --- |
| memory-002 / 1 | JVM — Java (Eclipse Temurin, HotSpot C2) [temurin-c2]; JDK 25.0.1+8 | Default (runtime selected Serial) | 42.11 / 42.11 (n=100) | 72.09 / 72.08 (n=100) | 130.50 / 130.48 (n=100) | 112.89 / 112.89 (n=100) |
| memory-002 / 1 | JVM — Java (Eclipse Temurin, HotSpot C2) [temurin-c2]; JDK 25.0.1+8 | Serial | 41.91 / 41.91 (n=100) | 71.96 / 71.96 (n=100) | 136.79 / 136.63 (n=100) | 107.31 / 107.31 (n=100) |
| memory-002 / 1 | JVM — Java (Eclipse Temurin, HotSpot C2) [temurin-c2]; JDK 25.0.1+8 | Parallel | 41.91 / 41.91 (n=100) | 72.36 / 72.36 (n=100) | 181.19 / 181.14 (n=100) | 115.66 / 115.66 (n=100) |
| memory-002 / 1 | JVM — Java (Eclipse Temurin, HotSpot C2) [temurin-c2]; JDK 25.0.1+8 | G1 | 43.39 / 43.39 (n=100) | 75.34 / 75.34 (n=100) | 151.86 / 151.81 (n=100) | 113.52 / 113.52 (n=100) |
| memory-002 / 1 | JVM — Java (Eclipse Temurin, HotSpot C2) [temurin-c2]; JDK 25.0.1+8 | ZGC | 45.36 / 45.36 (n=100) | 79.24 / 79.23 (n=100) | 244.10 / 244.00 (n=100) | 139.63 / 139.63 (n=100) |
| memory-002 / 1 | JVM — Java (Eclipse Temurin, HotSpot C2) [temurin-c2]; JDK 25.0.1+8 | Shenandoah | 44.40 / 44.40 (n=100) | 78.90 / 78.90 (n=100) | 209.10 / 209.03 (n=100) | 142.38 / 142.38 (n=100) |
| memory-002 / 1 | JVM — Java (Eclipse Temurin, HotSpot C2) [temurin-c2]; JDK 25.0.1+8 | Epsilon | 41.85 / 41.85 (n=100) | 74.52 / 74.52 (n=100) | 319.65 / 319.46 (n=100) | 133.89 / 133.89 (n=100) |
| memory-002 / 1 | Native Image AOT — Java (GraalVM Native Image) [graalvm-native]; Native Image 25.0.4.1.1 | Default (artifact uses Serial) | 8.93 / 8.93 (n=100) | Failed [F1] | 88.74 / 88.74 (n=100) | 35.94 / 35.94 (n=100) |
| memory-002 / 1 | Native Image AOT — Java (GraalVM Native Image) [graalvm-native]; Native Image 25.0.4.1.1 | Serial (build-time) | 8.80 / 8.80 (n=100) | Failed [F1] | 88.50 / 88.50 (n=100) | 36.22 / 36.22 (n=100) |
| memory-002 / 1 | Native Image AOT — Java (GraalVM Native Image) [graalvm-native]; Native Image 25.0.4.1.1 | Epsilon (build-time) | 8.89 / 8.89 (n=100) | Failed [F1] | 86.75 / 86.75 (n=100) | 35.73 / 35.73 (n=100) |

## Heap-profile results by application

Each cell shows median / P10 process RSS in MiB (n=100 samples). Each row is one run, target, collector, and trial. Failed profile labels refer to the failure key above. A missing measurement is not converted to zero.

### Console

| Run / trial | Execution target and kind | Collector | Default / default | 1 MiB / default | 1 MiB / 16 MiB | 1 MiB / 1024 MiB | 512 MiB / 1024 MiB |
| --- | --- | --- | --- | --- | --- | --- | --- |
| memory-002 / 1 | JVM — Java (Eclipse Temurin, HotSpot C2) [temurin-c2]; JDK 25.0.1+8 | Default (runtime selected Serial) | 42.11 / 42.11 (n=100) | 42.73 / 42.73 (n=100) | 42.78 / 42.78 (n=100) | 42.78 / 42.78 (n=100) | 43.25 / 43.25 (n=100) |
| memory-002 / 1 | JVM — Java (Eclipse Temurin, HotSpot C2) [temurin-c2]; JDK 25.0.1+8 | Serial | 41.91 / 41.91 (n=100) | 42.63 / 42.63 (n=100) | 42.87 / 42.87 (n=100) | 42.93 / 42.93 (n=100) | 43.07 / 43.07 (n=100) |
| memory-002 / 1 | JVM — Java (Eclipse Temurin, HotSpot C2) [temurin-c2]; JDK 25.0.1+8 | Parallel | 41.91 / 41.91 (n=100) | 41.95 / 41.95 (n=100) | 41.86 / 41.86 (n=100) | 42.16 / 42.16 (n=100) | 43.19 / 43.19 (n=100) |
| memory-002 / 1 | JVM — Java (Eclipse Temurin, HotSpot C2) [temurin-c2]; JDK 25.0.1+8 | G1 | 43.39 / 43.39 (n=100) | 42.98 / 42.98 (n=100) | 42.83 / 42.83 (n=100) | 43.61 / 43.61 (n=100) | 44.61 / 44.61 (n=100) |
| memory-002 / 1 | JVM — Java (Eclipse Temurin, HotSpot C2) [temurin-c2]; JDK 25.0.1+8 | ZGC | 45.36 / 45.36 (n=100) | 45.25 / 45.25 (n=100) | 48.07 / 48.07 (n=100) | 45.62 / 45.62 (n=100) | 45.47 / 45.47 (n=100) |
| memory-002 / 1 | JVM — Java (Eclipse Temurin, HotSpot C2) [temurin-c2]; JDK 25.0.1+8 | Shenandoah | 44.40 / 44.40 (n=100) | 45.30 / 45.30 (n=100) | 44.67 / 44.67 (n=100) | 45.54 / 45.54 (n=100) | 45.19 / 45.19 (n=100) |
| memory-002 / 1 | JVM — Java (Eclipse Temurin, HotSpot C2) [temurin-c2]; JDK 25.0.1+8 | Epsilon | 41.85 / 41.85 (n=100) | 42.07 / 42.07 (n=100) | 41.88 / 41.88 (n=100) | 41.86 / 41.86 (n=100) | 41.89 / 41.89 (n=100) |
| memory-002 / 1 | Native Image AOT — Java (GraalVM Native Image) [graalvm-native]; Native Image 25.0.4.1.1 | Default (artifact uses Serial) | 8.93 / 8.93 (n=100) | 8.85 / 8.85 (n=100) | 8.97 / 8.97 (n=100) | 9.09 / 9.09 (n=100) | 8.94 / 8.94 (n=100) |
| memory-002 / 1 | Native Image AOT — Java (GraalVM Native Image) [graalvm-native]; Native Image 25.0.4.1.1 | Serial (build-time) | 8.80 / 8.80 (n=100) | 9.00 / 9.00 (n=100) | 9.09 / 9.09 (n=100) | 9.09 / 9.09 (n=100) | 9.11 / 9.11 (n=100) |
| memory-002 / 1 | Native Image AOT — Java (GraalVM Native Image) [graalvm-native]; Native Image 25.0.4.1.1 | Epsilon (build-time) | 8.89 / 8.89 (n=100) | 8.93 / 8.93 (n=100) | 8.85 / 8.85 (n=100) | 8.74 / 8.74 (n=100) | 8.75 / 8.75 (n=100) |

### Swing

| Run / trial | Execution target and kind | Collector | Default / default | 1 MiB / default | 1 MiB / 16 MiB | 1 MiB / 1024 MiB | 512 MiB / 1024 MiB |
| --- | --- | --- | --- | --- | --- | --- | --- |
| memory-002 / 1 | JVM — Java (Eclipse Temurin, HotSpot C2) [temurin-c2]; JDK 25.0.1+8 | Default (runtime selected Serial) | 72.09 / 72.08 (n=100) | 68.73 / 68.72 (n=100) | 68.69 / 68.69 (n=100) | 69.09 / 69.09 (n=100) | 75.92 / 75.91 (n=100) |
| memory-002 / 1 | JVM — Java (Eclipse Temurin, HotSpot C2) [temurin-c2]; JDK 25.0.1+8 | Serial | 71.96 / 71.96 (n=100) | 68.97 / 68.97 (n=100) | 69.23 / 69.23 (n=100) | 69.32 / 69.32 (n=100) | 75.83 / 75.83 (n=100) |
| memory-002 / 1 | JVM — Java (Eclipse Temurin, HotSpot C2) [temurin-c2]; JDK 25.0.1+8 | Parallel | 72.36 / 72.36 (n=100) | 70.41 / 70.40 (n=100) | 70.90 / 70.90 (n=100) | 70.33 / 70.33 (n=100) | 76.16 / 76.15 (n=100) |
| memory-002 / 1 | JVM — Java (Eclipse Temurin, HotSpot C2) [temurin-c2]; JDK 25.0.1+8 | G1 | 75.34 / 75.34 (n=100) | 73.04 / 73.04 (n=100) | 71.98 / 71.97 (n=100) | 73.75 / 73.75 (n=100) | 77.27 / 77.27 (n=100) |
| memory-002 / 1 | JVM — Java (Eclipse Temurin, HotSpot C2) [temurin-c2]; JDK 25.0.1+8 | ZGC | 79.24 / 79.23 (n=100) | 80.23 / 80.23 (n=100) | 79.91 / 79.90 (n=100) | 79.96 / 79.95 (n=100) | 80.22 / 80.21 (n=100) |
| memory-002 / 1 | JVM — Java (Eclipse Temurin, HotSpot C2) [temurin-c2]; JDK 25.0.1+8 | Shenandoah | 78.90 / 78.90 (n=100) | 79.11 / 79.11 (n=100) | 77.15 / 77.15 (n=100) | 79.27 / 79.27 (n=100) | 79.16 / 79.15 (n=100) |
| memory-002 / 1 | JVM — Java (Eclipse Temurin, HotSpot C2) [temurin-c2]; JDK 25.0.1+8 | Epsilon | 74.52 / 74.52 (n=100) | 75.01 / 75.01 (n=100) | 75.02 / 75.02 (n=100) | 75.11 / 75.11 (n=100) | 74.82 / 74.82 (n=100) |
| memory-002 / 1 | Native Image AOT — Java (GraalVM Native Image) [graalvm-native]; Native Image 25.0.4.1.1 | Default (artifact uses Serial) | Failed [F1] | Failed [F1] | Failed [F1] | Failed [F1] | Failed [F1] |
| memory-002 / 1 | Native Image AOT — Java (GraalVM Native Image) [graalvm-native]; Native Image 25.0.4.1.1 | Serial (build-time) | Failed [F1] | Failed [F1] | Failed [F1] | Failed [F1] | Failed [F1] |
| memory-002 / 1 | Native Image AOT — Java (GraalVM Native Image) [graalvm-native]; Native Image 25.0.4.1.1 | Epsilon (build-time) | Failed [F1] | Failed [F1] | Failed [F1] | Failed [F1] | Failed [F1] |

### Spring Boot

| Run / trial | Execution target and kind | Collector | Default / default | 1 MiB / default | 1 MiB / 16 MiB | 1 MiB / 1024 MiB | 512 MiB / 1024 MiB |
| --- | --- | --- | --- | --- | --- | --- | --- |
| memory-002 / 1 | JVM — Java (Eclipse Temurin, HotSpot C2) [temurin-c2]; JDK 25.0.1+8 | Default (runtime selected Serial) | 130.50 / 130.48 (n=100) | 135.00 / 134.95 (n=100) | 129.98 / 129.93 (n=100) | 142.15 / 142.09 (n=100) | 273.32 / 273.21 (n=100) |
| memory-002 / 1 | JVM — Java (Eclipse Temurin, HotSpot C2) [temurin-c2]; JDK 25.0.1+8 | Serial | 136.79 / 136.63 (n=100) | 138.73 / 138.68 (n=100) | 130.37 / 130.32 (n=100) | 138.17 / 138.02 (n=100) | 270.75 / 270.75 (n=100) |
| memory-002 / 1 | JVM — Java (Eclipse Temurin, HotSpot C2) [temurin-c2]; JDK 25.0.1+8 | Parallel | 181.19 / 181.14 (n=100) | 177.29 / 177.24 (n=100) | 130.99 / 130.96 (n=100) | 163.71 / 163.68 (n=100) | 266.52 / 266.50 (n=100) |
| memory-002 / 1 | JVM — Java (Eclipse Temurin, HotSpot C2) [temurin-c2]; JDK 25.0.1+8 | G1 | 151.86 / 151.81 (n=100) | 153.07 / 153.05 (n=100) | 136.29 / 136.27 (n=100) | 152.64 / 152.64 (n=100) | 228.66 / 228.61 (n=100) |
| memory-002 / 1 | JVM — Java (Eclipse Temurin, HotSpot C2) [temurin-c2]; JDK 25.0.1+8 | ZGC | 244.10 / 244.00 (n=100) | 244.28 / 244.08 (n=100) | Failed [F2] | 266.13 / 266.08 (n=100) | 241.67 / 241.67 (n=100) |
| memory-002 / 1 | JVM — Java (Eclipse Temurin, HotSpot C2) [temurin-c2]; JDK 25.0.1+8 | Shenandoah | 209.10 / 209.03 (n=100) | 266.63 / 266.59 (n=100) | 138.35 / 138.35 (n=100) | 287.77 / 287.59 (n=100) | 345.34 / 345.18 (n=100) |
| memory-002 / 1 | JVM — Java (Eclipse Temurin, HotSpot C2) [temurin-c2]; JDK 25.0.1+8 | Epsilon | 319.65 / 319.46 (n=100) | 326.02 / 325.86 (n=100) | Failed [F2] | 319.38 / 319.12 (n=100) | 320.49 / 320.27 (n=100) |
| memory-002 / 1 | Native Image AOT — Java (GraalVM Native Image) [graalvm-native]; Native Image 25.0.4.1.1 | Default (artifact uses Serial) | 88.74 / 88.74 (n=100) | 88.64 / 88.64 (n=100) | 56.02 / 56.02 (n=100) | 88.50 / 88.50 (n=100) | 88.42 / 88.42 (n=100) |
| memory-002 / 1 | Native Image AOT — Java (GraalVM Native Image) [graalvm-native]; Native Image 25.0.4.1.1 | Serial (build-time) | 88.50 / 88.50 (n=100) | 88.41 / 88.41 (n=100) | 55.46 / 55.46 (n=100) | 88.56 / 88.56 (n=100) | 88.44 / 88.44 (n=100) |
| memory-002 / 1 | Native Image AOT — Java (GraalVM Native Image) [graalvm-native]; Native Image 25.0.4.1.1 | Epsilon (build-time) | 86.75 / 86.75 (n=100) | 86.87 / 86.87 (n=100) | Failed [F3] | 86.91 / 86.91 (n=100) | 86.96 / 86.96 (n=100) |

### Quarkus

| Run / trial | Execution target and kind | Collector | Default / default | 1 MiB / default | 1 MiB / 16 MiB | 1 MiB / 1024 MiB | 512 MiB / 1024 MiB |
| --- | --- | --- | --- | --- | --- | --- | --- |
| memory-002 / 1 | JVM — Java (Eclipse Temurin, HotSpot C2) [temurin-c2]; JDK 25.0.1+8 | Default (runtime selected Serial) | 112.89 / 112.89 (n=100) | 99.52 / 99.52 (n=100) | 98.59 / 98.59 (n=100) | 106.08 / 106.08 (n=100) | 136.00 / 136.00 (n=100) |
| memory-002 / 1 | JVM — Java (Eclipse Temurin, HotSpot C2) [temurin-c2]; JDK 25.0.1+8 | Serial | 107.31 / 107.31 (n=100) | 98.77 / 98.77 (n=100) | 99.17 / 99.17 (n=100) | 99.39 / 99.39 (n=100) | 135.91 / 135.91 (n=100) |
| memory-002 / 1 | JVM — Java (Eclipse Temurin, HotSpot C2) [temurin-c2]; JDK 25.0.1+8 | Parallel | 115.66 / 115.66 (n=100) | 111.40 / 111.40 (n=100) | 106.30 / 106.30 (n=100) | 111.48 / 111.48 (n=100) | 136.41 / 136.41 (n=100) |
| memory-002 / 1 | JVM — Java (Eclipse Temurin, HotSpot C2) [temurin-c2]; JDK 25.0.1+8 | G1 | 113.52 / 113.52 (n=100) | 111.60 / 111.60 (n=100) | 118.02 / 118.02 (n=100) | 111.05 / 111.05 (n=100) | 129.37 / 129.37 (n=100) |
| memory-002 / 1 | JVM — Java (Eclipse Temurin, HotSpot C2) [temurin-c2]; JDK 25.0.1+8 | ZGC | 139.63 / 139.63 (n=100) | 145.30 / 145.30 (n=100) | 124.50 / 124.50 (n=100) | 152.50 / 152.50 (n=100) | 151.98 / 151.98 (n=100) |
| memory-002 / 1 | JVM — Java (Eclipse Temurin, HotSpot C2) [temurin-c2]; JDK 25.0.1+8 | Shenandoah | 142.38 / 142.38 (n=100) | 146.42 / 146.42 (n=100) | 112.27 / 112.27 (n=100) | 146.73 / 146.73 (n=100) | 149.39 / 149.39 (n=100) |
| memory-002 / 1 | JVM — Java (Eclipse Temurin, HotSpot C2) [temurin-c2]; JDK 25.0.1+8 | Epsilon | 133.89 / 133.89 (n=100) | 134.08 / 134.08 (n=100) | Failed [F2] | 136.03 / 136.03 (n=100) | 134.98 / 134.98 (n=100) |
| memory-002 / 1 | Native Image AOT — Java (GraalVM Native Image) [graalvm-native]; Native Image 25.0.4.1.1 | Default (artifact uses Serial) | 35.94 / 35.94 (n=100) | 36.09 / 36.09 (n=100) | 32.72 / 32.72 (n=100) | 36.05 / 36.05 (n=100) | 36.10 / 36.10 (n=100) |
| memory-002 / 1 | Native Image AOT — Java (GraalVM Native Image) [graalvm-native]; Native Image 25.0.4.1.1 | Serial (build-time) | 36.22 / 36.22 (n=100) | 36.13 / 36.13 (n=100) | 33.16 / 33.16 (n=100) | 36.10 / 36.10 (n=100) | 36.20 / 36.20 (n=100) |
| memory-002 / 1 | Native Image AOT — Java (GraalVM Native Image) [graalvm-native]; Native Image 25.0.4.1.1 | Epsilon (build-time) | 35.73 / 35.73 (n=100) | 35.88 / 35.88 (n=100) | 35.71 / 35.71 (n=100) | 35.75 / 35.75 (n=100) | 35.74 / 35.74 (n=100) |

## Interpretation

### Collector and application effects

At the default heap profile in memory-002, Java (Eclipse Temurin, HotSpot C2) median RSS across available collectors ranged from 41.85 to 45.36 MiB for Console, 71.96 to 79.24 MiB for Swing, 130.50 to 319.65 MiB for Spring Boot, and 107.31 to 142.38 MiB for Quarkus. The corresponding Java (GraalVM Native Image) values ranged from 8.80 to 8.93 MiB for Console, 86.75 to 88.74 MiB for Spring Boot, and 35.73 to 36.22 MiB for Quarkus; Swing produced no valid Native Image measurement. These ranges span collector configurations and are single-trial observations.

The Temurin default collector resolved to Serial on this one-CPU, 1 GiB container. The default-heap Serial result was not identical to the explicit Serial-option result, but both select the same collector. Collector-to-collector differences were largest for Spring Boot under Temurin: its observed default-profile medians ranged from 130.50 MiB (default-selected Serial) to 319.65 MiB (Epsilon). Spring Boot with Epsilon also had the largest observed process peak: 345.34 MiB with Shenandoah and -Xms512m -Xmx1024m. Epsilon does not reclaim memory; these minimal survey results should not be generalized to long-running services.

### Heap settings

Within the default collector configuration in memory-002, changing the Temurin profile from default heap sizing to -Xms512m -Xmx1024m changed median RSS from 42.11 to 43.25 MiB for Console, 72.09 to 75.92 MiB for Swing, 130.50 to 273.32 MiB for Spring Boot, and 112.89 to 136.00 MiB for Quarkus. The largest change is consistent with the larger initial heap affecting committed/resident memory, especially for Spring Boot. Process RSS is still distinct from Java heap size.

For Native Image AOT with the default Serial build, the same profile change left these medians nearly unchanged: Console 8.93 to 8.94 MiB, Spring Boot 88.74 to 88.42 MiB, and Quarkus 35.94 to 36.10 MiB. The -Xms1m -Xmx16m profile reduced Spring Boot Native Image RSS to 56.02 MiB and Quarkus to 32.72 MiB, while Swing remained invalid. These values show the tested RSS response; they do not prove that 16 MiB is a generally sufficient heap.

Reducing -Xms to 1 MiB did not consistently reduce RSS. For example, Temurin Spring Boot rose from 130.50 to 135.00 MiB with default -Xmx, while Temurin Quarkus fell from 112.89 to 99.52 MiB. Results depend on the framework, collector, and runtime memory behavior. The three JVM 16 MiB failures and the Native Image Epsilon failure show that the 16 MiB setting is not viable for every app/collector combination. The five profiles are a small grid, not a search for the minimum viable heap.

### Sample variability and measurement limits

P10 equals the median in 125 of 181 successful survey trials. The median full-series RSS range was about 0.012 MiB, and the largest was 12.535 MiB (Quarkus, Temurin, Shenandoah, -Xms512m -Xmx1024m); that trial’s final-30-sample range was zero. Across all 181 trials, the largest final-30-sample range was 0.086 MiB. This describes observed short-window variation; no stability threshold was defined, so it is not a formal steady-state classification.

Process RSS, sampled process high-water RSS, and cgroup memory are separate metrics. The tables use process RSS. The summary.csv files retain P10, minimum, maximum, range, and high-water and cgroup summaries. Cgroup memory includes container accounting and must not be substituted for application-process RSS. One trial per configuration and a 10-second survey limit claims about replication, longer-lived memory behavior, or the minimum heap needed for sustained operation.

## Code under test

### Console — Java

Source: [ConsoleHello.java](../java-memory-test/console/src/ConsoleHello.java), method main.

```java
import java.util.concurrent.CountDownLatch;
import java.lang.management.ManagementFactory;

public final class ConsoleHello {
    private static final String MESSAGE = "Hello World";
    private static final CountDownLatch STOP = new CountDownLatch(1);

    public static void main(String[] args) throws InterruptedException {
        System.out.println(MESSAGE);
        var heap = ManagementFactory.getMemoryMXBean().getHeapMemoryUsage();
        System.out.printf("MEMORY_TEST_HEAP init=%d used=%d committed=%d max=%d%n",
                heap.getInit(), heap.getUsed(), heap.getCommitted(), heap.getMax());
        System.out.println("MEMORY_TEST_READY application=console");
        System.out.flush();
        STOP.await();
    }
}
```

### Swing — Java

Source: [SwingHello.java](../java-memory-test/swing/src/SwingHello.java), method main and its event-dispatch callback.

```java
public static void main(String[] args) throws Exception {
    SwingUtilities.invokeAndWait(() -> {
        var frame = new JFrame("Hello World");
        frame.setDefaultCloseOperation(JFrame.DO_NOTHING_ON_CLOSE);
        frame.setLayout(new BorderLayout());
        frame.add(new JLabel("Hello World", SwingConstants.CENTER));
        frame.setSize(320, 120);
        frame.setLocationRelativeTo(null);
        frame.setVisible(true);
        if (!frame.isShowing()) {
            throw new IllegalStateException("Swing frame is not showing");
        }
        var heap = ManagementFactory.getMemoryMXBean().getHeapMemoryUsage();
        System.out.printf("MEMORY_TEST_HEAP init=%d used=%d committed=%d max=%d%n",
                heap.getInit(), heap.getUsed(), heap.getCommitted(), heap.getMax());
        System.out.println("MEMORY_TEST_READY application=swing frame_visible=true");
        System.out.flush();
    });
    STOP.await();
}
```

### Spring Boot — Java

Source: [SpringHelloApplication.java](../java-memory-test/spring-boot/src/main/java/benchmarks/springhello/SpringHelloApplication.java), methods helloWorld and ready.

```java
@GetMapping(value = "/hello-world", produces = MediaType.TEXT_PLAIN_VALUE)
public String helloWorld() {
    return "Hello World";
}

@EventListener(ApplicationReadyEvent.class)
public void ready() {
    var heap = ManagementFactory.getMemoryMXBean().getHeapMemoryUsage();
    System.out.printf("MEMORY_TEST_HEAP init=%d used=%d committed=%d max=%d%n",
            heap.getInit(), heap.getUsed(), heap.getCommitted(), heap.getMax());
    System.out.println("MEMORY_TEST_READY application=spring-boot port=8080");
    System.out.flush();
}
```

### Quarkus — Java

Source: [HelloResource.java](../java-memory-test/quarkus/src/main/java/benchmarks/quarkushello/HelloResource.java), methods helloWorld and ready.

```java
@GET
@Produces(MediaType.TEXT_PLAIN)
public String helloWorld() {
    return "Hello World";
}

void ready(@Observes StartupEvent event) {
    var heap = ManagementFactory.getMemoryMXBean().getHeapMemoryUsage();
    System.out.printf("MEMORY_TEST_HEAP init=%d used=%d committed=%d max=%d%n",
            heap.getInit(), heap.getUsed(), heap.getCommitted(), heap.getMax());
    System.out.println("MEMORY_TEST_READY application=quarkus port=8080");
    System.out.flush();
}
```
