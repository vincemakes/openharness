---
name: interactive-verify
description: Run interactive browser-based verification using Playwright
allowed-tools: Bash, Read, Write, mcp__playwright__*
---

Run interactive browser-based verification for the active OpenHarness task.

1. Invoke the `interactive-verify` skill for guidance
2. Run `openharness interactive-verify start` to start the dev server
3. Use Playwright MCP tools to drive the browser through verification steps
4. Capture screenshots for each step
5. Write evidence to `verify-interactive-evidence.md`
6. Run `openharness interactive-verify complete pass` or `complete fail`
