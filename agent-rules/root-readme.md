# Root README

Keep the repository-root `README.md` as the entry point for readers who have
not seen the task history. It must let them understand the project's purpose,
which benchmarks have been completed, what the main measurements show, and
where to find the supporting analysis.

## Required content

The README must include:

1. An **Overview** section explaining the purpose of the benchmarks: comparing
   equivalent workloads across languages, compilers, and runtimes under
   documented, reproducible conditions. State what the benchmark is intended
   to reveal and any important limit on what it measures.
2. A list or table of every benchmark completed so far. Give each benchmark a
   short description of its workload and scope. Identify work still in
   progress as such; do not present it as completed.
3. A results table with the most useful headline measurements for each
   completed benchmark. Include units, the relevant targets or comparison,
   trial/configuration context, and a concise interpretation. Keep the table
   selective; link to the analysis for full target-level data and methodology.
4. Links from each benchmark entry to all related human-readable analysis
   files, including timing, matched-comparison, assembly, vectorization, or
   memory analysis when those files exist. Do not invent links or results for
   analyses that have not been produced yet.

## Accuracy and maintenance

- Update the README when a benchmark is completed, its analysis changes, or a
  new analysis file is added. Keep the benchmark list, headline figures, and
  analysis links in sync with the reports.
- Copy measurements from the analysis files and preserve their units, trial
  counts, and relevant configuration. Clearly label provisional, single-trial,
  unstable, or otherwise limited results; do not turn them into general
  language rankings.
- Use explicit language and runtime names from `targets.md` (for example,
  **Java (Eclipse Temurin, HotSpot C2)**) rather than ambiguous vendor or
  target shorthand.
- Prefer a small number of meaningful results over a dump of all CSV rows.
  The detailed analysis remains the source for methodology, full results,
  caveats, and code examples.
- Keep overview and navigation concise. Link to task specifications,
  workload instructions, evidence, and analysis instead of copying their full
  contents into the root README.
