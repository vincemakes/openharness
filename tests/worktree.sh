#!/bin/sh
# OpenHarness worktree test — validates git worktree isolation
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

# --- Setup ---
TMPDIR="$(mktemp -d)"
cd "$TMPDIR"
git init -q
echo "initial content" > file.txt
git add file.txt
git commit -q -m "initial commit"

echo "=== OpenHarness Worktree Test ==="
echo "Working dir: $TMPDIR"
echo ""

# Init
sh "$OPENHARNESS_BIN" init >/dev/null

# Create task
sh "$OPENHARNESS_BIN" start-task "add search" >/dev/null
TASK_ID="$(cat .openharness/active-task)"

# --- Test: Create worktree ---
echo "--- Create worktree ---"
sh "$OPENHARNESS_BIN" worktree create >/dev/null 2>&1
BRANCH="oh/$TASK_ID"
WT_PATH=".openharness/worktrees/$TASK_ID"

if [ -d "$WT_PATH" ]; then
  pass "worktree directory created"
else
  fail "worktree directory missing"
fi

if git rev-parse --verify "$BRANCH" >/dev/null 2>&1; then
  pass "branch $BRANCH exists"
else
  fail "branch missing"
fi

# --- Test: Worktree isolation ---
echo "--- Isolation ---"
echo "worktree-only change" > "$WT_PATH/new-file.txt"
if [ ! -f "new-file.txt" ]; then
  pass "main branch unaffected by worktree changes"
else
  fail "worktree changes leaked to main"
fi

if [ -f "$WT_PATH/file.txt" ]; then
  pass "worktree has original files"
else
  fail "worktree missing original files"
fi

# --- Test: Status shows worktree info ---
echo "--- Status ---"
OUTPUT="$(sh "$OPENHARNESS_BIN" status 2>&1)"
if echo "$OUTPUT" | grep -q "Branch:"; then
  pass "status shows branch"
else
  fail "status missing branch info"
fi

if echo "$OUTPUT" | grep -q "Worktree:"; then
  pass "status shows worktree path"
else
  fail "status missing worktree path"
fi

# --- Test: Worktree status subcommand ---
OUTPUT="$(sh "$OPENHARNESS_BIN" worktree status 2>&1)"
if echo "$OUTPUT" | grep -q "Exists:     yes"; then
  pass "worktree status reports exists"
else
  fail "worktree status wrong"
fi

# --- Test: Duplicate create fails ---
echo "--- Guards ---"
set +e
OUTPUT="$(sh "$OPENHARNESS_BIN" worktree create 2>&1)"
EXIT_CODE=$?
set -e
assert_exit 1 "$EXIT_CODE" "duplicate worktree create rejected"

# --- Test: Remove worktree ---
echo "--- Remove ---"
sh "$OPENHARNESS_BIN" worktree remove >/dev/null 2>&1
if [ ! -d "$WT_PATH" ]; then
  pass "worktree directory removed"
else
  fail "worktree directory still exists"
fi

if ! git rev-parse --verify "$BRANCH" >/dev/null 2>&1; then
  pass "branch cleaned up"
else
  fail "branch still exists"
fi

# --- Summary ---
echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
rm -rf "$TMPDIR"

if [ "$FAIL" -gt 0 ]; then exit 1; fi
