# Integration Guide

How OpenHarness works alongside other Claude Code tools.

## OpenHarness + Playwright MCP

**Purpose:** Browser-based verification of UI changes.

### Setup

1. Install the Playwright MCP server:

```json
// .claude/settings.local.json (mcpServers section)
{
  "mcpServers": {
    "playwright": {
      "command": "npx",
      "args": ["@anthropic/mcp-playwright"]
    }
  }
}
```

2. Configure your dev server in `.openharness/config.json`:

```json
{
  "interactive_verify": {
    "dev_server_command": "npm run dev",
    "dev_server_url": "http://localhost:3000",
    "dev_server_timeout": 30
  }
}
```

### Flow

```
openharness interactive-verify start    # starts dev server
  → agent uses Playwright MCP tools     # navigate, click, screenshot
openharness interactive-verify complete pass/fail
```

The shell manages the dev server lifecycle. The agent drives the browser. This is the **shell bookend pattern** — shell handles infrastructure, agent handles interaction.

## OpenHarness + claude-mem

**Purpose:** Persistent memory across conversations about task context.

### Recommended Pattern

- Save project decisions and task context to claude-mem during planning
- Reference past decisions when starting new tasks
- Use claude-mem's search to find related past work before `openharness start-task`

### What Goes Where

| Information | Store in |
|------------|----------|
| Task state, plans, evidence | OpenHarness (`.openharness/tasks/`) |
| Decisions, rationale, learnings | claude-mem |
| Architecture, patterns | claude-mem or CLAUDE.md |
| Bug context, debugging notes | claude-mem |

## OpenHarness + Superpowers

**Purpose:** Superpowers provides skills (brainstorming, debugging, etc.) that complement the OpenHarness lifecycle.

### Recommended Flow

1. **Brainstorming** (Superpowers) → produces task ideas
2. **Task creation** (OpenHarness) → `openharness start-task`
3. **Planning** (OpenHarness + Superpowers skills) → plan.md
4. **Implementation** (OpenHarness enforced) → code changes
5. **Verification** (OpenHarness) → shell or interactive verify
6. **Delivery** (OpenHarness) → commit + PR

Superpowers skills inform HOW to approach work. OpenHarness enforces WHEN each phase happens.
