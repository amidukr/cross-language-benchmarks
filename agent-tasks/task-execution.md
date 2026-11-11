# Task execution status

This file tracks how every task applies and satisfies the shared rules in
[`agent-rules/`](../agent-rules/). It is a live execution checklist, not a
replacement for the task specification, evidence, or acceptance criteria.

## Execution matrix

| Task | Title | `targets.md` | `tooling.md` | `docker.md` | `runner.md` | `project-structure.md` | `report.md` | `analysis.md` | `assembly-analysis.md` |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1.1 | Implement the virtual dispatch benchmark | done | done | done | done | done | done | not applicable | not applicable |
| 1.2 | Analyze the virtual dispatch results | done | not applicable | not applicable | not applicable | done | done | done | not applicable |
| 1.3 | Analyze virtual dispatch assembly | done | done | done | done | done | done | not applicable | done |
| 2.1 | Implement the enum dispatch benchmark | done | done | done | done | done | done | not applicable | not applicable |
| 2.2 | Analyze the enum dispatch results | done | not applicable | not applicable | not applicable | done | done | done | not applicable |
| 2.3 | Analyze enum dispatch assembly | done | done | done | done | done | done | not applicable | done |
| 2.4 | Diagnose enum-dispatch vectorization | done | done | done | not applicable | done | done | not applicable | done |
| 3.1 | Validate virtual-versus-enum dispatch differences | done | done | done | done | done | done | done | not applicable |
| 3.2 | Create the project README | done | done | done | done | done | done | done | done |
| 4.1 | Measure Java application RSS across selected heap profiles | to be done | to be done | to be done | to be done | to be done | to be done | to be done | not applicable |

## Status values

Every rule cell must contain exactly one of these values:

- `done`: The rule applies to the task, and its requirements have been
  completed and verified for the current task scope.
- `to be done`: The rule applies, but some required work or verification is
  still outstanding.
- `not applicable`: The rule does not apply to this task and will never be
  executed as part of it. Do not use this value merely because work is
  deferred, blocked, unavailable, or inconvenient.

## Maintenance procedure

1. Before starting a task, read its specification and referenced rules, add
   its row if missing, and reconsider every rule cell for the requested scope.
2. Set each applicable rule to `to be done` before performing work. A previous
   `done` value may remain only when resuming the same task scope and its
   evidence is still valid.
3. Change a cell to `done` only after that rule's work and verification are
   complete. Keep it `to be done` when any requirement remains, including work
   blocked on user-run evidence or an unavailable external tool.
4. Use `not applicable` only when the rule has no requirements for the task.
   If scope changes make the rule relevant, change it immediately to
   `to be done`.
5. Update the row after material scope changes and milestones, and perform a
   final update before reporting task completion. No applicable cell may
   remain `to be done` when a task is declared complete.
6. Use the task number and title from its specification. Keep rows in numeric
   order, retain completed task history, and do not create duplicate rows for
   reruns of the same task unless the task specification assigns a new number.
7. Keep one column for every Markdown rule file in `agent-rules/`. When a rule
   is added, renamed, or removed, update the table structure before executing
   another task. Non-rule support files, such as schema examples, do not get a
   column.

