# Docker and Podman build and execution rules

Use the compiler, runtime, and build tools defined in [tooling.md](tooling.md).

## Container engine selection

Support both Docker and Podman for containerized builds and runs. Use Docker
by default and allow callers to select Podman with `CONTAINER_ENGINE=podman`.
Accept `docker` and `podman` as the supported values. Fail clearly if the
selected engine is unavailable or the value is unsupported.

Use the selected engine for all container operations. Workload-level batch
scripts must preserve `CONTAINER_ENGINE` when invoking per-language scripts.
Use the same Dockerfiles, image tags, benchmark arguments, and output paths
with either engine. Use the same engine to build and run a target.

## Build and run in containers

These rules apply to `build.sh` and `run.sh`. The optional host-native path is
defined by `build_native.sh` and `run_native.sh` in
[project-structure.md](project-structure.md) and must preserve the same workload
and measurement contract.

- Compile, build, and publish all benchmark targets in containers. Run dataset
  generation, correctness checks, diagnostics, and benchmark measurements in
  containers as well.
- The host may invoke the container engine and collect result files. All
  compilers, SDKs, language runtimes, and benchmark dependencies must come from
  the images.
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
- Record the container engine and its version, the image reference, the
  architecture, and any CPU or memory limits used for the run.
