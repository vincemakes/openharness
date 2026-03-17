# OpenHarness — Agent Instructions

This repository uses [OpenHarness](https://github.com/user/openharness) for structured development.
All task state lives in `.openharness/`. The CLI is your only interface to task state.

## Lifecycle

Every change goes through this sequence:

1. **intake** — task created, goal captured in `task.md`
2. **planning** — approach written in `plan.md` (required before any code)
3. **implementing** — code changes made
4. **verifying** — verification commands run, evidence recorded in `verify.md`
5. **fixing** — failed verification triggers a fix loop
6. **ready_for_human_review** — verification passed, handoff written
7. **blocked** — repeated failures exceed limit, needs human intervention

## Before You Start

```bash
openharness status                  # Check for an active task
openharness start-task "<goal>"     # Create a new task
```

## Task Commands

```bash
openharness advance                 # Transition to next state (intake→planning, planning→implementing)
openharness verify                  # Run verification commands
openharness verify --fast           # Run fast layer only
openharness verify --full           # Run all layers (fast + standard + full)
openharness verify --layer <name>   # Run up to specified layer
openharness verify --only           # Run the target layer only (no cumulative)
openharness handoff                 # Write handoff summary, finalize state
openharness commit                  # Stage and commit (requires ready_for_human_review)
openharness pr                      # Generate PR draft
```

## intake → planning Gate

Before `openharness advance` will transition intake→planning, `task.md` must have:

- **`## Done Condition`** — non-empty: specific, measurable criteria for task completion
- **`## Verification Path`** — non-empty: how verification will be run (e.g. "unit tests", "interactive verify")

These are not optional. Fill them before calling advance.

## planning → implementing Gate

`plan.md` must have a non-empty `## Goal` section.

## Rules (Enforced by Hooks)

**Rule 1: No implementation without a plan.**
The PreToolUse hook blocks Edit/Write/NotebookEdit while status is `intake` or `planning`.

**Rule 2: No completion without verification.**
`openharness handoff` requires verify.md to have passing evidence.

**Rule 3: Explicit final state.**
Every task ends in `ready_for_human_review` or `blocked`. No silent "done".

**Rule 4: CLI is the only state mutation path.**
Do not manually edit `status.json`. Use CLI commands.

## Task Artifacts

Each task lives in `.openharness/tasks/<task-id>/`:

| File | Contents |
|------|----------|
| `task.md` | Original request, Done Condition, Verification Path |
| `plan.md` | Implementation approach (fill before coding) |
| `status.json` | Current state (machine-readable, do not edit) |
| `verify.md` | Verification evidence (auto-generated) |
| `handoff.md` | Final summary (auto-generated) |
| `verify-interactive.md` | Interactive verification steps (if configured) |

## Interactive Verification (Playwright)

If `interactive_verify.dev_server_command` is configured:

```bash
openharness interactive-verify start     # Start dev server, prepare screenshots dir
openharness interactive-verify complete pass   # Record pass, kill server
openharness interactive-verify complete fail   # Record fail, kill server, enter fixing
```

## Maintenance

```bash
openharness maintain    # Detect stale tasks, orphaned worktrees, blocked tasks
openharness gc          # Remove worktrees/branches for terminal-state tasks
openharness gc --purge  # Also remove task directories
```

## Session Continuity

At the start of each session, check `.openharness/HANDOFF.md` for the last known state of the repository and any pending work.
