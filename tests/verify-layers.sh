#!/bin/sh
# OpenHarness verify layers test — validates layered verification system
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

assert_contains() {
  if grep -q "$2" "$1" 2>/dev/null; then pass "contains '$2' in $1"; else fail "missing '$2' in $1"; fi
}

# --- Setup ---
TMPDIR="$(mktemp -d)"
cd "$TMPDIR"
git init -q

echo "=== OpenHarness Verify Layers Test ==="
echo "Working dir: $TMPDIR"
echo ""

sh "$OPENHARNESS_BIN" init >/dev/null

# Helper: advance to implementing state
start_implementing() {
  local label="$1"
  sh "$OPENHARNESS_BIN" start-task "$label" >/dev/null
  local tid="$(cat .openharness/active-task)"
  local tdir=".openharness/tasks/$tid"
  fill_task_md "$tdir"
  sh "$OPENHARNESS_BIN" advance >/dev/null
  printf '## Goal\nTest verify layers\n' > "$tdir/plan.md"
  sh "$OPENHARNESS_BIN" advance >/dev/null
  echo "$tdir"
}

# --- Test: Backward compat — verify_command maps to standard ---
echo "--- Backward compatibility ---"
printf '{"verify_command":"echo compat-ok","max_verify_attempts":3,"pr_base_branch":"main"}' > .openharness/config.json
TDIR1="$(start_implementing "compat test")"

OUTPUT="$(sh "$OPENHARNESS_BIN" verify 2>&1)"
if echo "$OUTPUT" | grep -q "compat-ok"; then
  pass "verify_command backward compat works"
else
  fail "verify_command backward compat failed"
fi
assert_contains "$TDIR1/status.json" '"status": "ready_for_human_review"'

# --- Test: Layered config — default layer runs ---
echo "--- Default layer ---"
cat > .openharness/config.json <<'EOCFG'
{
  "verify_layers": {
    "fast": ["echo fast-ran"],
    "standard": ["echo standard-ran"],
    "full": ["echo full-ran"]
  },
  "default_verify_layer": "standard",
  "max_verify_attempts": 3,
  "pr_base_branch": "main"
}
EOCFG

TDIR2="$(start_implementing "default layer")"
OUTPUT="$(sh "$OPENHARNESS_BIN" verify 2>&1)"
if echo "$OUTPUT" | grep -q "fast-ran" && echo "$OUTPUT" | grep -q "standard-ran"; then
  pass "default standard runs fast + standard"
else
  fail "default standard should run fast + standard"
fi
if echo "$OUTPUT" | grep -q "full-ran"; then
  fail "default standard should NOT run full"
else
  pass "default standard skips full"
fi
assert_contains "$TDIR2/status.json" '"status": "ready_for_human_review"'

# --- Test: --fast flag runs only fast ---
echo "--- --fast flag ---"
TDIR3="$(start_implementing "fast flag")"
OUTPUT="$(sh "$OPENHARNESS_BIN" verify --fast 2>&1)"
if echo "$OUTPUT" | grep -q "fast-ran"; then
  pass "--fast runs fast layer"
else
  fail "--fast should run fast layer"
fi
if echo "$OUTPUT" | grep -q "standard-ran" || echo "$OUTPUT" | grep -q "full-ran"; then
  fail "--fast should not run standard or full"
else
  pass "--fast skips standard and full"
fi

# --- Test: --full flag runs all layers cumulatively ---
echo "--- --full flag ---"
TDIR4="$(start_implementing "full flag")"
OUTPUT="$(sh "$OPENHARNESS_BIN" verify --full 2>&1)"
if echo "$OUTPUT" | grep -q "fast-ran" && echo "$OUTPUT" | grep -q "standard-ran" && echo "$OUTPUT" | grep -q "full-ran"; then
  pass "--full runs all layers"
else
  fail "--full should run all layers"
fi

# --- Test: --layer <name> flag ---
echo "--- --layer flag ---"
TDIR5="$(start_implementing "layer flag")"
OUTPUT="$(sh "$OPENHARNESS_BIN" verify --layer standard 2>&1)"
if echo "$OUTPUT" | grep -q "fast-ran" && echo "$OUTPUT" | grep -q "standard-ran"; then
  pass "--layer standard runs fast + standard"
else
  fail "--layer standard should run fast + standard"
fi

# --- Test: --only flag skips lower layers ---
echo "--- --only flag ---"
TDIR6="$(start_implementing "only flag")"
OUTPUT="$(sh "$OPENHARNESS_BIN" verify --layer full --only 2>&1)"
if echo "$OUTPUT" | grep -q "full-ran"; then
  pass "--only full runs full layer"
else
  fail "--only full should run full layer"
fi
if echo "$OUTPUT" | grep -q "fast-ran" || echo "$OUTPUT" | grep -q "standard-ran"; then
  fail "--only should skip other layers"
else
  pass "--only skips other layers"
fi

# --- Test: verify failure in fast stops immediately ---
echo "--- Failure stops early ---"
cat > .openharness/config.json <<'EOCFG'
{
  "verify_layers": {
    "fast": ["false"],
    "standard": ["echo standard-should-not-run"],
    "full": []
  },
  "default_verify_layer": "standard",
  "max_verify_attempts": 3,
  "pr_base_branch": "main"
}
EOCFG

TDIR7="$(start_implementing "failure stops")"
OUTPUT="$(sh "$OPENHARNESS_BIN" verify 2>&1 || true)"
if echo "$OUTPUT" | grep -q "standard-should-not-run"; then
  fail "fast failure should stop before standard"
else
  pass "fast failure stops before standard"
fi
assert_contains "$TDIR7/status.json" '"status": "fixing"'

# --- Test: manual layer printed, not executed ---
echo "--- Manual layer ---"
cat > .openharness/config.json <<'EOCFG'
{
  "verify_layers": {
    "fast": ["echo fast-ok"],
    "standard": ["echo standard-ok"],
    "manual": ["Step 1: Open browser", "Step 2: Check homepage"]
  },
  "default_verify_layer": "standard",
  "max_verify_attempts": 3,
  "pr_base_branch": "main"
}
EOCFG

TDIR8="$(start_implementing "manual layer")"
OUTPUT="$(sh "$OPENHARNESS_BIN" verify --layer manual --only 2>&1)"
if echo "$OUTPUT" | grep -q "Step 1: Open browser"; then
  pass "manual layer prints checklist"
else
  fail "manual layer should print checklist"
fi
# manual layer doesn't actually fail anything
assert_contains "$TDIR8/status.json" '"status": "ready_for_human_review"'

# --- Test: empty layer skipped gracefully ---
echo "--- Empty layer skipped ---"
cat > .openharness/config.json <<'EOCFG'
{
  "verify_layers": {
    "fast": [],
    "standard": ["echo std-ok"],
    "full": []
  },
  "default_verify_layer": "standard",
  "max_verify_attempts": 3,
  "pr_base_branch": "main"
}
EOCFG

TDIR9="$(start_implementing "empty layers")"
OUTPUT="$(sh "$OPENHARNESS_BIN" verify 2>&1)"
if echo "$OUTPUT" | grep -q "std-ok"; then
  pass "non-empty standard runs when fast/full empty"
else
  fail "standard should run when fast/full empty"
fi
assert_contains "$TDIR9/status.json" '"status": "ready_for_human_review"'

# --- Summary ---
echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
rm -rf "$TMPDIR"

if [ "$FAIL" -gt 0 ]; then exit 1; fi
