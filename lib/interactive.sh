# OpenHarness interactive verification module
# Manages dev server lifecycle and browser-based verification evidence.

# --- Config helpers ---

_oh_interactive_config_field() {
  local config="$1"
  local field="$2"
  sed -n "s/.*\"$field\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" "$config" | head -1
}

_oh_interactive_config_num() {
  local config="$1"
  local field="$2"
  sed -n "s/.*\"$field\"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p" "$config" | head -1
}

# --- Dev server lifecycle ---

_oh_kill_pid() {
  local pid_file="$1"
  if [ ! -f "$pid_file" ]; then
    return 0
  fi
  local pid
  pid="$(cat "$pid_file")"
  if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null || true
    # Wait up to 5 seconds for graceful shutdown
    local waited=0
    while [ "$waited" -lt 5 ] && kill -0 "$pid" 2>/dev/null; do
      sleep 1
      waited=$((waited + 1))
    done
    # Force kill if still alive
    if kill -0 "$pid" 2>/dev/null; then
      kill -9 "$pid" 2>/dev/null || true
    fi
  fi
  rm -f "$pid_file"
}

# --- Commands ---

oh_interactive_verify() {
  case "${1:-}" in
    --help|-h)
      echo "Usage: openharness interactive-verify <start|complete>"
      echo ""
      echo "Manage interactive browser-based verification."
      echo ""
      echo "Subcommands:"
      echo "  start             Start dev server and prepare for browser verification"
      echo "  complete <pass|fail>  Stop dev server and record results"
      return 0
      ;;
    start)
      shift
      _oh_interactive_start "$@"
      ;;
    complete)
      shift
      _oh_interactive_complete "$@"
      ;;
    "")
      echo "openharness interactive-verify: missing subcommand" >&2
      echo "Run 'openharness interactive-verify --help' for usage." >&2
      exit 1
      ;;
    *)
      echo "openharness interactive-verify: unknown subcommand '$1'" >&2
      echo "Run 'openharness interactive-verify --help' for usage." >&2
      exit 1
      ;;
  esac
}

_oh_interactive_start() {
  _oh_require_init

  local task_dir
  if ! task_dir="$(_oh_active_task_dir)"; then
    echo "openharness interactive-verify: no active task" >&2
    exit 1
  fi

  local root
  root="$(_oh_repo_root)"
  local config="$root/.openharness/config.json"

  # Read interactive verify config
  local dev_cmd dev_url dev_timeout
  dev_cmd="$(_oh_interactive_config_field "$config" "dev_server_command")"
  dev_url="$(_oh_interactive_config_field "$config" "dev_server_url")"
  dev_timeout="$(_oh_interactive_config_num "$config" "dev_server_timeout")"
  dev_timeout="${dev_timeout:-30}"

  if [ -z "$dev_cmd" ]; then
    echo "openharness interactive-verify: no dev_server_command configured" >&2
    echo "Add 'interactive_verify.dev_server_command' to .openharness/config.json" >&2
    exit 1
  fi

  if [ -z "$dev_url" ]; then
    echo "openharness interactive-verify: no dev_server_url configured" >&2
    echo "Add 'interactive_verify.dev_server_url' to .openharness/config.json" >&2
    exit 1
  fi

  local id status
  id="$(_oh_read_field "$task_dir" "id")"
  status="$(_oh_read_field "$task_dir" "status")"

  # Only allow from implementing, verifying, or fixing
  case "$status" in
    implementing|verifying|fixing) ;;
    *)
      echo "openharness interactive-verify: cannot start from '$status'" >&2
      echo "Must be in implementing, verifying, or fixing state." >&2
      exit 1
      ;;
  esac

  local pid_file="$task_dir/.dev-server.pid"

  # Kill stale PID if exists
  _oh_kill_pid "$pid_file"

  # Start dev server in background (subshell to avoid cwd side effects)
  echo "Starting dev server: $dev_cmd"
  (cd "$root" && exec sh -c "$dev_cmd" >/dev/null 2>&1) &
  local server_pid=$!
  echo "$server_pid" > "$pid_file"

  # Poll dev_server_url until ready
  echo "Waiting for $dev_url (timeout: ${dev_timeout}s)..."
  local elapsed=0
  local ready=false
  while [ "$elapsed" -lt "$dev_timeout" ]; do
    local http_code
    http_code="$(curl -s -o /dev/null -w "%{http_code}" "$dev_url" 2>/dev/null || echo "000")"
    if [ "$http_code" -ge 200 ] 2>/dev/null && [ "$http_code" -lt 400 ] 2>/dev/null; then
      ready=true
      break
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done

  if [ "$ready" = "false" ]; then
    echo "openharness interactive-verify: dev server failed to start within ${dev_timeout}s" >&2
    _oh_kill_pid "$pid_file"
    exit 1
  fi

  echo "Dev server ready (PID: $server_pid)"

  # Ensure browse binary is built
  local oh_root
  oh_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  local browse_bin="$oh_root/browse/dist/browse"
  if [ ! -f "$browse_bin" ]; then
    echo "Browse binary not found. Building..."
    (cd "$oh_root/browse" && ./setup)
    if [ ! -f "$browse_bin" ]; then
      echo "openharness interactive-verify: failed to build browse binary" >&2
      _oh_kill_pid "$pid_file"
      exit 1
    fi
  fi
  export B="$browse_bin"

  # Create screenshots directory
  mkdir -p "$task_dir/screenshots"

  # Increment attempt and transition to verifying
  local attempt
  attempt="$(_oh_read_num_field "$task_dir" "attempt")"
  attempt=$((attempt + 1))
  _oh_write_status "$task_dir" "$id" "verifying" "$attempt"

  # Check for verify-interactive.md spec
  if [ -f "$task_dir/verify-interactive.md" ]; then
    echo ""
    echo "=== Interactive Verification Steps ==="
    cat "$task_dir/verify-interactive.md"
    echo ""
  fi

  echo ""
  echo "Screenshots dir: $task_dir/screenshots/"
  echo "Server URL: $dev_url"
  echo "Server PID: $server_pid"
  echo "Browse binary: $B"
  echo ""
  echo "Use \$B commands to drive the browser (e.g., \$B goto $dev_url)."
  echo "Write results to: $task_dir/verify-interactive-evidence.md"
  echo "When done, run: openharness interactive-verify complete <pass|fail>"
}

_oh_interactive_complete() {
  _oh_require_init

  local result="${1:-}"
  if [ "$result" != "pass" ] && [ "$result" != "fail" ]; then
    echo "openharness interactive-verify complete: specify 'pass' or 'fail'" >&2
    exit 1
  fi

  local task_dir
  if ! task_dir="$(_oh_active_task_dir)"; then
    echo "openharness interactive-verify: no active task" >&2
    exit 1
  fi

  local root
  root="$(_oh_repo_root)"
  local config="$root/.openharness/config.json"

  local id status attempt
  id="$(_oh_read_field "$task_dir" "id")"
  status="$(_oh_read_field "$task_dir" "status")"
  attempt="$(_oh_read_num_field "$task_dir" "attempt")"

  # Kill dev server
  local pid_file="$task_dir/.dev-server.pid"
  if [ -f "$pid_file" ]; then
    echo "Stopping dev server..."
    _oh_kill_pid "$pid_file"
    echo "Dev server stopped."
  fi

  # Read max attempts
  local max_attempts
  max_attempts="$(_oh_interactive_config_num "$config" "max_verify_attempts")"
  if [ -z "$max_attempts" ]; then
    max_attempts="$(sed -n 's/.*"max_verify_attempts"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p' "$config" | head -1)"
  fi
  max_attempts="${max_attempts:-3}"

  # Merge interactive evidence into verify.md
  local evidence_file="$task_dir/verify-interactive-evidence.md"
  local now
  now="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

  # Build verify.md entry
  local verify_section=""
  verify_section="# Verification Evidence

## Interactive Verification — Attempt $attempt
- **Type:** Browser-based (browse)
- **Result:** $(echo "$result" | tr '[:lower:]' '[:upper:]')
- **Timestamp:** $now
"

  # Append interactive evidence if it exists
  if [ -f "$evidence_file" ]; then
    verify_section="$verify_section
### Evidence
$(cat "$evidence_file")
"
  fi

  # Add screenshot references
  local screenshot_count=0
  if [ -d "$task_dir/screenshots" ]; then
    screenshot_count="$(ls -1 "$task_dir/screenshots/" 2>/dev/null | wc -l | tr -d ' ')"
  fi
  if [ "$screenshot_count" -gt 0 ]; then
    verify_section="$verify_section
### Screenshots ($screenshot_count captured)
"
    for img in "$task_dir/screenshots/"*; do
      if [ -f "$img" ]; then
        local basename
        basename="$(basename "$img")"
        verify_section="$verify_section- \`screenshots/$basename\`
"
      fi
    done
  fi

  printf '%s' "$verify_section" > "$task_dir/verify.md"

  # Update status
  if [ "$result" = "pass" ]; then
    _oh_write_status "$task_dir" "$id" "ready_for_human_review" "$attempt" "true" "" "null"
    echo "Interactive verification PASSED."
    echo "Run 'openharness handoff' to complete."
  else
    if [ "$attempt" -ge "$max_attempts" ]; then
      _oh_write_status "$task_dir" "$id" "blocked" "$attempt" "false" "interactive-verify" "blocked"
      echo "Interactive verification FAILED (attempt $attempt/$max_attempts — limit reached)."
      echo "Task is now BLOCKED."
    else
      _oh_write_status "$task_dir" "$id" "fixing" "$attempt" "false" "interactive-verify" "null"
      echo "Interactive verification FAILED (attempt $attempt/$max_attempts)."
      echo "Status: fixing. Fix the issue and run 'openharness interactive-verify start' again."
    fi
  fi
}
