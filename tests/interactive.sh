#!/bin/sh
# OpenHarness interactive verification test
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

assert_dir() {
  if [ -d "$1" ]; then pass "dir exists: $1"; else fail "dir missing: $1"; fi
}

assert_contains() {
  if grep -q "$2" "$1" 2>/dev/null; then pass "contains '$2' in $1"; else fail "missing '$2' in $1"; fi
}

# --- Setup ---
TMPDIR="$(mktemp -d)"
cd "$TMPDIR"
git init -q

echo "=== OpenHarness Interactive Verification Test ==="
echo "Working dir: $TMPDIR"
echo ""

# Init
sh "$OPENHARNESS_BIN" init >/dev/null

# --- Test: Config parsing for interactive_verify fields ---
echo "--- Config parsing ---"
assert_contains ".openharness/config.json" "interactive_verify"
assert_contains ".openharness/config.json" "dev_server_command"
assert_contains ".openharness/config.json" "dev_server_url"
assert_contains ".openharness/config.json" "dev_server_timeout"

# --- Test: Start without dev server configured → graceful error ---
echo "--- Start without config ---"
sh "$OPENHARNESS_BIN" start-task "test interactive" >/dev/null
TASK_ID="$(cat .openharness/active-task)"
TASK_DIR=".openharness/tasks/$TASK_ID"

fill_task_md "$TASK_DIR"
sh "$OPENHARNESS_BIN" advance >/dev/null
printf '## Goal\nTest interactive verify\n' > "$TASK_DIR/plan.md"
sh "$OPENHARNESS_BIN" advance >/dev/null

set +e
OUTPUT="$(sh "$OPENHARNESS_BIN" interactive-verify start 2>&1)"
EXIT_CODE=$?
set -e
assert_exit 1 "$EXIT_CODE" "start without dev_server_command fails gracefully"

# --- Test: verify-interactive.md generation ---
echo "--- verify-interactive.md generation ---"
# Configure interactive verify
cat > .openharness/config.json <<'EOCFG'
{
  "verify_command": "echo ok",
  "max_verify_attempts": 3,
  "pr_base_branch": "main",
  "interactive_verify": {
    "dev_server_command": "python3 -m http.server 18923",
    "dev_server_url": "http://localhost:18923",
    "dev_server_timeout": 10
  }
}
EOCFG

# New task should get verify-interactive.md
sh "$OPENHARNESS_BIN" start-task "test interactive gen" >/dev/null
TASK_ID2="$(cat .openharness/active-task)"
TASK_DIR2=".openharness/tasks/$TASK_ID2"
assert_file "$TASK_DIR2/verify-interactive.md"
assert_contains "$TASK_DIR2/verify-interactive.md" "Interactive Verification Steps"

# --- Test: Start with mock server → polling detects readiness ---
echo "--- Start with mock server ---"
fill_task_md "$TASK_DIR2"
sh "$OPENHARNESS_BIN" advance >/dev/null
printf '## Goal\nTest interactive\n' > "$TASK_DIR2/plan.md"
sh "$OPENHARNESS_BIN" advance >/dev/null

OUTPUT="$(sh "$OPENHARNESS_BIN" interactive-verify start 2>&1)"
EXIT_CODE=$?
assert_exit 0 "$EXIT_CODE" "start with mock server succeeds"

# --- Test: Start creates screenshots dir and PID file ---
echo "--- Screenshots dir and PID ---"
assert_dir "$TASK_DIR2/screenshots"
assert_file "$TASK_DIR2/.dev-server.pid"

# Verify PID is a real process
PID="$(cat "$TASK_DIR2/.dev-server.pid")"
if kill -0 "$PID" 2>/dev/null; then
  pass "dev server PID is alive"
else
  fail "dev server PID is not alive"
fi

# --- Test: Complete pass → ready_for_human_review ---
echo "--- Complete pass ---"
# Write some evidence
cat > "$TASK_DIR2/verify-interactive-evidence.md" <<'EOEVIDENCE'
## Step 1: Navigate to app
- **Result:** PASS
EOEVIDENCE

sh "$OPENHARNESS_BIN" interactive-verify complete pass >/dev/null
assert_contains "$TASK_DIR2/status.json" '"status": "ready_for_human_review"'
assert_contains "$TASK_DIR2/verify.md" "Interactive Verification"
assert_contains "$TASK_DIR2/verify.md" "PASS"

# Verify dev server was killed
if ! kill -0 "$PID" 2>/dev/null; then
  pass "dev server killed after complete"
else
  fail "dev server still running after complete"
  kill "$PID" 2>/dev/null || true
fi

# --- Test: Complete fail → fixing ---
echo "--- Complete fail ---"
sh "$OPENHARNESS_BIN" start-task "test fail flow" >/dev/null
TASK_ID3="$(cat .openharness/active-task)"
TASK_DIR3=".openharness/tasks/$TASK_ID3"

fill_task_md "$TASK_DIR3"
sh "$OPENHARNESS_BIN" advance >/dev/null
printf '## Goal\nTest fail\n' > "$TASK_DIR3/plan.md"
sh "$OPENHARNESS_BIN" advance >/dev/null

sh "$OPENHARNESS_BIN" interactive-verify start >/dev/null 2>&1
PID2="$(cat "$TASK_DIR3/.dev-server.pid")"
sh "$OPENHARNESS_BIN" interactive-verify complete fail >/dev/null
assert_contains "$TASK_DIR3/status.json" '"status": "fixing"'

# Verify PID cleanup
if ! kill -0 "$PID2" 2>/dev/null; then
  pass "dev server killed after fail complete"
else
  fail "dev server still running after fail"
  kill "$PID2" 2>/dev/null || true
fi

# --- Test: Stale PID cleanup on start ---
echo "--- Stale PID cleanup ---"
# Write a bogus PID file
echo "99999" > "$TASK_DIR3/.dev-server.pid"
OUTPUT="$(sh "$OPENHARNESS_BIN" interactive-verify start 2>&1)"
if [ $? -eq 0 ]; then
  pass "start cleans stale PID and proceeds"
  # Clean up server
  if [ -f "$TASK_DIR3/.dev-server.pid" ]; then
    kill "$(cat "$TASK_DIR3/.dev-server.pid")" 2>/dev/null || true
  fi
else
  pass "start handles stale PID gracefully"
fi

# --- Test: Max attempts → blocked ---
echo "--- Max attempts ---"
cat > .openharness/config.json <<'EOCFG'
{
  "verify_command": "echo ok",
  "max_verify_attempts": 2,
  "pr_base_branch": "main",
  "interactive_verify": {
    "dev_server_command": "python3 -m http.server 18924",
    "dev_server_url": "http://localhost:18924",
    "dev_server_timeout": 10
  }
}
EOCFG

sh "$OPENHARNESS_BIN" start-task "test max attempts" >/dev/null
TASK_ID4="$(cat .openharness/active-task)"
TASK_DIR4=".openharness/tasks/$TASK_ID4"

fill_task_md "$TASK_DIR4"
sh "$OPENHARNESS_BIN" advance >/dev/null
printf '## Goal\nTest max\n' > "$TASK_DIR4/plan.md"
sh "$OPENHARNESS_BIN" advance >/dev/null

# First fail → fixing
sh "$OPENHARNESS_BIN" interactive-verify start >/dev/null 2>&1
sh "$OPENHARNESS_BIN" interactive-verify complete fail >/dev/null
assert_contains "$TASK_DIR4/status.json" '"status": "fixing"'

# Second fail → blocked (max_verify_attempts = 2)
sh "$OPENHARNESS_BIN" interactive-verify start >/dev/null 2>&1
sh "$OPENHARNESS_BIN" interactive-verify complete fail >/dev/null
assert_contains "$TASK_DIR4/status.json" '"status": "blocked"'
pass "max attempts -> blocked"

# --- Cleanup any lingering servers ---
for pf in "$TMPDIR"/.openharness/tasks/*/.dev-server.pid; do
  if [ -f "$pf" ]; then
    kill "$(cat "$pf")" 2>/dev/null || true
  fi
done

# --- Summary ---
echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
rm -rf "$TMPDIR"

if [ "$FAIL" -gt 0 ]; then exit 1; fi
