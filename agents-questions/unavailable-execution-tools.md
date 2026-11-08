# What should an agent do when required execution tools are unavailable?

## Question

The agent's execution environment does not expose one or more tools required to
complete a task, such as Docker, Podman, a compiler, a runtime, a profiler, or a
diagnostic decoder. Should the agent reduce the task to locally available
targets, mark the remaining targets as skipped, or wait for the missing tools?

Where should evidence produced by a user-run collection script be stored?

## Answer

When practical, prepare reproducible scripts that the user can run on a host
where the required tools are available. The scripts must collect the requested
data, logs, manifests, commands, versions, statuses, and failure reasons into a
self-contained output directory. The user can then make that directory
available in the repository workspace, and the agent can validate and analyze
the artifacts without access to the original execution host.

Use the output location already defined by the applicable project-structure
rule. Do not invent a separate transfer directory. For example, assembly and
code-generation evidence belongs under:

```text
reports/<workload>-test/assembly/
  <target-id>/
    <docker|podman|native>/
      <diagnostic-run-id>/
```

The collection scripts should default to that location. After the user runs
them, the agent should analyze the returned evidence in place and write the
analysis to the standard path defined by the project-structure rule, such as:

```text
reports/<workload>-test-assembly.md
```

Follow the repository's task and rule requirements for argument validation,
native and container separation, provenance, clean performance runs,
diagnostic isolation, and failure handling. Support every required execution
mode, such as native, Docker, and Podman, when the task and rules require them.

Do not narrow the requested scope or ask the user whether to wait merely
because the agent environment lacks a tool when this script-and-return workflow
can preserve the intended scope. Report targets as skipped only after the
collection script has attempted them on the capable host and recorded a
specific unavailable dependency or capture limitation, or when preparing a
remote collection workflow is itself impossible.
