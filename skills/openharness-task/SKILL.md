---
name: openharness-task
description: Use when executing a development task inside an OpenHarness-managed repo. Guides the agent through the full task lifecycle including planning, implementation, verification, and handoff.
---

# OpenHarness Task Execution

You are executing a development task under OpenHarness control. Follow this sequence exactly.

## Phase 1: Intake

After `openharness start-task "<goal>"`:

1. Read the generated `task.md`
2. Fill in constraints, success criteria, and assumptions
3. Run `openharness advance` to move to planning

## Phase 2: Planning

1. Write `plan.md` with:
   - **Goal**: what you're trying to achieve
   - **Affected Files**: list every file you expect to modify or create
   - **Approach**: step-by-step implementation plan
   - **Verification Commands**: what commands will prove success
   - **Risks**: what could go wrong
2. Run `openharness advance` to move to implementing

The advance command will verify that plan.md has real content in the Goal section.

## Phase 3: Implementation

Now you can edit project files. The PreToolUse hook will allow Edit/Write operations.

Implement according to your plan. If you discover the plan needs changes, update plan.md as you go.

## Phase 4: Verification

Run:

```bash
openharness verify
```

This executes the verification command configured in `.openharness/config.json` and writes evidence to `verify.md`.

- If verification **passes**: status moves to `ready_for_human_review`
- If verification **fails**: status moves to `fixing`

## Phase 5: Fix Loop

If verification failed:

1. Read `verify.md` for failure details
2. Fix the issue
3. Run `openharness verify` again
4. If max attempts exceeded, task becomes `blocked`

## Phase 6: Handoff

Run:

```bash
openharness handoff
```

This produces `handoff.md` with a summary. Final state is one of:
- `ready_for_human_review` — verification passed
- `blocked` — repeated failures

## CLI Quick Reference

```bash
openharness start-task "<goal>"   # Create task
openharness advance               # Move to next state
openharness status                # Check current state
openharness verify                # Run verification
openharness handoff               # Produce final summary
```
