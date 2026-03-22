---
name: interactive-verify
description: Use when performing interactive browser-based verification of a task. Guides the agent through dev server startup, browser interaction via $B commands, screenshot capture, and evidence recording.
---

# Interactive Browser Verification

You are performing interactive browser-based verification for the active OpenHarness task. This verification uses the self-contained browse binary (`$B`) to drive a headless Chromium browser.

## Pre-flight Check

Before starting, verify the browse binary is available:

1. Check if `$B` is set and the binary exists at that path
2. If the binary is **not available**:
   - The `openharness interactive-verify start` command will auto-build it
   - If auto-build fails, run `browse/setup` manually
   - **Do not proceed** until the binary is confirmed working

## Step 1: Start Infrastructure

Run:

```bash
openharness interactive-verify start
```

This will:
- Ensure the browse binary is built (auto-runs `browse/setup` if missing)
- Start the dev server in the background
- Poll until the server is ready
- Create the `screenshots/` directory
- Export `$B` pointing to the browse binary
- Output the verification steps from `verify-interactive.md`

Parse the output to get:
- **Server URL** — where to navigate
- **Screenshots dir** — where to save screenshots
- **Step list** — what to verify

## Step 2: Execute Verification Steps

For each step in the verification spec:

1. **Announce** the step you're about to perform
2. **Execute** using `$B` commands:
   - `$B goto <url>` — navigate to URLs
   - `$B click <selector>` — click elements (use CSS selectors or @refs)
   - `$B fill <selector> <value>` — fill input fields
   - `$B snapshot -i` — get interactive elements with @e refs
   - `$B screenshot <path>` — capture screenshots
3. **Screenshot** — save to `screenshots/step-NN.png` after each step
4. **Record** — note the result (pass/fail and what you observed)

### Typical Interaction Flow

```bash
# Navigate to the page
$B goto http://localhost:3000

# Get interactive elements
$B snapshot -i

# Interact using refs from snapshot
$B fill @e2 "test@example.com"
$B click @e4

# Verify result
$B snapshot -i
$B screenshot screenshots/step-01.png

# Check for errors
$B console --errors
```

### Key Commands Quick Reference

| Action | Command |
|--------|---------|
| Navigate | `$B goto <url>` |
| Click | `$B click <sel\|@ref>` |
| Fill input | `$B fill <sel\|@ref> <value>` |
| Get page state | `$B snapshot -i` |
| Screenshot | `$B screenshot <path>` |
| Check text | `$B text` |
| Wait for element | `$B wait <sel>` |
| Console errors | `$B console --errors` |

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
- Refs (`@e1`, `@c1`) become stale after navigation — re-run `$B snapshot -i`
- The browse server auto-shuts down after 30 min idle
