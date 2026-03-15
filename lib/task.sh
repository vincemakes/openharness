# OpenHarness task module

# --- Helpers ---

_oh_repo_root() {
  git rev-parse --show-toplevel 2>/dev/null || {
    echo "openharness: not a git repository" >&2
    return 1
  }
}

_oh_tasks_dir() {
  echo "$(_oh_repo_root)/.openharness/tasks"
}

_oh_require_init() {
  local root
  root="$(_oh_repo_root)"
  if [ ! -f "$root/.openharness/config.json" ]; then
    echo "openharness: repo not initialized. Run 'openharness init' first." >&2
    exit 1
  fi
}

_oh_active_task_dir() {
  local root
  root="$(_oh_repo_root)" || return 1
  local active_file="$root/.openharness/active-task"
  local tasks_dir
  tasks_dir="$(_oh_tasks_dir)"

  # Primary: read from active-task file
  if [ -f "$active_file" ]; then
    local task_id
    task_id="$(cat "$active_file")"
    if [ -n "$task_id" ] && [ -f "$tasks_dir/$task_id/status.json" ]; then
      echo "$tasks_dir/$task_id"
      return 0
    fi
  fi

  # Fallback: most recent task by modification time (legacy compat)
  if [ -d "$tasks_dir" ]; then
    local latest
    latest="$(ls -1t "$tasks_dir" 2>/dev/null | head -1)"
    if [ -n "$latest" ] && [ -f "$tasks_dir/$latest/status.json" ]; then
      echo "$tasks_dir/$latest"
      return 0
    fi
  fi
  return 1
}

_oh_read_status() {
  local task_dir="$1"
  cat "$task_dir/status.json"
}

_oh_read_field() {
  local task_dir="$1"
  local field="$2"
  # Minimal JSON field reader — no jq dependency
  sed -n "s/.*\"$field\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" "$task_dir/status.json" | head -1
}

_oh_read_num_field() {
  local task_dir="$1"
  local field="$2"
  sed -n "s/.*\"$field\"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p" "$task_dir/status.json" | head -1
}

_oh_write_status() {
  local task_dir="$1"
  local id="$2"
  local status="$3"
  local attempt="${4:-1}"
  local verification_passed="${5:-false}"
  local last_failed_command="${6:-}"
  local handoff_state="${7:-null}"
  local created_at="${8:-}"
  local now
  now="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

  if [ "$handoff_state" = "null" ]; then
    local hs="null"
  else
    local hs="\"$handoff_state\""
  fi

  if [ -n "$last_failed_command" ]; then
    local lfc="\"$last_failed_command\""
  else
    local lfc="null"
  fi

  # Preserve created_at from existing file, or use provided value, or now
  if [ -z "$created_at" ] && [ -f "$task_dir/status.json" ]; then
    created_at="$(sed -n 's/.*"created_at"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$task_dir/status.json" | head -1)"
  fi
  created_at="${created_at:-$now}"

  # Atomic write: write to temp file, then mv
  local tmp_file="$task_dir/status.json.tmp"
  cat > "$tmp_file" <<EOF
{
  "id": "$id",
  "status": "$status",
  "attempt": $attempt,
  "verification_passed": $verification_passed,
  "last_failed_command": $lfc,
  "handoff_state": $hs,
  "created_at": "$created_at",
  "updated_at": "$now"
}
EOF
  mv "$tmp_file" "$task_dir/status.json"
}

_oh_slugify() {
  local date_prefix
  date_prefix="$(date +%Y-%m-%d)"
  local slug
  slug="$(echo "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-//' | sed 's/-$//' | cut -c1-60)"
  echo "${date_prefix}-${slug}"
}

# --- Commands ---

oh_advance() {
  case "${1:-}" in
    --help|-h)
      echo "Usage: openharness advance"
      echo ""
      echo "Advance the active task to the next state."
      echo "  intake -> planning (always)"
      echo "  planning -> implementing (requires plan.md content)"
      return 0
      ;;
  esac

  _oh_require_init

  local task_dir
  if ! task_dir="$(_oh_active_task_dir)"; then
    echo "openharness advance: no active task" >&2
    exit 1
  fi

  local id status attempt
  id="$(_oh_read_field "$task_dir" "id")"
  status="$(_oh_read_field "$task_dir" "status")"
  attempt="$(_oh_read_num_field "$task_dir" "attempt")"

  case "$status" in
    intake)
      _oh_write_status "$task_dir" "$id" "planning" "$attempt"
      echo "Task advanced: intake -> planning"
      echo "Next: write $task_dir/plan.md, then run 'openharness advance' again."
      ;;
    planning)
      # Require plan.md to have real content
      if [ ! -s "$task_dir/plan.md" ]; then
        echo "openharness advance: plan.md is empty" >&2
        exit 1
      fi
      # Check that at least the Goal section has content
      if ! grep -q '^## Goal' "$task_dir/plan.md" 2>/dev/null || \
         ! sed -n '/^## Goal/,/^## /p' "$task_dir/plan.md" | grep -qv '^##\|^$\|^<!--'; then
        echo "openharness advance: plan.md Goal section is empty" >&2
        echo "Fill in the plan before advancing to implementation." >&2
        exit 1
      fi
      _oh_write_status "$task_dir" "$id" "implementing" "$attempt"
      echo "Task advanced: planning -> implementing"
      echo "Implementation is now allowed. Edit/Write hooks will permit file changes."
      ;;
    implementing|verifying|fixing)
      echo "openharness advance: cannot advance from '$status'" >&2
      echo "Use 'openharness verify' for later transitions." >&2
      exit 1
      ;;
    ready_for_human_review|delivered|blocked)
      echo "openharness advance: task is in terminal state '$status'" >&2
      exit 1
      ;;
    *)
      echo "openharness advance: unknown state '$status'" >&2
      exit 1
      ;;
  esac
}

oh_start_task() {
  case "${1:-}" in
    --help|-h|"")
      echo "Usage: openharness start-task \"<goal>\""
      echo ""
      echo "Create a new task and initialize artifacts."
      return 0
      ;;
  esac

  _oh_require_init

  local goal="$*"
  local task_id
  task_id="$(_oh_slugify "$goal")"
  local tasks_dir
  tasks_dir="$(_oh_tasks_dir)"
  local task_dir="$tasks_dir/$task_id"

  if [ -d "$task_dir" ]; then
    echo "openharness: task '$task_id' already exists" >&2
    exit 1
  fi

  mkdir -p "$task_dir"

  # Write active-task pointer
  local root
  root="$(_oh_repo_root)"
  printf '%s' "$task_id" > "$root/.openharness/active-task"

  # Initialize task.md
  cat > "$task_dir/task.md" <<EOF
# Task: $goal

## Original Request
$goal

## Constraints
<!-- Add constraints here -->

## Success Criteria
<!-- Define what success looks like -->

## Assumptions
<!-- List assumptions -->
EOF

  # Initialize plan.md placeholder
  cat > "$task_dir/plan.md" <<EOF
# Plan

<!-- This file must be completed before implementation begins. -->
<!-- Required sections: goal, affected files, approach, verification commands, risks -->

## Goal

## Affected Files

## Approach

## Verification Commands

## Risks
EOF

  # Initialize status.json (attempt 0 — verify increments before use)
  _oh_write_status "$task_dir" "$task_id" "intake" "0"

  # Initialize verify.md placeholder
  cat > "$task_dir/verify.md" <<EOF
# Verification Evidence

<!-- Written by 'openharness verify'. Do not edit manually. -->
EOF

  # Initialize handoff.md placeholder
  cat > "$task_dir/handoff.md" <<EOF
# Handoff

<!-- Written by 'openharness handoff'. Do not edit manually. -->

## Summary

## Verification Summary

## Known Risks

## Final State
<!-- Must be one of: ready_for_human_review | blocked -->
EOF

  # Generate verify-interactive.md if interactive verify is configured
  local root_for_config
  root_for_config="$(_oh_repo_root)"
  local iv_cmd
  iv_cmd="$(sed -n 's/.*"dev_server_command"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$root_for_config/.openharness/config.json" | head -1)"
  if [ -n "$iv_cmd" ]; then
    cat > "$task_dir/verify-interactive.md" <<EOF
# Interactive Verification Steps

## Steps

1. Navigate to the app
2. (add your steps here)
EOF
    echo "Created: verify-interactive.md (interactive verification configured)"
  fi

  echo "Task created: $task_id"
  echo "Status: intake"
  echo "Directory: $task_dir"
  echo ""
  echo "Next: fill in $task_dir/task.md, then write $task_dir/plan.md"
}

oh_status() {
  case "${1:-}" in
    --help|-h)
      echo "Usage: openharness status"
      echo ""
      echo "Show the active task state."
      return 0
      ;;
  esac

  _oh_require_init

  local task_dir
  if ! task_dir="$(_oh_active_task_dir)"; then
    echo "No active task."
    echo "Run 'openharness start-task \"<goal>\"' to create one."
    return 0
  fi

  local id status attempt vp lfc hs
  id="$(_oh_read_field "$task_dir" "id")"
  status="$(_oh_read_field "$task_dir" "status")"
  attempt="$(_oh_read_num_field "$task_dir" "attempt")"
  vp="$(_oh_read_field "$task_dir" "verification_passed")"

  local branch wt_path
  branch="$(sed -n 's/.*"branch"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$task_dir/status.json" | head -1)"
  wt_path="$(sed -n 's/.*"worktree_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$task_dir/status.json" | head -1)"

  echo "Task:     $id"
  echo "Status:   $status"
  echo "Attempt:  $attempt"
  echo "Verified: ${vp:-false}"
  echo "Dir:      $task_dir"
  if [ -n "$branch" ]; then
    echo "Branch:   $branch"
    echo "Worktree: $wt_path"
  fi
}

oh_verify() {
  case "${1:-}" in
    --help|-h)
      echo "Usage: openharness verify"
      echo ""
      echo "Run configured verification commands and record evidence."
      return 0
      ;;
  esac

  _oh_require_init

  local task_dir
  if ! task_dir="$(_oh_active_task_dir)"; then
    echo "openharness verify: no active task" >&2
    exit 1
  fi

  local root
  root="$(_oh_repo_root)"
  local config="$root/.openharness/config.json"

  # Read verify command from config.json
  local verify_cmd
  verify_cmd="$(sed -n 's/.*"verify_command"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$config" | head -1)"

  if [ -z "$verify_cmd" ]; then
    echo "openharness verify: no verify_command configured in .openharness/config.json" >&2
    exit 1
  fi

  local id status attempt
  id="$(_oh_read_field "$task_dir" "id")"
  status="$(_oh_read_field "$task_dir" "status")"

  # Only allow verify from implementing, verifying, or fixing states
  case "$status" in
    implementing|verifying|fixing) ;;
    ready_for_human_review|delivered)
      echo "openharness verify: task already verified (status: $status)" >&2
      exit 1
      ;;
    blocked)
      echo "openharness verify: task is blocked (max attempts reached)" >&2
      exit 1
      ;;
    intake|planning)
      echo "openharness verify: cannot verify from '$status' — advance to implementing first" >&2
      exit 1
      ;;
    *)
      echo "openharness verify: unknown state '$status'" >&2
      exit 1
      ;;
  esac

  attempt="$(_oh_read_num_field "$task_dir" "attempt")"
  attempt=$((attempt + 1))

  # Read max attempts
  local max_attempts
  max_attempts="$(sed -n 's/.*"max_verify_attempts"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p' "$config" | head -1)"
  max_attempts="${max_attempts:-3}"

  echo "Running verification (attempt $attempt)..."
  echo "Command: $verify_cmd"
  echo ""

  # Run verification
  local result output exit_code
  set +e
  output="$(cd "$root" && sh -c "$verify_cmd" 2>&1)"
  exit_code=$?
  set -e

  if [ "$exit_code" -eq 0 ]; then
    result="PASS"
  else
    result="FAIL"
  fi

  # Write verify.md
  cat > "$task_dir/verify.md" <<EOF
# Verification Evidence

## Attempt $attempt
- **Command:** \`$verify_cmd\`
- **Result:** $result
- **Exit code:** $exit_code
- **Timestamp:** $(date -u +"%Y-%m-%dT%H:%M:%SZ")

### Output
\`\`\`
$output
\`\`\`
EOF

  if [ "$result" = "PASS" ]; then
    _oh_write_status "$task_dir" "$id" "ready_for_human_review" "$attempt" "true" "" "null"
    echo "Verification PASSED."
    echo "Run 'openharness handoff' to complete."
  else
    if [ "$attempt" -ge "$max_attempts" ]; then
      _oh_write_status "$task_dir" "$id" "blocked" "$attempt" "false" "$verify_cmd" "blocked"
      echo "Verification FAILED (attempt $attempt/$max_attempts — limit reached)."
      echo "Task is now BLOCKED."
    else
      _oh_write_status "$task_dir" "$id" "fixing" "$attempt" "false" "$verify_cmd" "null"
      echo "Verification FAILED (attempt $attempt/$max_attempts)."
      echo "Status: fixing. Fix the issue and run 'openharness verify' again."
    fi
  fi
}

oh_handoff() {
  case "${1:-}" in
    --help|-h)
      echo "Usage: openharness handoff"
      echo ""
      echo "Produce final handoff summary. Requires prior verification."
      return 0
      ;;
  esac

  _oh_require_init

  local task_dir
  if ! task_dir="$(_oh_active_task_dir)"; then
    echo "openharness handoff: no active task" >&2
    exit 1
  fi

  local id status
  id="$(_oh_read_field "$task_dir" "id")"
  status="$(_oh_read_field "$task_dir" "status")"

  # Require verification evidence
  if [ ! -s "$task_dir/verify.md" ] || ! grep -q 'Attempt' "$task_dir/verify.md" 2>/dev/null; then
    echo "openharness handoff: no verification evidence found" >&2
    echo "Run 'openharness verify' before handoff." >&2
    exit 1
  fi

  local final_state
  case "$status" in
    ready_for_human_review)
      final_state="ready_for_human_review"
      ;;
    blocked)
      final_state="blocked"
      ;;
    delivered)
      echo "openharness handoff: task already delivered" >&2
      exit 1
      ;;
    intake|planning|implementing)
      echo "openharness handoff: cannot handoff from '$status' — run verify first" >&2
      exit 1
      ;;
    *)
      # If verify passed but status wasn't updated, allow handoff
      if grep -q '"verification_passed": true' "$task_dir/status.json" 2>/dev/null; then
        final_state="ready_for_human_review"
      else
        final_state="blocked"
      fi
      ;;
  esac

  # Generate handoff.md
  local verify_result
  verify_result="$(grep -m1 'Result:' "$task_dir/verify.md" | sed 's/.*\*\*Result:\*\*[[:space:]]*//')"

  cat > "$task_dir/handoff.md" <<EOF
# Handoff: $id

## Summary
Task: $id
Final state: **$final_state**

## Verification Summary
Last result: $verify_result

## Known Risks
<!-- Review and fill in -->

## Final State
$final_state
EOF

  # Update status
  local attempt
  attempt="$(_oh_read_num_field "$task_dir" "attempt")"
  local vp
  if [ "$final_state" = "ready_for_human_review" ]; then
    vp="true"
  else
    vp="false"
  fi
  _oh_write_status "$task_dir" "$id" "$final_state" "$attempt" "$vp" "" "$final_state"

  echo "Handoff complete: $final_state"
  echo "Summary: $task_dir/handoff.md"
}
