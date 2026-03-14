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
    echo "OpenHarness already initialized in $repo_root"
    return 0
  fi

  echo "Initializing OpenHarness in $repo_root..."

  # Create .openharness directory structure
  mkdir -p "$oh_dir/tasks"

  # Copy templates
  cp "$OPENHARNESS_ROOT/templates/.openharness/config.json" "$oh_dir/config.json"
  cp "$OPENHARNESS_ROOT/templates/.openharness/REPO_GUIDE.md" "$oh_dir/REPO_GUIDE.md"
  cp "$OPENHARNESS_ROOT/templates/.openharness/RULES.md" "$oh_dir/RULES.md"
  touch "$oh_dir/tasks/.gitkeep"

  # Append gitignore rules if not already present
  local gitignore="$repo_root/.gitignore"
  if [ -f "$gitignore" ]; then
    if ! grep -q '.openharness/tasks/*/status.json' "$gitignore" 2>/dev/null; then
      printf '\n# OpenHarness — local task artifacts\n.openharness/tasks/*/status.json\n.openharness/tasks/*/verify.md\n' >> "$gitignore"
    fi
  else
    printf '# OpenHarness — local task artifacts\n.openharness/tasks/*/status.json\n.openharness/tasks/*/verify.md\n' > "$gitignore"
  fi

  # AGENTS.md integration
  local agents_file="$repo_root/AGENTS.md"
  local agents_block="## OpenHarness

This repository uses [OpenHarness](https://github.com/user/openharness) for structured development.

Before implementing any changes:
1. Run \`openharness status\` to check for an active task
2. If no task exists, run \`openharness start-task \"<goal>\"\`
3. Follow the harness lifecycle: intake → planning → implementing → verifying → handoff

See \`.openharness/RULES.md\` for enforcement rules."

  if [ -f "$agents_file" ]; then
    if ! grep -q 'OpenHarness' "$agents_file" 2>/dev/null; then
      printf '\n%s\n' "$agents_block" >> "$agents_file"
      echo "Updated: AGENTS.md (appended OpenHarness section)"
    fi
  else
    printf '%s\n' "$agents_block" > "$agents_file"
    echo "Created: AGENTS.md"
  fi

  echo "Created: .openharness/"
  echo "Updated: .gitignore"
  echo ""
  echo "Ready. Run 'openharness start-task \"<goal>\"' to begin."
}
