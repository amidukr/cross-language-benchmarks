# Project instructions

This project benchmarks equivalent workloads across programming languages, compilers, and runtimes. The goal is to produce reproducible comparisons under documented conditions.

## Tasks

All task specifications live in [`agent-tasks/`](agent-tasks/). Before starting work, read the requested task and any specifications it references. Use the task's acceptance criteria to verify completion.

Maintain [`agent-tasks/task-execution.md`](agent-tasks/task-execution.md) every
time a task is executed. Before doing task work, add or refresh its row and
classify every rule as `done`, `to be done`, or `not applicable`. Update the
row as work progresses and again before reporting completion. Follow the
maintenance instructions in that file; a task is not complete while an
applicable rule remains `to be done`.

## Rules

Shared rules and guidelines live in [`agent-rules/`](agent-rules/). Before writing, changing, or running a benchmark, read the applicable rules, starting with [Benchmark targets and measurement](agent-rules/targets.md).

## Questions and clarifications

Reusable answers to agent questions live in
[`agents-questions/`](agents-questions/). Before asking the user how to proceed
when tools, runtimes, container engines, permissions, or other execution
capabilities are unavailable, check this directory for an existing
clarification and follow it when applicable.
