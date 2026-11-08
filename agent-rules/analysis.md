# Benchmark analysis

Use these rules when analyzing benchmark reports produced under
[report.md](report.md). Workload tasks define the operation, primary metric,
input paths, output path, and any workload-specific interpretation.

## Inputs and validation

- Record every source report and log filename used in the analysis, along with
  the selected run IDs.
- Validate the CSV schema, schema version, metric names, units, and required
  fields before calculating summaries.
- Detect and report duplicate rows, duplicate trials, incomplete trials,
  missing targets, unsuccessful runs, and missing provenance. Exclude invalid
  data only when necessary, and document each exclusion and its reason.
- Preserve the original CSVs and logs. Write classifications, filtered data,
  and other derived results to separate files when the task requires them.
- If no usable inputs are available, identify what is missing and leave
  numerical comparisons empty.

## Comparable groups

- Compare results only when workload settings, case, configuration, host,
  execution mode, and resource controls match. Separate groups when any of
  these affect comparability.
- Keep native and container runs separate. Split Docker and Podman runs when
  the logs identify both engines.
- Use logs to verify effective arguments, correctness checks, execution mode,
  toolchain, runtime flags, environment, and resource controls. State when
  missing provenance prevents or weakens a comparison.
- Follow the workload specification when equal inputs can produce equivalent
  rather than identical datasets, such as when implementations use different
  random-number generators.

## Samples and stability

- Keep startup, warmup, unclassified, and steady-state measurements separate.
  Do not silently relabel or combine phases.
- Inspect each trial's ordered samples against elapsed time. Describe warmup
  trends, level shifts, spikes, and other visible transitions.
- Use the workload's documented stability criterion when one exists. Otherwise,
  state a common criterion before applying it, including its window size,
  tolerance, minimum sample count, and statistic being tested.
- Keep inconclusive samples unclassified. Report trials that do not demonstrate
  stability within the available samples.
- Retain slow samples and spikes. Do not discard outliers solely because they
  are slow; document every exclusion.

## Summaries and comparisons

- Define the primary metric and unit before comparing targets. Clearly label
  any derived metric and show how it is calculated.
- Summarize each trial first, then compare the trial summaries so a trial with
  more samples cannot dominate the result.
- For each comparable group, report at least the target, trial count, sample
  count, median, and a stated measure of spread.
- Label results based on only one trial. Do not present within-trial sample
  count as independent replication.
- State what the benchmark operation includes. Attribute a difference to one
  isolated mechanism only when a matched control isolates that mechanism.

## Diagnostics and conclusions

- Use diagnostic logs to explain observed transitions only when the evidence
  supports the explanation. Distinguish confirmed runtime events from plausible
  interpretations.
- Identify missing startup data, diagnostic data, independent trials, stability
  evidence, or other limitations that constrain the conclusions.
- Explain what the measurements support, what remains uncertain, and which
  additional measurements would resolve the uncertainty.
