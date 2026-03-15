# OpenHarness

A delivery control plane for AI coding agents. Give it a task — it delivers a PR.

```
idea → task → plan → implement → verify → commit → PR
```

OpenHarness takes your coding agent from ad-hoc code generation to a constrained, evidence-based delivery pipeline. It enforces sequencing at the platform level using hooks — the agent cannot skip steps even if it wants to.

**What it does:** Owns the delivery path from "task is clear enough" to "PR is ready for review."

**What it doesn't do:** Brainstorming, memory, or conversation management. Those belong to other tools (Superpowers, claude-mem, etc.).

## The Full Flow

```
User: "add search to the chat panel"
  ↓
openharness start-task "add search to chat panel"    # capture intent
openharness advance                                    # → planning
  # agent writes plan.md (hooks block code edits until plan exists)
openharness advance                                    # → implementing
  # agent writes code in isolated worktree
openharness verify                                     # run tests, record evidence
openharness cleanup                                    # lint + format
openharness commit                                     # auto-generated commit message
openharness pr                                         # create PR with summary + evidence
  ↓
User: reviews PR
```

## Installation

### Claude Code

```bash
git clone https://github.com/vincemakes/openharness.git ~/openharness
export PATH="$HOME/openharness/bin:$PATH"  # add to your shell profile
cd /path/to/your/project
openharness init
```

Restart Claude Code after `init`. The init command creates `.claude/settings.local.json` with hook configuration.

### Codex

```bash
git clone https://github.com/vincemakes/openharness.git ~/openharness
~/openharness/bin/openharness install codex
cd /path/to/your/project
openharness init
```

## Initialize a Repository

```bash
cd /path/to/your/project
openharness init
```

Creates:
- `.openharness/` — config, rules, tasks directory
- `.claude/settings.local.json` — hook configuration
- `AGENTS.md` section — agent lifecycle instructions

## CLI Reference

### Lifecycle Commands

| Command | Description |
|---------|-------------|
| `start-task "<goal>"` | Create a new task, set status to `intake` |
| `advance` | Move task forward: intake → planning → implementing |
| `verify` | Run verification commands, record evidence |
| `handoff` | Produce final summary (legacy, before delivery tail) |

### Delivery Commands

| Command | Description |
|---------|-------------|
| `cleanup` | Run lint/format from `cleanup_command` config |
| `commit` | Auto-commit with generated message (requires verified) |
| `pr` | Create PR via `gh` or write draft to task directory |

### Worktree Commands

| Command | Description |
|---------|-------------|
| `worktree create` | Create isolated git worktree for active task |
| `worktree status` | Show worktree info |
| `worktree remove` | Remove worktree and clean up branch |

### Other Commands

| Command | Description |
|---------|-------------|
| `init` | Initialize repo for OpenHarness |
| `install <platform>` | Install for claude-code or codex |
| `status` | Show active task state |

## State Machine

```
intake → planning → implementing → verifying
                                      ↓
                              ┌───────┴───────┐
                              ↓               ↓
                           fixing      ready_for_human_review
                              ↓               ↓
                           blocked        delivered
```

- **intake** — task created, agent fills in constraints
- **planning** — agent writes plan.md (hooks block code edits)
- **implementing** — code changes allowed
- **verifying** — running verification commands
- **fixing** — verification failed, agent fixing (retries allowed)
- **blocked** — max verification attempts exceeded (terminal)
- **ready_for_human_review** — verification passed
- **delivered** — committed and ready for PR

## Worktree Isolation

Each task can run in an isolated git worktree:

```bash
openharness start-task "add search"
openharness worktree create
# Creates branch: oh/2026-03-15-add-search
# Worktree at: .openharness/worktrees/2026-03-15-add-search/
```

Changes stay on the task branch. Main branch is never touched until PR merge.

## Task Artifacts

```
.openharness/tasks/<task-id>/
├── task.md          # request, constraints, success criteria
├── plan.md          # approach, affected files, risks
├── status.json      # machine-readable state (gitignored)
├── verify.md        # verification evidence (gitignored)
├── handoff.md       # summary for human review
└── pr-draft.md      # PR body (if gh CLI unavailable)
```

## Configuration

Edit `.openharness/config.json`:

```json
{
  "verify_command": "pnpm test",
  "cleanup_command": "pnpm lint --fix && pnpm format",
  "max_verify_attempts": 3,
  "pr_base_branch": "main"
}
```

| Field | Description |
|-------|-------------|
| `verify_command` | Command to validate the project |
| `cleanup_command` | Lint/format command (optional) |
| `max_verify_attempts` | Retries before marking task blocked |
| `pr_base_branch` | Target branch for PRs |

## Enforcement

- **PreToolUse hook** — blocks `Edit`/`Write`/`NotebookEdit` in `intake` and `planning` states
- **Session-start hook** — injects task awareness into every session
- **CLI-only state mutations** — no manual status.json editing
- **Atomic writes** — status.json uses temp file + mv to prevent corruption

## Philosophy

- **Repo is the system of record** — task state, plans, and evidence live in the repo
- **Enforcement over guidance** — hooks block invalid operations
- **Evidence over claims** — no completion without verification
- **Isolation by default** — worktrees keep main branch clean
- **Explicit delivery** — every task ends in a reviewable PR or a blocked state

Inspired by [Harness Engineering](https://openai.com/index/harness-engineering/).

## Requirements

- Git
- POSIX shell (sh/bash/zsh)
- Claude Code or Codex
- `gh` CLI (optional, for automated PR creation)

## License

MIT License — see LICENSE file for details.
