#!/bin/sh
# OpenHarness instructions test — validates INSTRUCTIONS.md creation and migration
set -eu

OPENHARNESS_BIN="$(cd "$(dirname "$0")/../bin" && pwd)/openharness"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

assert_file() {
  if [ -f "$1" ]; then pass "file exists: $1"; else fail "file missing: $1"; fi
}

assert_contains() {
  if grep -q "$2" "$1" 2>/dev/null; then pass "contains '$2' in $1"; else fail "missing '$2' in $1"; fi
}

assert_not_contains() {
  if ! grep -q "$2" "$1" 2>/dev/null; then pass "does not contain '$2' in $1"; else fail "should not contain '$2' in $1"; fi
}

# --- Setup ---
TMPDIR="$(mktemp -d)"
cd "$TMPDIR"
git init -q

echo "=== OpenHarness Instructions Test ==="
echo "Working dir: $TMPDIR"
echo ""

# --- Test: Fresh init creates INSTRUCTIONS.md ---
echo "--- Fresh init ---"
sh "$OPENHARNESS_BIN" init >/dev/null
assert_file ".openharness/INSTRUCTIONS.md"
assert_contains ".openharness/INSTRUCTIONS.md" "OpenHarness"
assert_contains ".openharness/INSTRUCTIONS.md" "Lifecycle"
assert_contains ".openharness/INSTRUCTIONS.md" "Done Condition"
assert_contains ".openharness/INSTRUCTIONS.md" "Verification Path"

# --- Test: AGENTS.md is thin adapter pointing to INSTRUCTIONS.md ---
echo "--- AGENTS.md thin adapter ---"
assert_file "AGENTS.md"
assert_contains "AGENTS.md" "INSTRUCTIONS.md"
assert_not_contains "AGENTS.md" "## Lifecycle"

# --- Test: Idempotent init does not duplicate ---
echo "--- Idempotent init ---"
sh "$OPENHARNESS_BIN" init >/dev/null
AGENT_LINES="$(grep -c 'OpenHarness' AGENTS.md 2>/dev/null || echo 0)"
if [ "$AGENT_LINES" -le 3 ]; then
  pass "idempotent init does not duplicate AGENTS.md section"
else
  fail "AGENTS.md section duplicated on second init"
fi

# --- Test: Migration — existing repo gets INSTRUCTIONS.md ---
echo "--- Migration ---"
MIGRATE_DIR="$(mktemp -d)"
cd "$MIGRATE_DIR"
git init -q

# Simulate old-style init (copy old templates manually)
mkdir -p .openharness/tasks
printf '{"verify_command":"echo ok","max_verify_attempts":3}' > .openharness/config.json
printf '# OpenHarness Repo Guide\n\nOld content here.\n' > .openharness/REPO_GUIDE.md
printf '# OpenHarness Rules\n\nOld rules here.\n' > .openharness/RULES.md
printf '## OpenHarness\nSee RULES.md for enforcement rules.\n' > AGENTS.md

# Run init on existing repo — should migrate
sh "$OPENHARNESS_BIN" init >/dev/null 2>&1 || true

assert_file ".openharness/INSTRUCTIONS.md"
assert_contains ".openharness/INSTRUCTIONS.md" "OpenHarness"

# Old files should have deprecated header
assert_contains ".openharness/REPO_GUIDE.md" "DEPRECATED"
assert_contains ".openharness/RULES.md" "DEPRECATED"

# Old content preserved
assert_contains ".openharness/REPO_GUIDE.md" "Old content here"
assert_contains ".openharness/RULES.md" "Old rules here"

# AGENTS.md untouched (already has OpenHarness)
assert_contains "AGENTS.md" "RULES.md"

cd "$TMPDIR"

# --- Test: CLAUDE.md gets adapter section if it exists ---
echo "--- CLAUDE.md adapter ---"
CLAUDE_DIR="$(mktemp -d)"
cd "$CLAUDE_DIR"
git init -q
printf '## Tech Stack\nNext.js 15\n' > CLAUDE.md

sh "$OPENHARNESS_BIN" init >/dev/null

assert_contains "CLAUDE.md" "INSTRUCTIONS.md"
assert_contains "CLAUDE.md" "Tech Stack"

# Second init does not duplicate
sh "$OPENHARNESS_BIN" init >/dev/null 2>&1 || true
CLAUDE_OH="$(grep -c 'OpenHarness' CLAUDE.md 2>/dev/null || echo 0)"
if [ "$CLAUDE_OH" -le 2 ]; then
  pass "idempotent init does not duplicate CLAUDE.md section"
else
  fail "CLAUDE.md section duplicated on second init"
fi

cd "$TMPDIR"

# --- Summary ---
echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
rm -rf "$TMPDIR" "$MIGRATE_DIR" "$CLAUDE_DIR"

if [ "$FAIL" -gt 0 ]; then exit 1; fi
