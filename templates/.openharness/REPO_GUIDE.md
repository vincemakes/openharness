# OpenHarness Repo Guide

This repository is managed by OpenHarness. Development tasks follow a structured lifecycle.

## Lifecycle

1. **intake** — task created, goal captured
2. **planning** — plan.md written with approach, affected files, verification commands
3. **implementing** — code changes made (only allowed after plan exists)
4. **verifying** — verification commands executed, evidence recorded
5. **fixing** — failed verification triggers fix loop
6. **ready_for_human_review** — verification passed, handoff written
7. **blocked** — repeated failures, needs human intervention

## Key Rules

- No implementation before planning
- No completion claim without verification evidence
- Every task ends in an explicit state

## Task Artifacts

Each task lives in `.openharness/tasks/<task-id>/` and contains:

- `task.md` — original request, constraints, success criteria
- `plan.md` — implementation approach (must be filled before coding)
- `status.json` — current state (machine-readable)
- `verify.md` — verification evidence (auto-generated)
- `handoff.md` — final summary (auto-generated)

## CLI Commands

```bash
openharness start-task "<goal>"   # Create a task
openharness status                # Check current state
openharness verify                # Run verification
openharness handoff               # Complete the task
```
