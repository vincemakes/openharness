#!/bin/sh
# OpenHarness smoke test — validates the full lifecycle
set -eu

OPENHARNESS_BIN="$(cd "$(dirname "$0")/../bin" && pwd)/openharness"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

# Fill required intake fields so advance intake->planning succeeds
fill_task_md() {
  local task_dir="$1"
  printf '## Done Condition\nTask is complete when tests pass\n\n## Verification Path\nunit tests\n' >> "$task_dir/task.md"
}

assert_exit() {
  local expected="$1" actual="$2" label="$3"
  if [ "$expected" = "$actual" ]; then pass "$label"; else fail "$label (expected exit $expected, got $actual)"; fi
}

assert_file() {
  if [ -f "$1" ]; then pass "file exists: $1"; else fail "file missing: $1"; fi
}

assert_contains() {
  if grep -q "$2" "$1" 2>/dev/null; then pass "contains '$2' in $1"; else fail "missing '$2' in $1"; fi
}

# --- Setup ---
TMPDIR="$(mktemp -d)"
cd "$TMPDIR"
git init -q

echo "=== OpenHarness Smoke Test ==="
echo "Working dir: $TMPDIR"
echo ""

# --- Test: CLI help ---
echo "--- CLI ---"
sh "$OPENHARNESS_BIN" --help >/dev/null 2>&1
assert_exit 0 $? "CLI help"
sh "$OPENHARNESS_BIN" --version >/dev/null 2>&1
assert_exit 0 $? "CLI version"

# --- Test: Init ---
echo "--- Init ---"
sh "$OPENHARNESS_BIN" init >/dev/null
assert_file ".openharness/config.json"
assert_file ".openharness/REPO_GUIDE.md"
assert_file ".openharness/RULES.md"
assert_file "AGENTS.md"
assert_contains ".gitignore" "status.json"
assert_contains ".gitignore" "active-task"

# --- Test: Idempotent init ---
sh "$OPENHARNESS_BIN" init >/dev/null
assert_exit 0 $? "idempotent init"

# --- Test: Start task ---
echo "--- Task creation ---"
sh "$OPENHARNESS_BIN" start-task "fix streaming bug" >/dev/null
TASK_DIR="$(ls -1d .openharness/tasks/*/ | head -1)"
assert_file "${TASK_DIR}task.md"
assert_file "${TASK_DIR}plan.md"
assert_file "${TASK_DIR}status.json"
assert_contains "${TASK_DIR}status.json" '"status": "intake"'
assert_contains "${TASK_DIR}status.json" '"created_at"'
assert_contains "${TASK_DIR}status.json" '"updated_at"'

# --- Test: Active-task file ---
echo "--- Active-task file ---"
assert_file ".openharness/active-task"
ACTIVE_ID="$(cat .openharness/active-task)"
if echo "$TASK_DIR" | grep -q "$ACTIVE_ID"; then
  pass "active-task matches task directory"
else
  fail "active-task mismatch"
fi

# --- Test: Status ---
echo "--- Status ---"
OUTPUT="$(sh "$OPENHARNESS_BIN" status)"
echo "$OUTPUT" | grep -q "intake"
assert_exit 0 $? "status shows intake"

# --- Test: Hook enforcement (intake) ---
echo "--- Hook enforcement ---"
set +e
echo '{"tool_name":"Edit","tool_input":{"file_path":"/tmp/x.js","old_string":"a","new_string":"b"}}' | sh "$(dirname "$OPENHARNESS_BIN")/../hooks/pre-tool-use" 2>/dev/null
HOOK_EXIT=$?
set -e
assert_exit 2 "$HOOK_EXIT" "hook blocks Edit during intake"

# --- Test: Advance intake -> planning ---
echo "--- State transitions ---"
fill_task_md "$TASK_DIR"
sh "$OPENHARNESS_BIN" advance >/dev/null
assert_contains "${TASK_DIR}status.json" '"status": "planning"'

# --- Test: Hook enforcement (planning) ---
set +e
echo '{"tool_name":"Write","tool_input":{"file_path":"/tmp/x.js","content":"x"}}' | sh "$(dirname "$OPENHARNESS_BIN")/../hooks/pre-tool-use" 2>/dev/null
HOOK_EXIT=$?
set -e
assert_exit 2 "$HOOK_EXIT" "hook blocks Write during planning"

# --- Test: Advance planning -> implementing (requires plan content) ---
printf '## Goal\nFix the streaming bug\n\n## Affected Files\nstream.js\n\n## Approach\nFix ordering\n\n## Verification Commands\nnpm test\n\n## Risks\nNone\n' > "${TASK_DIR}plan.md"
sh "$OPENHARNESS_BIN" advance >/dev/null
assert_contains "${TASK_DIR}status.json" '"status": "implementing"'

# --- Test: Hook allows during implementing ---
set +e
echo '{"tool_name":"Edit","tool_input":{"file_path":"/tmp/x.js","old_string":"a","new_string":"b"}}' | sh "$(dirname "$OPENHARNESS_BIN")/../hooks/pre-tool-use" 2>/dev/null
HOOK_EXIT=$?
set -e
assert_exit 0 "$HOOK_EXIT" "hook allows Edit during implementing"

# --- Test: Illegal state transitions ---
echo "--- Illegal state transitions ---"
set +e
OUTPUT="$(sh "$OPENHARNESS_BIN" advance 2>&1)"
assert_exit 1 $? "advance from implementing rejected"

# Verify from intake is rejected
sh "$OPENHARNESS_BIN" start-task "test illegal verify" >/dev/null
ILLEGAL_DIR=".openharness/tasks/$(cat .openharness/active-task)"
OUTPUT="$(sh "$OPENHARNESS_BIN" verify 2>&1)"
assert_exit 1 $? "verify from intake rejected"

# Handoff from planning is rejected
fill_task_md "$ILLEGAL_DIR"
sh "$OPENHARNESS_BIN" advance >/dev/null
OUTPUT="$(sh "$OPENHARNESS_BIN" handoff 2>&1)"
assert_exit 1 $? "handoff from planning rejected"
set -e

# Switch back to first task for remaining tests
printf '%s' "$(echo "$TASK_DIR" | sed 's|.openharness/tasks/||;s|/||')" > .openharness/active-task

# --- Test: Verify (pass) ---
echo "--- Verification ---"
printf '{"verify_command":"echo all tests passed","cleanup_command":"echo cleaned","max_verify_attempts":3,"pr_base_branch":"main"}' > .openharness/config.json
sh "$OPENHARNESS_BIN" verify >/dev/null
assert_contains "${TASK_DIR}verify.md" "PASS"
assert_contains "${TASK_DIR}status.json" '"status": "ready_for_human_review"'

# --- Test: Verify from ready_for_human_review is rejected ---
set +e
OUTPUT="$(sh "$OPENHARNESS_BIN" verify 2>&1)"
assert_exit 1 $? "verify from ready_for_human_review rejected"
set -e

# --- Test: Handoff ---
echo "--- Handoff ---"
sh "$OPENHARNESS_BIN" handoff >/dev/null
assert_file "${TASK_DIR}handoff.md"
assert_contains "${TASK_DIR}handoff.md" "ready_for_human_review"
assert_contains "${TASK_DIR}status.json" '"handoff_state": "ready_for_human_review"'

# --- Summary ---
echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
rm -rf "$TMPDIR"

if [ "$FAIL" -gt 0 ]; then exit 1; fi
