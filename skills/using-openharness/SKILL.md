---
name: using-openharness
description: Use when starting any conversation in a repo that has OpenHarness initialized (.openharness/ directory exists). Detects harness state and routes development work into the enforced lifecycle.
---

# Using OpenHarness

You are working in a repository managed by OpenHarness — a local development harness that enforces a structured lifecycle for development tasks.

## First: Check Harness State

Before doing any work, run:

```bash
openharness status
```

This tells you whether there is an active task and what state it is in.

## If No Active Task

If the user wants you to implement something, create a task first:

```bash
openharness start-task "<goal>"
```

## Lifecycle

Every task follows this enforced sequence:

1. **intake** — task created. Fill in `task.md` with constraints and success criteria.
2. **planning** — advance with `openharness advance`. Write `plan.md` with approach, affected files, verification commands.
3. **implementing** — advance with `openharness advance` (requires plan.md content). Now you can edit project files.
4. **verifying** — run `openharness verify` to execute configured verification and record evidence.
5. **fixing** — if verification fails, fix the issue and run `openharness verify` again.
6. **handoff** — run `openharness handoff` to produce the final summary.

## Enforcement

OpenHarness uses hooks to enforce ordering:

- **Edit/Write operations are blocked** when the task is in `intake` or `planning` state.
- **Handoff requires verification evidence.**

This is not optional guidance — the hooks will physically prevent you from editing project files before the plan is ready.

## Key Rule

The CLI is the only way to change task state. Do not manually edit `status.json`. Use:
- `openharness advance` to move forward through intake → planning → implementing
- `openharness verify` to run verification
- `openharness handoff` to complete the task

## Files Reference

- `.openharness/RULES.md` — enforcement rules
- `.openharness/REPO_GUIDE.md` — lifecycle documentation
- `.openharness/tasks/<task-id>/` — task artifacts
