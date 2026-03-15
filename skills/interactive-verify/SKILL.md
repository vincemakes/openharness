---
name: interactive-verify
description: Use when performing interactive browser-based verification of a task. Guides the agent through dev server startup, Playwright-driven browser interaction, screenshot capture, and evidence recording.
---

# Interactive Browser Verification

You are performing interactive browser-based verification for the active OpenHarness task. This verification uses Playwright MCP tools to drive a real browser.

## Pre-flight Check

Before starting, verify Playwright MCP tools are available:

1. Check if `mcp__playwright__*` tools exist (e.g., `mcp__playwright__browser_navigate`)
2. If Playwright MCP is **not available**:
   - Warn: "Playwright MCP not detected. Interactive verification requires the Playwright MCP server."
   - Suggest: "Add Playwright MCP to `.claude/settings.local.json`, or use `openharness verify` for shell-based verification instead."
   - **Stop here** — do not proceed without Playwright MCP.

## Step 1: Start Infrastructure

Run:

```bash
openharness interactive-verify start
```

This will:
- Start the dev server in the background
- Poll until the server is ready
- Create the `screenshots/` directory
- Output the verification steps from `verify-interactive.md`

Parse the output to get:
- **Server URL** — where to navigate
- **Screenshots dir** — where to save screenshots
- **Step list** — what to verify

## Step 2: Execute Verification Steps

For each step in the verification spec:

1. **Announce** the step you're about to perform
2. **Execute** using Playwright MCP tools:
   - `mcp__playwright__browser_navigate` — navigate to URLs
   - `mcp__playwright__browser_click` — click elements
   - `mcp__playwright__browser_type` — type into inputs
   - `mcp__playwright__browser_snapshot` — get page state
   - `mcp__playwright__browser_screenshot` — capture screenshots
3. **Screenshot** — save to `screenshots/step-NN.png` after each step
4. **Record** — note the result (pass/fail and what you observed)

## Step 3: Write Evidence

Write your findings to `verify-interactive-evidence.md` in the task directory:

```markdown
## Step 1: [step description]
- **Action:** [what you did]
- **Expected:** [what should happen]
- **Actual:** [what happened]
- **Result:** PASS / FAIL
- **Screenshot:** `screenshots/step-01.png`

## Step 2: ...
```

## Step 4: Complete

Determine the overall result:
- **pass** — all steps passed
- **fail** — any step failed

Run:

```bash
openharness interactive-verify complete pass
# or
openharness interactive-verify complete fail
```

This will:
- Stop the dev server
- Merge your evidence into `verify.md`
- Transition the task state appropriately

## Important Notes

- Always capture a screenshot after each verification step
- If a step fails, still continue with remaining steps to get full evidence
- The dev server is managed by OpenHarness — don't start/stop it manually
- If the dev server crashes mid-verification, run `openharness interactive-verify start` again
