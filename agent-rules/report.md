# Benchmark report format

Every benchmark runner produces a `<target-id>-report.csv` file using the same
schema, where `<target-id>` is the canonical target ID passed with `--target`.
Each row records one metric for one sample. A suite can combine reports by
keeping one header and appending the data rows.

## CSV format

- Use UTF-8, comma-separated fields, a header, and a period as the decimal
  separator. Quote fields containing commas or quotes and double embedded quotes.
- Use the column order below. Write numbers without grouping separators or units.
  Leave optional values empty when unavailable. Use zero only for a measured zero.
- Keep metric names and units consistent across runners. Use schema version `2`.
  Change `schema_version` if a column or its meaning changes.

| Column           | Meaning                                                                    |
| ---------------- | -------------------------------------------------------------------------- |
| `schema_version` | Use `2` for this schema.                                                   |
| `run_id`         | Unique ID for a benchmark invocation or suite.                             |
| `benchmark`      | Workload name, such as `edigits`.                                          |
| `case_id`        | Workload inputs and settings, such as `digits-10000`.                      |
| `language`       | Language name, such as `Java`, `Go`, or `Python`.                          |
| `target`         | Runtime or toolchain ID, such as `temurin-c2` or `graalvm-jit`.            |
| `config_id`      | Build and runtime profile, such as `default` or `pgo`.                     |
| `toolchain`      | Exact compiler or runtime distribution and build.                          |
| `flags`          | Build and runtime options. Empty means the recorded profile uses defaults. |
| `environment`    | Hardware, OS, and architecture of the measurement host.                    |
| `trial`          | One-based process repetition within a run, case, target, and profile.      |
| `phase`          | `startup`, `warmup`, `unclassified`, or `steady_state`.                    |
| `sample`         | One-based index that increases within the trial across phases.             |
| `elapsed_ms`     | Milliseconds from trial start to the end of the sample.                    |
| `metric`         | A stable metric name from the table below.                                 |
| `value`          | Numeric observation in the specified unit.                                 |
| `unit`           | Fixed unit for this metric.                                                |

## Standard metrics

| Metric        | Unit    | Definition                                                                                                                 |
| ------------- | ------- | -------------------------------------------------------------------------------------------------------------------------- |
| `wall_time`   | `ms`    | Wall-clock duration of the measured operation or window. For `startup`, measure process launch to exit for one invocation. |
| `time_per_op` | `ns/op` | Timed window divided by the number of completed operations.                                                                |
| `throughput`  | `ops/s` | Completed operations divided by the timed window in seconds.                                                               |
| `peak_rss`    | `bytes` | Maximum resident set size of the process during its lifetime.                                                              |
| `latency_p99` | `ms`    | 99th-percentile latency of individual operations in the sample window.                                                     |

Define one operation in the benchmark task so all targets count the same work.
Emit only metrics the runner measures. If a workload needs an additional metric,
define its name, unit, and measurement boundary here before using it.

## Sample rules

- Use one trial per independent process. Use separate trials for launch-to-exit
  measurements and for repeated in-process measurements.
- Give all metrics from the same sample the same trial, phase, sample index, and
  elapsed time. Use a new index for the next measurement window.
- Classify a window as `steady_state` only after it meets the workload's stability
  criteria. If analysis cannot determine a sample's phase, keep it as
  `unclassified`. If the trial never demonstrates stability, report that outcome
  in the benchmark run log.
- Use `unclassified` for measured in-process samples whose phase has not yet
  been determined. Later analysis may produce a derived CSV that classifies
  those samples as `warmup` or `steady_state`. Preserve the original CSV and do
  not overwrite its raw phase assignments.
- Keep JIT verification and correctness diagnostics in the run log. Include only
  measurements from successful, correctness-checked trials in the results CSV.
- Keep individual samples in the CSV. Compute summaries and charts from those
  samples. For a warmup chart, filter to a workload and metric, then plot
  `elapsed_ms` against `value`, with a series per target and trial.
