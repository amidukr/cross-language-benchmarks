# Docker build and execution rules

## Build and run in Docker

- Compile, build, and publish all benchmark targets in Docker. Run dataset
  generation, correctness checks, diagnostics, and benchmark measurements in
  Docker as well.
- The host may invoke Docker and collect result files. All compilers, SDKs,
  language runtimes, and benchmark dependencies must come from the images.
- Keep Dockerfiles and build and run commands in the repository. Pin base-image
  versions or digests and toolchain versions. Use the same target architecture
  and equivalent CPU and memory limits for comparable runs.
- Use the same input data across targets. Write result CSVs and diagnostic logs
  to a mounted output directory so they remain available on the host.

## Timing boundaries

- Build or publish the workload before timing starts.
- For fresh-process measurements, start the container first, then time the
  benchmark process from launch through exit from inside that container.
- Run warmup and steady-state measurements in the same benchmark process.
- Record the image reference, architecture, and any CPU or memory limits used
  for the run.
