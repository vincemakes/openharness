#!/bin/sh
# OpenHarness maintenance test — validates maintain and gc commands
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
echo "initial" > file.txt
git add file.txt
git commit -q -m "initial commit"

echo "=== OpenHarness Maintenance Test ==="
echo "Working dir: $TMPDIR"
echo ""

# Init
sh "$OPENHARNESS_BIN" init >/dev/null
printf '{"verify_command":"echo ok","cleanup_command":"","max_verify_attempts":3,"pr_base_branch":"main","interactive_verify":{"dev_server_command":"","dev_server_url":"","dev_server_timeout":30}}' > .openharness/config.json

# --- Test: Maintain with no issues ---
echo "--- Maintain (clean) ---"
OUTPUT="$(sh "$OPENHARNESS_BIN" maintain 2>&1)"
if echo "$OUTPUT" | grep -q "No issues found"; then
  pass "maintain reports no issues on clean state"
else
  fail "maintain should report no issues"
fi

# --- Test: Maintain detects stale fixing tasks ---
echo "--- Maintain detects stale fixing ---"
sh "$OPENHARNESS_BIN" start-task "stale fixer" >/dev/null
STALE_ID="$(cat .openharness/active-task)"
STALE_DIR=".openharness/tasks/$STALE_ID"

# Manually set to fixing with old timestamp
cat > "$STALE_DIR/status.json" <<EOF
{
  "id": "$STALE_ID",
  "status": "fixing",
  "attempt": 1,
  "verification_passed": false,
  "last_failed_command": null,
  "handoff_state": null,
  "created_at": "2026-03-13T10:00:00Z",
  "updated_at": "2026-03-13T10:00:00Z"
}
EOF

OUTPUT="$(sh "$OPENHARNESS_BIN" maintain 2>&1)"
if echo "$OUTPUT" | grep -q "STALE.*$STALE_ID"; then
  pass "maintain detects stale fixing task"
else
  fail "maintain should detect stale fixing task"
fi

# --- Test: Maintain detects blocked tasks ---
echo "--- Maintain detects blocked ---"
sh "$OPENHARNESS_BIN" start-task "blocked task" >/dev/null
BLOCKED_ID="$(cat .openharness/active-task)"
BLOCKED_DIR=".openharness/tasks/$BLOCKED_ID"

cat > "$BLOCKED_DIR/status.json" <<EOF
{
  "id": "$BLOCKED_ID",
  "status": "blocked",
  "attempt": 3,
  "verification_passed": false,
  "last_failed_command": "echo fail",
  "handoff_state": "blocked",
  "created_at": "2026-03-14T10:00:00Z",
  "updated_at": "2026-03-14T10:00:00Z"
}
EOF

OUTPUT="$(sh "$OPENHARNESS_BIN" maintain 2>&1)"
if echo "$OUTPUT" | grep -q "BLOCKED.*$BLOCKED_ID"; then
  pass "maintain detects blocked task"
else
  fail "maintain should detect blocked task"
fi

# --- Test: Maintain detects orphaned worktrees ---
echo "--- Maintain detects orphaned worktrees ---"
sh "$OPENHARNESS_BIN" start-task "orphan wt" >/dev/null
ORPHAN_ID="$(cat .openharness/active-task)"
ORPHAN_DIR=".openharness/tasks/$ORPHAN_ID"

# Set worktree_path to non-existent directory
cat > "$ORPHAN_DIR/status.json" <<EOF
{
  "id": "$ORPHAN_ID",
  "status": "implementing",
  "attempt": 0,
  "verification_passed": false,
  "last_failed_command": null,
  "handoff_state": null,
  "created_at": "2026-03-15T10:00:00Z",
  "updated_at": "2026-03-15T10:00:00Z",
  "branch": "oh/$ORPHAN_ID",
  "worktree_path": "/tmp/nonexistent-worktree-path"
}
EOF

OUTPUT="$(sh "$OPENHARNESS_BIN" maintain 2>&1)"
if echo "$OUTPUT" | grep -q "ORPHANED WORKTREE.*$ORPHAN_ID"; then
  pass "maintain detects orphaned worktree"
else
  fail "maintain should detect orphaned worktree"
fi

# --- Test: GC removes delivered worktrees ---
echo "--- GC removes delivered worktrees ---"
sh "$OPENHARNESS_BIN" start-task "gc target" >/dev/null
GC_ID="$(cat .openharness/active-task)"
GC_DIR=".openharness/tasks/$GC_ID"

# Create actual worktree
sh "$OPENHARNESS_BIN" worktree create >/dev/null 2>&1
GC_BRANCH="oh/$GC_ID"
GC_WT=".openharness/worktrees/$GC_ID"

# Set to delivered
cat > "$GC_DIR/status.json" <<EOF
{
  "id": "$GC_ID",
  "status": "delivered",
  "attempt": 1,
  "verification_passed": true,
  "last_failed_command": null,
  "handoff_state": "ready_for_human_review",
  "created_at": "2026-03-15T10:00:00Z",
  "updated_at": "2026-03-15T10:00:00Z",
  "branch": "$GC_BRANCH",
  "worktree_path": "$GC_WT"
}
EOF

sh "$OPENHARNESS_BIN" gc >/dev/null 2>&1
if [ ! -d "$GC_WT" ]; then
  pass "gc removes delivered worktree"
else
  fail "gc should remove delivered worktree"
fi

if ! git rev-parse --verify "$GC_BRANCH" >/dev/null 2>&1; then
  pass "gc deletes delivered branch"
else
  fail "gc should delete delivered branch"
fi

# --- Test: GC skips non-terminal tasks ---
echo "--- GC skips non-terminal ---"
sh "$OPENHARNESS_BIN" start-task "gc skip me" >/dev/null
SKIP_ID="$(cat .openharness/active-task)"
SKIP_DIR=".openharness/tasks/$SKIP_ID"

sh "$OPENHARNESS_BIN" worktree create >/dev/null 2>&1
SKIP_WT=".openharness/worktrees/$SKIP_ID"

sh "$OPENHARNESS_BIN" gc >/dev/null 2>&1
if [ -d "$SKIP_WT" ]; then
  pass "gc skips non-terminal task worktree"
else
  fail "gc should not remove active task worktree"
fi

# --- Test: GC with --purge removes task directory ---
echo "--- GC --purge ---"
# Use the blocked task from earlier
printf '%s' "$BLOCKED_ID" > .openharness/active-task

sh "$OPENHARNESS_BIN" gc --purge >/dev/null 2>&1
if [ ! -d "$BLOCKED_DIR" ]; then
  pass "gc --purge removes blocked task directory"
else
  fail "gc --purge should remove task directory"
fi

# Also check the delivered task dir was purged
if [ ! -d "$GC_DIR" ]; then
  pass "gc --purge removes delivered task directory"
else
  fail "gc --purge should remove delivered task directory"
fi

# --- Summary ---
echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
rm -rf "$TMPDIR"

if [ "$FAIL" -gt 0 ]; then exit 1; fi
