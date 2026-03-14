# OpenHarness Rules

These rules are enforced by hooks. Violating them will block your operation.

## Rule 1: No implementation without a plan

You cannot edit or write project files while the active task is in `intake` or `planning` status. Complete the plan first.

**Enforced by:** PreToolUse hook blocks Edit/Write when status is intake or planning.

## Rule 2: No completion without verification

You cannot claim work is done without running `openharness verify`. The handoff command requires verification evidence.

**Enforced by:** `openharness handoff` checks for verify.md content.

## Rule 3: Explicit final state

Every task must end in one of two states:
- `ready_for_human_review` — verification passed
- `blocked` — repeated failures or unresolvable issue

There is no "done" state. Human review is always required.

## Rule 4: CLI is the only state mutation path

Do not manually edit `status.json`. Use CLI commands to change task state. Skills guide you to the right command but do not change state themselves.
