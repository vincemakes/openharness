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
      echo "  intake -> planning (requires task.md Done Condition + Verification Path)"
      echo "  planning -> implementing (requires plan.md Goal section content)"
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
      # Require task.md Done Condition to have real content
      if ! grep -q '^## Done Condition' "$task_dir/task.md" 2>/dev/null || \
         ! sed -n '/^## Done Condition/,/^## /p' "$task_dir/task.md" | grep -Eqv '^##|^[[:space:]]*$|^<!--'; then
        echo "openharness advance: task.md Done Condition section is empty" >&2
        echo "Define what 'done' looks like before planning." >&2
        exit 1
      fi
      # Require task.md Verification Path to have real content
      if ! grep -q '^## Verification Path' "$task_dir/task.md" 2>/dev/null || \
         ! sed -n '/^## Verification Path/,/^## /p' "$task_dir/task.md" | grep -Eqv '^##|^[[:space:]]*$|^<!--'; then
        echo "openharness advance: task.md Verification Path section is empty" >&2
        echo "Define how this task will be verified before planning." >&2
        exit 1
      fi
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
         ! sed -n '/^## Goal/,/^## /p' "$task_dir/plan.md" | grep -Eqv '^##|^[[:space:]]*$|^<!--'; then
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

## Done Condition
<!-- REQUIRED: What does "done" look like? Be specific and observable. -->
<!-- Example: "Search input appears in the header and returns matching results" -->

## Verification Path
<!-- REQUIRED: How will this be verified? -->
<!-- Example: "unit tests", "interactive verify", "manual review", or "reuse repo default" -->

## Rollback Hint
<!-- Recommended: How to undo this if it goes wrong -->

## Constraints
<!-- Add constraints here -->

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

# --- Verify helpers ---

# Fixed layer execution order
_OH_LAYER_ORDER="fast standard full"

# Read verify_layers commands for a given layer from config.json.
# Returns newline-separated commands, or empty if layer not defined.
# Falls back to verify_command mapped to standard.
_oh_verify_layer_cmds() {
  local config="$1"
  local layer="$2"

  # Check if verify_layers exists in config
  if grep -q '"verify_layers"' "$config" 2>/dev/null; then
    # Extract commands array for the layer using sed
    # Matches: "fast": ["cmd1", "cmd2"]  (single or multiple lines within the array)
    # We use a multi-pass approach: find the layer key, collect until closing ]
    local in_layer=false
    local in_array=false
    while IFS= read -r line; do
      if echo "$line" | grep -q "\"$layer\""; then
        in_layer=true
      fi
      if [ "$in_layer" = "true" ]; then
        if echo "$line" | grep -q '\['; then
          in_array=true
        fi
        if [ "$in_array" = "true" ]; then
          # Extract quoted strings from array elements
          echo "$line" | grep -o '"[^"]*"' | sed 's/^"//;s/"$//' | grep -v "^$layer$" || true
          if echo "$line" | grep -q '\]'; then
            break
          fi
        fi
      fi
    done < "$config"
  else
    # Backward compat: verify_command maps to standard
    if [ "$layer" = "standard" ]; then
      sed -n 's/.*"verify_command"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$config" | head -1
    fi
  fi
}

# Get the default verify layer from config
_oh_default_layer() {
  local config="$1"
  local default
  default="$(sed -n 's/.*"default_verify_layer"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$config" | head -1)"
  echo "${default:-standard}"
}

# Determine which layers to run given a target layer (cumulative from fast up to target)
_oh_layers_to_run() {
  local target="$1"
  local only="$2"  # if "true", run only the target layer
  if [ "$only" = "true" ]; then
    echo "$target"
    return
  fi
  local found=false
  for layer in $_OH_LAYER_ORDER; do
    echo "$layer"
    if [ "$layer" = "$target" ]; then
      found=true
      break
    fi
  done
  if [ "$found" = "false" ]; then
    # Unknown layer — run just that layer
    echo "$target"
  fi
}

oh_verify() {
  local target_layer=""
  local only_flag=false

  # Parse flags
  while [ $# -gt 0 ]; do
    case "$1" in
      --help|-h)
        echo "Usage: openharness verify [--fast | --full | --layer <name>] [--only]"
        echo ""
        echo "Run configured verification and record evidence."
        echo ""
        echo "Options:"
        echo "  --fast             Run up to fast layer"
        echo "  --full             Run all layers (fast + standard + full)"
        echo "  --layer <name>     Run up to named layer (cumulative)"
        echo "  --only             Run only the specified layer (not cumulative)"
        return 0
        ;;
      --fast)
        target_layer="fast"
        shift
        ;;
      --full)
        target_layer="full"
        shift
        ;;
      --layer)
        shift
        target_layer="${1:-}"
        if [ -z "$target_layer" ]; then
          echo "openharness verify: --layer requires a layer name" >&2
          exit 1
        fi
        shift
        ;;
      --only)
        only_flag=true
        shift
        ;;
      *)
        echo "openharness verify: unknown option '$1'" >&2
        exit 1
        ;;
    esac
  done

  _oh_require_init

  local task_dir
  if ! task_dir="$(_oh_active_task_dir)"; then
    echo "openharness verify: no active task" >&2
    exit 1
  fi

  local root
  root="$(_oh_repo_root)"
  local config="$root/.openharness/config.json"

  # Determine target layer
  if [ -z "$target_layer" ]; then
    target_layer="$(_oh_default_layer "$config")"
  fi

  local id status
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

  local attempt
  attempt="$(_oh_read_num_field "$task_dir" "attempt")"
  attempt=$((attempt + 1))

  local max_attempts
  max_attempts="$(sed -n 's/.*"max_verify_attempts"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p' "$config" | head -1)"
  max_attempts="${max_attempts:-3}"

  echo "Running verification (attempt $attempt, layer: $target_layer)..."
  echo ""

  # Determine layers to run
  local layers_to_run
  layers_to_run="$(_oh_layers_to_run "$target_layer" "$only_flag")"

  local overall_result="PASS"
  local failed_layer=""
  local failed_cmd=""
  local verify_md_content=""
  local now
  now="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

  verify_md_content="# Verification Evidence

## Attempt $attempt (layer: $target_layer)
- **Timestamp:** $now
"

  # Run each layer
  for layer in $layers_to_run; do
    # Manual layer is a checklist, not executable — handled separately below
    [ "$layer" = "manual" ] && continue

    local cmds
    cmds="$(_oh_verify_layer_cmds "$config" "$layer")"

    # Skip layer if no commands defined for it
    if [ -z "$cmds" ]; then
      continue
    fi

    echo "--- Layer: $layer ---"
    verify_md_content="${verify_md_content}
### Layer: $layer
"

    # Run each command in the layer
    local layer_result="PASS"
    while IFS= read -r cmd; do
      [ -z "$cmd" ] && continue
      echo "  Running: $cmd"
      local cmd_output cmd_exit
      set +e
      cmd_output="$(cd "$root" && sh -c "$cmd" 2>&1)"
      cmd_exit=$?
      set -e

      local cmd_result="PASS"
      if [ "$cmd_exit" -ne 0 ]; then
        cmd_result="FAIL"
        layer_result="FAIL"
      fi

      verify_md_content="${verify_md_content}- **Command:** \`$cmd\`
- **Result:** $cmd_result
- **Exit code:** $cmd_exit

\`\`\`
$cmd_output
\`\`\`

"
      if [ "$cmd_result" = "FAIL" ]; then
        echo "  FAIL (exit $cmd_exit)"
        break
      else
        echo "  PASS"
      fi
    done <<EOF
$cmds
EOF

    if [ "$layer_result" = "FAIL" ]; then
      overall_result="FAIL"
      failed_layer="$layer"
      failed_cmd="$cmd"
      break
    fi
  done

  # Append manual checklist if present and we ran a full pass
  if [ "$overall_result" = "PASS" ] && grep -q '"manual"' "$config" 2>/dev/null; then
    local manual_items
    manual_items="$(_oh_verify_layer_cmds "$config" "manual")"
    if [ -n "$manual_items" ]; then
      echo "--- Manual Review Checklist ---"
      verify_md_content="${verify_md_content}### Manual Review Checklist
"
      while IFS= read -r item; do
        [ -z "$item" ] && continue
        echo "  [ ] $item"
        verify_md_content="${verify_md_content}- [ ] $item
"
      done <<EOF
$manual_items
EOF
    fi
  fi

  # Append overall result
  if [ "$overall_result" = "PASS" ]; then
    verify_md_content="${verify_md_content}
### Overall: PASS
"
  else
    verify_md_content="${verify_md_content}
### Overall: FAIL (failed at layer: $failed_layer)
"
  fi

  printf '%s' "$verify_md_content" > "$task_dir/verify.md"

  echo ""
  if [ "$overall_result" = "PASS" ]; then
    _oh_write_status "$task_dir" "$id" "ready_for_human_review" "$attempt" "true" "" "null"
    echo "Verification PASSED."
    echo "Run 'openharness handoff' to complete."
  else
    if [ "$attempt" -ge "$max_attempts" ]; then
      _oh_write_status "$task_dir" "$id" "blocked" "$attempt" "false" "$failed_cmd" "blocked"
      echo "Verification FAILED (attempt $attempt/$max_attempts — limit reached)."
      echo "Task is now BLOCKED."
    else
      _oh_write_status "$task_dir" "$id" "fixing" "$attempt" "false" "$failed_cmd" "null"
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

  # Write repo-level HANDOFF.md for session continuity
  local root
  root="$(git rev-parse --show-toplevel 2>/dev/null || echo ".")"
  local now
  now="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  local task_title
  task_title="$(grep -m1 '^# Task:' "$task_dir/task.md" 2>/dev/null | sed 's/^# Task: *//' || echo "$id")"

  cat > "$root/.openharness/HANDOFF.md" <<EOF
# OpenHarness — Session Handoff

**Last updated:** $now
**Task:** $id
**Title:** $task_title
**Final state:** $final_state

## What Was Done

See task artifacts: \`.openharness/tasks/$id/\`
- \`task.md\` — original goal and constraints
- \`plan.md\` — implementation approach
- \`verify.md\` — verification evidence
- \`handoff.md\` — handoff summary

## Pending Work

<!-- Review and update for the next session -->

## Next Steps

$(if [ "$final_state" = "ready_for_human_review" ]; then
  echo "- Run \`openharness pr\` to create a pull request"
  echo "- Or run \`openharness commit\` to commit and deliver"
else
  echo "- Task is $final_state — review \`.openharness/tasks/$id/status.json\`"
fi)
EOF

  echo "Handoff complete: $final_state"
  echo "Summary: $task_dir/handoff.md"
  echo "Session continuity: .openharness/HANDOFF.md"
}
