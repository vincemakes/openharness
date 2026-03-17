#!/bin/sh
# OpenHarness intake gate test — validates Done Condition and Verification Path enforcement
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

echo "=== OpenHarness Intake Gate Test ==="
echo "Working dir: $TMPDIR"
echo ""

sh "$OPENHARNESS_BIN" init >/dev/null
printf '{"verify_command":"echo ok","max_verify_attempts":3,"pr_base_branch":"main"}' > .openharness/config.json

# --- Test: Advance blocked without task.md content ---
echo "--- Advance blocked without task.md ---"
sh "$OPENHARNESS_BIN" start-task "no task content" >/dev/null
TASK_DIR1=".openharness/tasks/$(cat .openharness/active-task)"

set +e
OUTPUT="$(sh "$OPENHARNESS_BIN" advance 2>&1)"
assert_exit 1 $? "advance blocked when task.md has no content"
set -e

# --- Test: Advance blocked with only Done Condition ---
echo "--- Advance blocked with only Done Condition ---"
sh "$OPENHARNESS_BIN" start-task "only done" >/dev/null
TASK_DIR2=".openharness/tasks/$(cat .openharness/active-task)"
printf '## Done Condition\nAll tests pass\n' >> "$TASK_DIR2/task.md"

set +e
OUTPUT="$(sh "$OPENHARNESS_BIN" advance 2>&1)"
assert_exit 1 $? "advance blocked when Verification Path is missing"
set -e

# --- Test: Advance blocked with only Verification Path ---
echo "--- Advance blocked with only Verification Path ---"
sh "$OPENHARNESS_BIN" start-task "only verify path" >/dev/null
TASK_DIR3=".openharness/tasks/$(cat .openharness/active-task)"
printf '## Verification Path\nunit tests\n' >> "$TASK_DIR3/task.md"

set +e
OUTPUT="$(sh "$OPENHARNESS_BIN" advance 2>&1)"
assert_exit 1 $? "advance blocked when Done Condition is missing"
set -e

# --- Test: Advance blocked with empty Done Condition ---
echo "--- Advance blocked with empty sections ---"
sh "$OPENHARNESS_BIN" start-task "empty sections" >/dev/null
TASK_DIR4=".openharness/tasks/$(cat .openharness/active-task)"
printf '## Done Condition\n\n## Verification Path\n\n' >> "$TASK_DIR4/task.md"

set +e
OUTPUT="$(sh "$OPENHARNESS_BIN" advance 2>&1)"
assert_exit 1 $? "advance blocked when sections are empty"
set -e

# --- Test: Advance succeeds with both fields filled ---
echo "--- Advance succeeds with both fields ---"
sh "$OPENHARNESS_BIN" start-task "complete intake" >/dev/null
TASK_DIR5=".openharness/tasks/$(cat .openharness/active-task)"
printf '## Done Condition\nAll unit tests pass and UI renders correctly\n\n## Verification Path\nunit tests\n' >> "$TASK_DIR5/task.md"

sh "$OPENHARNESS_BIN" advance >/dev/null
assert_contains "$TASK_DIR5/status.json" '"status": "planning"'

# --- Test: task.md template contains required sections ---
echo "--- task.md template sections ---"
sh "$OPENHARNESS_BIN" start-task "check template" >/dev/null
TEMPLATE_DIR=".openharness/tasks/$(cat .openharness/active-task)"
assert_contains "$TEMPLATE_DIR/task.md" "## Done Condition"
assert_contains "$TEMPLATE_DIR/task.md" "## Verification Path"

# --- Test: Error message mentions the missing section ---
echo "--- Error message quality ---"
sh "$OPENHARNESS_BIN" start-task "check error msg" >/dev/null
ERROR_DIR=".openharness/tasks/$(cat .openharness/active-task)"
set +e
OUTPUT="$(sh "$OPENHARNESS_BIN" advance 2>&1)"
EXIT_CODE=$?
set -e
assert_exit 1 "$EXIT_CODE" "advance blocked"
if echo "$OUTPUT" | grep -q "Done Condition"; then
  pass "error mentions Done Condition"
else
  fail "error should mention Done Condition"
fi

# --- Summary ---
echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
rm -rf "$TMPDIR"

if [ "$FAIL" -gt 0 ]; then exit 1; fi
