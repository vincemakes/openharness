#!/bin/sh
# OpenHarness delivery test — validates cleanup, commit, PR draft
set -eu

OPENHARNESS_BIN="$(cd "$(dirname "$0")/../bin" && pwd)/openharness"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

assert_exit() {
  local expected="$1" actual="$2" label="$3"
  if [ "$expected" = "$actual" ]; then pass "$label"; else fail "$label (expected exit $expected, got $actual)"; fi
}

assert_contains() {
  if grep -q "$2" "$1" 2>/dev/null; then pass "contains '$2' in $1"; else fail "missing '$2' in $1"; fi
}

# --- Setup ---
TMPDIR="$(mktemp -d)"
cd "$TMPDIR"
git init -q
echo "initial" > file.txt
git add file.txt
git commit -q -m "initial commit"

echo "=== OpenHarness Delivery Test ==="
echo "Working dir: $TMPDIR"
echo ""

# Init with full config
sh "$OPENHARNESS_BIN" init >/dev/null
printf '{"verify_command":"echo all tests passed","cleanup_command":"echo cleaned up","max_verify_attempts":3,"pr_base_branch":"main"}' > .openharness/config.json

# Create task and advance to implementing
sh "$OPENHARNESS_BIN" start-task "add user search" >/dev/null
TASK_ID="$(cat .openharness/active-task)"
TASK_DIR=".openharness/tasks/$TASK_ID"

sh "$OPENHARNESS_BIN" advance >/dev/null
printf '## Goal\nAdd search\n\n## Approach\nNew component\n\n## Risks\nNone\n' > "$TASK_DIR/plan.md"
sh "$OPENHARNESS_BIN" advance >/dev/null

# Make changes
echo "search feature" > search.js

# Verify
sh "$OPENHARNESS_BIN" verify >/dev/null

# --- Test: Cleanup ---
echo "--- Cleanup ---"
sh "$OPENHARNESS_BIN" cleanup >/dev/null 2>&1
pass "cleanup runs successfully"

# --- Test: Cleanup with no config ---
printf '{"verify_command":"echo ok","max_verify_attempts":3}' > .openharness/config.json
OUTPUT="$(sh "$OPENHARNESS_BIN" cleanup 2>&1)"
if echo "$OUTPUT" | grep -q "no cleanup_command"; then
  pass "cleanup skips gracefully without config"
else
  fail "cleanup should warn when no command configured"
fi
# Restore config
printf '{"verify_command":"echo all tests passed","cleanup_command":"echo cleaned up","max_verify_attempts":3,"pr_base_branch":"main"}' > .openharness/config.json

# --- Test: Commit guards ---
echo "--- Commit guards ---"
# Create another task in implementing to test guard
sh "$OPENHARNESS_BIN" start-task "test commit guard" >/dev/null
GUARD_ID="$(cat .openharness/active-task)"
sh "$OPENHARNESS_BIN" advance >/dev/null
printf '## Goal\nTest\n' > ".openharness/tasks/$GUARD_ID/plan.md"
sh "$OPENHARNESS_BIN" advance >/dev/null
set +e
OUTPUT="$(sh "$OPENHARNESS_BIN" commit 2>&1)"
assert_exit 1 $? "commit from implementing rejected"
set -e

# Switch back to verified task
printf '%s' "$TASK_ID" > .openharness/active-task

# --- Test: Commit ---
echo "--- Commit ---"
sh "$OPENHARNESS_BIN" commit >/dev/null 2>&1
assert_contains "$TASK_DIR/status.json" '"status": "delivered"'
pass "commit creates delivered status"

# Check commit message
LAST_MSG="$(git log -1 --pretty=%B)"
if echo "$LAST_MSG" | grep -q "feat:"; then
  pass "commit message has feat: prefix"
else
  fail "commit message missing prefix"
fi
if echo "$LAST_MSG" | grep -q "Task: $TASK_ID"; then
  pass "commit message references task ID"
else
  fail "commit message missing task ID"
fi

# --- Test: Commit from delivered rejects ---
echo "extra" > extra.txt
set +e
OUTPUT="$(sh "$OPENHARNESS_BIN" commit 2>&1)"
assert_exit 1 $? "commit from delivered rejected"
set -e

# --- Test: PR draft ---
echo "--- PR ---"
sh "$OPENHARNESS_BIN" pr >/dev/null 2>&1
if [ -f "$TASK_DIR/pr-draft.md" ]; then
  pass "PR draft file created"
else
  fail "PR draft missing"
fi
assert_contains "$TASK_DIR/pr-draft.md" "Summary"
assert_contains "$TASK_DIR/pr-draft.md" "$TASK_ID"
assert_contains "$TASK_DIR/pr-draft.md" "Verification"

# --- Test: PR from non-delivered state rejects ---
printf '%s' "$GUARD_ID" > .openharness/active-task
set +e
OUTPUT="$(sh "$OPENHARNESS_BIN" pr 2>&1)"
assert_exit 1 $? "pr from implementing rejected"
set -e

# --- Test: Verify failure -> fixing -> retry flow ---
echo "--- Verify failure flow ---"
printf '{"verify_command":"false","max_verify_attempts":3,"pr_base_branch":"main"}' > .openharness/config.json

sh "$OPENHARNESS_BIN" start-task "test verify retry" >/dev/null
RETRY_ID="$(cat .openharness/active-task)"
RETRY_DIR=".openharness/tasks/$RETRY_ID"

sh "$OPENHARNESS_BIN" advance >/dev/null
printf '## Goal\nTest\n' > "$RETRY_DIR/plan.md"
sh "$OPENHARNESS_BIN" advance >/dev/null

# First verify fails -> fixing
sh "$OPENHARNESS_BIN" verify >/dev/null 2>&1 || true
assert_contains "$RETRY_DIR/status.json" '"status": "fixing"'
pass "verify fail -> fixing"

# Second verify fails -> fixing (attempt 2)
sh "$OPENHARNESS_BIN" verify >/dev/null 2>&1 || true
assert_contains "$RETRY_DIR/status.json" '"status": "fixing"'
pass "second verify fail -> still fixing"

# Third verify fails -> blocked (max attempts)
sh "$OPENHARNESS_BIN" verify >/dev/null 2>&1 || true
assert_contains "$RETRY_DIR/status.json" '"status": "blocked"'
pass "third verify fail -> blocked"

# Verify from blocked is rejected
set +e
OUTPUT="$(sh "$OPENHARNESS_BIN" verify 2>&1)"
assert_exit 1 $? "verify from blocked rejected"
set -e

# --- Summary ---
echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
rm -rf "$TMPDIR"

if [ "$FAIL" -gt 0 ]; then exit 1; fi
