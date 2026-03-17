#!/bin/sh
# OpenHarness handoff test — validates repo-level HANDOFF.md creation
set -eu

OPENHARNESS_BIN="$(cd "$(dirname "$0")/../bin" && pwd)/openharness"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

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

assert_not_file() {
  if [ ! -f "$1" ]; then pass "file absent: $1"; else fail "file should not exist: $1"; fi
}

# --- Setup ---
TMPDIR="$(mktemp -d)"
cd "$TMPDIR"
git init -q
echo "initial" > file.txt
git add file.txt
git commit -q -m "initial commit"

echo "=== OpenHarness Handoff Test ==="
echo "Working dir: $TMPDIR"
echo ""

sh "$OPENHARNESS_BIN" init >/dev/null
printf '{"verify_command":"echo ok","max_verify_attempts":3,"pr_base_branch":"main"}' > .openharness/config.json

# --- Test: HANDOFF.md not created before handoff ---
echo "--- HANDOFF.md not present before handoff ---"
assert_not_file ".openharness/HANDOFF.md"

# --- Test: Complete lifecycle produces HANDOFF.md ---
echo "--- Lifecycle produces HANDOFF.md ---"
sh "$OPENHARNESS_BIN" start-task "test handoff pointer" >/dev/null
TASK_ID="$(cat .openharness/active-task)"
TASK_DIR=".openharness/tasks/$TASK_ID"

fill_task_md "$TASK_DIR"
sh "$OPENHARNESS_BIN" advance >/dev/null
printf '## Goal\nTest handoff MD\n' > "$TASK_DIR/plan.md"
sh "$OPENHARNESS_BIN" advance >/dev/null
sh "$OPENHARNESS_BIN" verify >/dev/null
sh "$OPENHARNESS_BIN" handoff >/dev/null

assert_file ".openharness/HANDOFF.md"
assert_contains ".openharness/HANDOFF.md" "$TASK_ID"
assert_contains ".openharness/HANDOFF.md" "ready_for_human_review"
assert_contains ".openharness/HANDOFF.md" "Last updated"
assert_contains ".openharness/HANDOFF.md" "What Was Done"

# --- Test: HANDOFF.md is NOT gitignored ---
echo "--- HANDOFF.md not gitignored ---"
if grep -q 'HANDOFF.md' .gitignore 2>/dev/null; then
  fail "HANDOFF.md should not be in .gitignore"
else
  pass "HANDOFF.md not in .gitignore"
fi

# --- Test: HANDOFF.md overwritten on second handoff ---
echo "--- HANDOFF.md overwritten on re-handoff ---"
sh "$OPENHARNESS_BIN" start-task "second handoff task" >/dev/null
TASK_ID2="$(cat .openharness/active-task)"
TASK_DIR2=".openharness/tasks/$TASK_ID2"

fill_task_md "$TASK_DIR2"
sh "$OPENHARNESS_BIN" advance >/dev/null
printf '## Goal\nSecond task\n' > "$TASK_DIR2/plan.md"
sh "$OPENHARNESS_BIN" advance >/dev/null
sh "$OPENHARNESS_BIN" verify >/dev/null
sh "$OPENHARNESS_BIN" handoff >/dev/null

assert_contains ".openharness/HANDOFF.md" "$TASK_ID2"

# --- Test: per-task handoff.md still generated ---
echo "--- Per-task handoff.md still generated ---"
assert_file "$TASK_DIR2/handoff.md"
assert_contains "$TASK_DIR2/handoff.md" "ready_for_human_review"

# --- Test: Session-start hook reports HANDOFF.md presence ---
echo "--- Session-start hook mentions HANDOFF.md ---"
HOOK_OUT="$("$(dirname "$OPENHARNESS_BIN")/../hooks/session-start" 2>/dev/null || echo '')"
if echo "$HOOK_OUT" | grep -q "HANDOFF.md"; then
  pass "session-start hook mentions HANDOFF.md"
else
  fail "session-start hook should mention HANDOFF.md when it exists"
fi

# --- Summary ---
echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
rm -rf "$TMPDIR"

if [ "$FAIL" -gt 0 ]; then exit 1; fi
