# OpenHarness

OpenHarness is a local development harness for Claude Code and Codex, inspired by [Harness Engineering](https://openai.com/index/harness-engineering/). It takes your coding agent from ad-hoc code generation to a constrained, evidence-based development loop.

## How it works

It starts the moment you ask your agent to build something. Instead of jumping straight into writing code, OpenHarness forces the agent through a structured lifecycle:

1. **Capture intent** — the agent creates a task with constraints and success criteria
2. **Plan first** — the agent must write a plan before touching any project files. Hooks physically block `Edit` and `Write` operations until a plan exists
3. **Implement** — only after the plan is approved can the agent write code
4. **Verify** — the agent runs your configured verification commands and records evidence
5. **Fix or finish** — failed verification triggers a fix loop. Repeated failures mark the task as blocked. Passing verification produces a structured handoff

Every task ends in one of two explicit states: `ready_for_human_review` or `blocked`. There is no silent "done."

The key difference from prompt-only workflow tools: OpenHarness uses `PreToolUse` hooks to enforce sequencing at the platform level. The agent cannot skip steps even if it wants to.

## Installation

**Note:** Claude Code and Codex have different installation paths.

### Claude Code

```bash
git clone https://github.com/vincemakes/openharness.git ~/openharness
export PATH="$HOME/openharness/bin:$PATH"  # add to your shell profile
cd /path/to/your/project
openharness init
```

Restart Claude Code after `init`. The init command creates `.claude/settings.local.json` with hook configuration that Claude Code picks up on next session.

### Codex

```bash
git clone https://github.com/vincemakes/openharness.git ~/openharness
~/openharness/bin/openharness install codex
cd /path/to/your/project
openharness init
```

Restart Codex after installation.

### Verify Installation

Start a new Claude Code session in an initialized repo. The session-start hook should report OpenHarness status. Ask the agent to implement something — it should automatically route the work through the task lifecycle.

## Initialize a Repository

```bash
cd /path/to/your/project
openharness init
```

This creates:
- `.openharness/` — configuration, rules, and tasks directory
- `.claude/settings.local.json` — hook configuration for Claude Code
- `AGENTS.md` section — agent instructions for the harness lifecycle

## The Development Loop

```bash
openharness start-task "fix the streaming order bug"   # capture intent
openharness advance                                     # intake → planning
# agent writes plan.md
openharness advance                                     # planning → implementing
# agent implements changes
openharness verify                                      # run tests, record evidence
openharness handoff                                     # produce final summary
```

The agent learns these commands through two built-in skills that activate automatically.

## What's Inside

### Enforcement Layer

- **PreToolUse hook** — blocks `Edit`/`Write`/`NotebookEdit` when the active task is in `intake` or `planning` state
- **Session-start hook** — injects task awareness into every new session
- **CLI-only state mutations** — skills guide the agent but never change state directly

### Task Artifacts

Each task produces a self-contained directory:

```
.openharness/tasks/<task-id>/
├── task.md          # request, constraints, success criteria
├── plan.md          # approach, affected files, risks
├── status.json      # machine-readable state (gitignored)
├── verify.md        # verification evidence (gitignored)
└── handoff.md       # final summary for human review
```

### Skills

- **using-openharness** — detects harness state, routes work into the lifecycle
- **openharness-task** — teaches the agent the full task lifecycle and CLI commands

### Commands

- `/start-task` — create a new task
- `/verify-task` — run verification on the active task
- `/handoff-task` — complete the active task

### CLI

```bash
openharness install <platform>    # install for claude-code or codex
openharness init                  # initialize current repo
openharness start-task "<goal>"   # create a new task
openharness advance               # move to next lifecycle state
openharness status                # show active task state
openharness verify                # run verification, record evidence
openharness handoff               # produce final handoff summary
```

## Philosophy

- **Repo is the system of record** — all task state, plans, and evidence live in the repo, not in chat history
- **Enforcement over guidance** — hooks block invalid operations, not just discourage them
- **Evidence over claims** — no completion without verification
- **Explicit handoff** — every task ends in a reviewable state

Inspired by [Harness Engineering: leveraging Codex in an agent-first world](https://openai.com/index/harness-engineering/) — the idea that environmental design produces higher ROI than prompt engineering.

## Configuration

After `openharness init`, edit `.openharness/config.json`:

```json
{
  "verify_command": "npm test",
  "max_verify_attempts": 3
}
```

Set `verify_command` to whatever validates your project (test suite, linter, type check, etc.).

## Requirements

- Git
- POSIX shell (sh/bash/zsh)
- Claude Code or Codex

## Contributing

1. Fork the repository
2. Create a branch for your changes
3. Submit a PR

## License

MIT License — see LICENSE file for details.
