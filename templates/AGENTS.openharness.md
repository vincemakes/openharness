## OpenHarness

This repository uses [OpenHarness](https://github.com/user/openharness) for structured development.

Before implementing any changes:
1. Run `openharness status` to check for an active task
2. If no task exists, run `openharness start-task "<goal>"`
3. Follow the harness lifecycle: intake → planning → implementing → verifying → handoff

See `.openharness/RULES.md` for enforcement rules.
