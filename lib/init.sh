# OpenHarness init module

oh_init() {
  case "${1:-}" in
    --help|-h)
      echo "Usage: openharness init"
      echo ""
      echo "Initialize the current git repository for OpenHarness."
      echo "Creates .openharness/ directory and optional AGENTS.md integration."
      return 0
      ;;
  esac

  # Must be in a git repo
  if ! git rev-parse --git-dir >/dev/null 2>&1; then
    echo "openharness init: not a git repository" >&2
    exit 1
  fi

  local repo_root
  repo_root="$(git rev-parse --show-toplevel)"
  local oh_dir="$repo_root/.openharness"

  if [ -d "$oh_dir" ] && [ -f "$oh_dir/config.json" ]; then
    # Migrate existing repo: add INSTRUCTIONS.md if missing
    if [ ! -f "$oh_dir/INSTRUCTIONS.md" ]; then
      cp "$OPENHARNESS_ROOT/templates/.openharness/INSTRUCTIONS.md" "$oh_dir/INSTRUCTIONS.md"
      echo "Migrated: .openharness/INSTRUCTIONS.md (consolidated agent instructions)"
      # Add deprecated header to old files to redirect agents
      local deprecated_header="<!-- DEPRECATED: This file is superseded by INSTRUCTIONS.md. Kept for reference. -->"
      for old_file in "$oh_dir/REPO_GUIDE.md" "$oh_dir/RULES.md"; do
        if [ -f "$old_file" ] && ! grep -q 'DEPRECATED' "$old_file" 2>/dev/null; then
          local tmp_file="${old_file}.tmp"
          printf '%s\n\n' "$deprecated_header" > "$tmp_file"
          cat "$old_file" >> "$tmp_file"
          mv "$tmp_file" "$old_file"
        fi
      done
    fi
    echo "OpenHarness already initialized in $repo_root"
    return 0
  fi

  echo "Initializing OpenHarness in $repo_root..."

  # Create .openharness directory structure
  mkdir -p "$oh_dir/tasks"

  # Copy templates
  cp "$OPENHARNESS_ROOT/templates/.openharness/config.json" "$oh_dir/config.json"
  cp "$OPENHARNESS_ROOT/templates/.openharness/INSTRUCTIONS.md" "$oh_dir/INSTRUCTIONS.md"
  cp "$OPENHARNESS_ROOT/templates/.openharness/REPO_GUIDE.md" "$oh_dir/REPO_GUIDE.md"
  cp "$OPENHARNESS_ROOT/templates/.openharness/RULES.md" "$oh_dir/RULES.md"
  touch "$oh_dir/tasks/.gitkeep"

  # Append gitignore rules if not already present
  local gitignore="$repo_root/.gitignore"
  if [ -f "$gitignore" ]; then
    if ! grep -q '.openharness/tasks/*/status.json' "$gitignore" 2>/dev/null; then
      printf '\n# OpenHarness — local task artifacts\n.openharness/tasks/*/status.json\n.openharness/tasks/*/status.json.tmp\n.openharness/tasks/*/verify.md\n.openharness/tasks/*/screenshots/\n.openharness/tasks/*/.dev-server.pid\n.openharness/active-task\n' >> "$gitignore"
    fi
  else
    printf '# OpenHarness — local task artifacts\n.openharness/tasks/*/status.json\n.openharness/tasks/*/status.json.tmp\n.openharness/tasks/*/verify.md\n.openharness/tasks/*/screenshots/\n.openharness/tasks/*/.dev-server.pid\n.openharness/active-task\n' > "$gitignore"
  fi

  # AGENTS.md integration — thin adapter pointing to INSTRUCTIONS.md
  local agents_file="$repo_root/AGENTS.md"
  local agents_block
  agents_block="$(cat "$OPENHARNESS_ROOT/templates/AGENTS.openharness.md")"

  if [ -f "$agents_file" ]; then
    if ! grep -q 'OpenHarness' "$agents_file" 2>/dev/null; then
      printf '\n%s\n' "$agents_block" >> "$agents_file"
      echo "Updated: AGENTS.md (appended OpenHarness section)"
    fi
  else
    printf '%s\n' "$agents_block" > "$agents_file"
    echo "Created: AGENTS.md"
  fi

  # CLAUDE.md integration — thin adapter pointing to INSTRUCTIONS.md
  local claude_md="$repo_root/CLAUDE.md"
  local claude_block
  claude_block="$(cat "$OPENHARNESS_ROOT/templates/CLAUDE.openharness.md")"

  if [ -f "$claude_md" ]; then
    if ! grep -q 'OpenHarness' "$claude_md" 2>/dev/null; then
      printf '\n%s\n' "$claude_block" >> "$claude_md"
      echo "Updated: CLAUDE.md (appended OpenHarness section)"
    fi
  fi

  # Claude Code hooks integration via .claude/settings.local.json
  local claude_settings_dir="$repo_root/.claude"
  local claude_local="$claude_settings_dir/settings.local.json"
  mkdir -p "$claude_settings_dir"

  if [ -f "$claude_local" ]; then
    if ! grep -q 'pre-tool-use' "$claude_local" 2>/dev/null; then
      echo "Warning: .claude/settings.local.json exists but has no OpenHarness hooks." >&2
      echo "Add hooks manually or remove the file and re-run init." >&2
    fi
  else
    cat > "$claude_local" <<EOJSON
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Edit|Write|NotebookEdit",
        "hooks": [
          {
            "type": "command",
            "command": "$OPENHARNESS_ROOT/hooks/pre-tool-use"
          }
        ]
      }
    ],
    "SessionStart": [
      {
        "matcher": "startup|resume|clear|compact",
        "hooks": [
          {
            "type": "command",
            "command": "$OPENHARNESS_ROOT/hooks/session-start"
          }
        ]
      }
    ]
  }
}
EOJSON
    echo "Created: .claude/settings.local.json (hooks)"
  fi

  echo "Created: .openharness/"
  echo "Updated: .gitignore"

  # Check for Playwright MCP availability
  local playwright_detected=false
  if [ -f "$claude_local" ] && grep -q 'playwright' "$claude_local" 2>/dev/null; then
    playwright_detected=true
  elif [ -f "$repo_root/.claude/settings.json" ] && grep -q 'playwright' "$repo_root/.claude/settings.json" 2>/dev/null; then
    playwright_detected=true
  fi

  if [ "$playwright_detected" = "true" ]; then
    echo "Playwright MCP detected — interactive verification available."
  else
    echo "Tip: Add Playwright MCP server for interactive browser verification."
  fi

  echo ""
  echo "Ready. Restart Claude Code, then run 'openharness start-task \"<goal>\"' to begin."
}
