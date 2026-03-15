# OpenHarness delivery module
# Handles cleanup, commit, and PR creation.

oh_cleanup() {
  case "${1:-}" in
    --help|-h)
      echo "Usage: openharness cleanup"
      echo ""
      echo "Run configured cleanup commands (lint, format, etc.)."
      echo "Reads cleanup_command from .openharness/config.json."
      return 0
      ;;
  esac

  _oh_require_init

  local task_dir
  if ! task_dir="$(_oh_active_task_dir)"; then
    echo "openharness cleanup: no active task" >&2
    exit 1
  fi

  local root
  root="$(_oh_repo_root)"
  local config="$root/.openharness/config.json"
  local id
  id="$(_oh_read_field "$task_dir" "id")"

  # Read cleanup command from config
  local cleanup_cmd
  cleanup_cmd="$(sed -n 's/.*"cleanup_command"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$config" | head -1)"

  if [ -z "$cleanup_cmd" ]; then
    echo "openharness cleanup: no cleanup_command configured in .openharness/config.json" >&2
    echo "Skipping cleanup. Add \"cleanup_command\": \"your-command\" to config.json." >&2
    return 0
  fi

  echo "Running cleanup..."
  echo "Command: $cleanup_cmd"
  echo ""

  # Determine working directory (worktree or repo root)
  local work_dir="$root"
  local wt_path
  wt_path="$(sed -n 's/.*"worktree_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$task_dir/status.json" | head -1)"
  if [ -n "$wt_path" ] && [ -d "$wt_path" ]; then
    work_dir="$wt_path"
  fi

  set +e
  local output exit_code
  output="$(cd "$work_dir" && sh -c "$cleanup_cmd" 2>&1)"
  exit_code=$?
  set -e

  if [ "$exit_code" -eq 0 ]; then
    echo "Cleanup passed."
  else
    echo "Cleanup failed (exit $exit_code):" >&2
    echo "$output" >&2
    exit 1
  fi
}

oh_commit() {
  case "${1:-}" in
    --help|-h)
      echo "Usage: openharness commit"
      echo ""
      echo "Auto-generate commit message and commit all changes."
      echo "Only allowed after verification passes (status: ready_for_human_review)."
      return 0
      ;;
  esac

  _oh_require_init

  local task_dir
  if ! task_dir="$(_oh_active_task_dir)"; then
    echo "openharness commit: no active task" >&2
    exit 1
  fi

  local root
  root="$(_oh_repo_root)"
  local id status
  id="$(_oh_read_field "$task_dir" "id")"
  status="$(_oh_read_field "$task_dir" "status")"

  if [ "$status" != "ready_for_human_review" ]; then
    echo "openharness commit: task must be in 'ready_for_human_review' state (current: $status)" >&2
    echo "Run 'openharness verify' first." >&2
    exit 1
  fi

  # Determine working directory
  local work_dir="$root"
  local wt_path
  wt_path="$(sed -n 's/.*"worktree_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$task_dir/status.json" | head -1)"
  if [ -n "$wt_path" ] && [ -d "$wt_path" ]; then
    work_dir="$wt_path"
  fi

  # Generate commit message from task artifacts
  local goal
  goal="$(sed -n 's/^# Task: //p' "$task_dir/task.md" | head -1)"
  goal="${goal:-$id}"

  local approach
  approach="$(sed -n '/^## Approach/,/^## /{ /^## Approach/d; /^## /d; /^$/d; /^<!--/d; p; }' "$task_dir/plan.md" 2>/dev/null | head -3)"

  local verify_result
  verify_result="$(grep -m1 'Result:' "$task_dir/verify.md" 2>/dev/null | sed 's/.*\*\*Result:\*\*[[:space:]]*//')"

  # Build commit message
  local commit_msg
  commit_msg="feat: $goal

Task: $id
Verification: ${verify_result:-unknown}"

  if [ -n "$approach" ]; then
    commit_msg="$commit_msg

Approach:
$approach"
  fi

  # Stage and commit
  cd "$work_dir"

  # Check for changes
  if [ -z "$(git status --porcelain 2>/dev/null)" ]; then
    echo "openharness commit: no changes to commit" >&2
    exit 1
  fi

  git add -A
  git commit -m "$commit_msg"

  # Update status to delivered
  local attempt vp lfc created_at
  attempt="$(_oh_read_num_field "$task_dir" "attempt")"
  created_at="$(sed -n 's/.*"created_at"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$task_dir/status.json" | head -1)"
  _oh_write_status "$task_dir" "$id" "delivered" "$attempt" "true" "" "delivered" "$created_at"

  # Re-add worktree fields if they existed
  local branch
  branch="$(sed -n 's/.*"branch"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$task_dir/status.json" | head -1)"
  if [ -n "$branch" ] || [ -n "$wt_path" ]; then
    local tmp_file="$task_dir/status.json.tmp"
    sed '$ d' "$task_dir/status.json" > "$tmp_file"
    printf '  "branch": "%s",\n  "worktree_path": "%s"\n}\n' "${branch:-}" "${wt_path:-}" >> "$tmp_file"
    mv "$tmp_file" "$task_dir/status.json"
  fi

  echo "Committed and delivered: $id"
}

oh_pr() {
  case "${1:-}" in
    --help|-h)
      echo "Usage: openharness pr"
      echo ""
      echo "Create a PR from the task's worktree branch."
      echo "Uses 'gh' CLI if available, otherwise writes a draft."
      return 0
      ;;
  esac

  _oh_require_init

  local task_dir
  if ! task_dir="$(_oh_active_task_dir)"; then
    echo "openharness pr: no active task" >&2
    exit 1
  fi

  local root
  root="$(_oh_repo_root)"
  local id status
  id="$(_oh_read_field "$task_dir" "id")"
  status="$(_oh_read_field "$task_dir" "status")"

  if [ "$status" != "delivered" ]; then
    echo "openharness pr: task must be in 'delivered' state (current: $status)" >&2
    echo "Run 'openharness commit' first." >&2
    exit 1
  fi

  # Read config
  local config="$root/.openharness/config.json"
  local base_branch
  base_branch="$(sed -n 's/.*"pr_base_branch"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$config" | head -1)"
  base_branch="${base_branch:-main}"

  # Read task info for PR body
  local goal
  goal="$(sed -n 's/^# Task: //p' "$task_dir/task.md" | head -1)"
  goal="${goal:-$id}"

  local verify_result
  verify_result="$(grep -m1 'Result:' "$task_dir/verify.md" 2>/dev/null | sed 's/.*\*\*Result:\*\*[[:space:]]*//')"

  local verify_output
  verify_output="$(sed -n '/^### Output/,/^```$/{ /^### Output/d; /^```/d; p; }' "$task_dir/verify.md" 2>/dev/null | head -20)"

  local approach
  approach="$(sed -n '/^## Approach/,/^## /{ /^## Approach/d; /^## /d; /^$/d; /^<!--/d; p; }' "$task_dir/plan.md" 2>/dev/null | head -5)"

  local risks
  risks="$(sed -n '/^## Risks/,/^## /{ /^## Risks/d; /^## /d; /^$/d; /^<!--/d; p; }' "$task_dir/plan.md" 2>/dev/null | head -5)"
  risks="${risks:-None identified}"

  # Build PR body
  local pr_title="$goal"
  local pr_body="## Summary

- Task: \`$id\`
- $goal

## Approach

${approach:-See plan.md for details}

## Verification

- Result: **${verify_result:-unknown}**

## Known Risks

${risks}

---
Generated by [OpenHarness](https://github.com/user/openharness)"

  # Get branch name
  local branch
  branch="$(sed -n 's/.*"branch"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$task_dir/status.json" | head -1)"

  # Try gh CLI first
  if command -v gh >/dev/null 2>&1 && [ -n "$branch" ]; then
    # Push branch first
    local work_dir="$root"
    local wt_path
    wt_path="$(sed -n 's/.*"worktree_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$task_dir/status.json" | head -1)"
    if [ -n "$wt_path" ] && [ -d "$wt_path" ]; then
      work_dir="$wt_path"
    fi

    echo "Pushing branch $branch..."
    cd "$work_dir"
    git push -u origin "$branch" 2>&1 || true

    echo "Creating PR..."
    gh pr create \
      --base "$base_branch" \
      --head "$branch" \
      --title "$pr_title" \
      --body "$pr_body" 2>&1

    echo ""
    echo "PR created for task: $id"
  else
    # Write PR draft to task directory
    local draft_file="$task_dir/pr-draft.md"
    cat > "$draft_file" <<PRDRAFT
# PR: $pr_title

**Base:** $base_branch
**Head:** ${branch:-<branch>}

$pr_body
PRDRAFT

    echo "PR draft written to: $draft_file"
    if [ -z "$branch" ]; then
      echo "Note: no worktree branch found. Create one with 'openharness worktree create'."
    fi
    if ! command -v gh >/dev/null 2>&1; then
      echo "Note: 'gh' CLI not found. Install it to create PRs automatically."
    fi
  fi
}
