# Benchmark runner interface

Every implementation of a workload must expose the same command-line interface.
The implementation's `run.sh` accepts these options and forwards the workload
settings unchanged to the benchmark application running inside Docker.

## Standard workload options

| Option             | Value                   | Meaning                                                             |
| ------------------ | ----------------------- | ------------------------------------------------------------------- |
| `--size`           | Positive integer        | Number of elements in the prepared dataset.                         |
| `--seed`           | Unsigned 64-bit integer | Optional random seed. Generate a seed from the system when omitted. |
| `--repeats`        | Positive integer        | Number of full dataset passes in one timed benchmark operation.     |
| `--value`          | Signed 32-bit integer   | Input value supplied to each workload operation.                    |
| `--warmup-samples` | Nonnegative integer     | Number of timed samples designated as warmup.                       |
| `--samples`        | Positive integer        | Number of measured samples recorded initially as `unclassified`.    |
| `--output`         | Directory path          | Host output directory for `results.csv` and run logs.               |

Use the `--option value` form. Do not use positional arguments for standard
workload settings. Each application must also support `--help`, print a concise
usage message, and exit successfully without running the benchmark.

## Argument behavior

- A workload task may define defaults for workload options. The application
  must report every effective value, including a system-generated seed.
- Supplying the same seed to the same implementation and toolchain must generate
  the same dataset. Different languages are not required to generate identical
  datasets from the same seed unless the workload task says otherwise.
- Reject missing option values, malformed numbers, out-of-range values, unknown
  options, and conflicting duplicate options. Print the error and usage summary
  to standard error and exit with a nonzero status.
- Validate arguments before preparing data or recording samples.
- Do not silently clamp, wrap, or otherwise change an argument.
- `--warmup-samples` and `--samples` are separate counts. Run all configured
  warmup samples first, followed by all measured samples. Sample indices increase
  across both groups.

## Script behavior

`run.sh` must use the workload directory as its working context and mount the
host directory supplied with `--output` at a consistent container output path.
It may translate only this path when passing `--output` to the application.
Ensure result files remain owned and writable by the invoking host user where
the container platform supports it. Create no benchmark results outside the
selected output directory.

Forward the benchmark application's exit status. A failed argument check,
checksum mismatch, timeout, signal, or incomplete run invalidates the trial and
must not produce successful measurement rows.

Write diagnostic messages and errors to standard error. Keep standard output
machine-readable or empty so repository-level orchestration can consume it.

Follow [report.md](report.md) for CSV fields, phases, sample numbering, and
successful-trial requirements.
