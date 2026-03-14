---
name: verify-task
description: Run verification on the active OpenHarness task
allowed-tools: Bash, Read
---

Run verification for the active OpenHarness task.

1. Run `openharness verify`
2. Read the generated verify.md for results
3. If verification failed, diagnose and fix the issue, then run `openharness verify` again
4. If verification passed, run `openharness handoff` to complete
