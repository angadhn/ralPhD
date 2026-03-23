#!/usr/bin/env bash
# RED test: terminal prose in "## Next Task" extracts bogus agent names.
#
# Bug: detect.sh:42 does ${next_task##* } to get the agent name.
# When Next Task contains prose like "Thread ready for review", the
# function returns "review" — a non-existent agent — instead of empty.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$SCRIPT_DIR/lib/detect.sh"

TMPDIR_BASE=$(mktemp -d)
trap 'rm -rf "$TMPDIR_BASE"' EXIT

PASS=0
FAIL=0

pass() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

# -- Helper: create a checkpoint with a given Next Task body --
make_checkpoint() {
  local dir=$1 body=$2
  cat > "$dir/checkpoint.md" << EOF
# Checkpoint — test

**Thread:** test
**Status:** testing

## Next Task

$body
EOF
}

# -- Helper: create a plan with one pending task --
make_plan() {
  local dir=$1
  cat > "$dir/plan.md" << 'EOF'
- [x] 1. Previous task — **coder**
- [ ] 2. Next real task — **scout**
EOF
}

echo "=== Terminal checkpoint dispatch tests ==="

# ── Test A: Prose "Thread ready for review" should not extract "review" ──
DIR="$TMPDIR_BASE/a"
mkdir -p "$DIR"
make_checkpoint "$DIR" "Thread ready for review"
make_plan "$DIR"
DETECTED=$(detect_agent_from_checkpoint "$DIR/checkpoint.md" "$DIR/plan.md")
if [ -z "$DETECTED" ] || [ "$DETECTED" = "scout" ]; then
  pass "A: 'Thread ready for review' → empty or plan fallback ('$DETECTED')"
else
  fail "A: 'Thread ready for review' → got '$DETECTED', expected empty or 'scout'"
fi

# ── Test B: Prose "All done" should not extract "done" ──
DIR="$TMPDIR_BASE/b"
mkdir -p "$DIR"
make_checkpoint "$DIR" "All done"
make_plan "$DIR"
DETECTED=$(detect_agent_from_checkpoint "$DIR/checkpoint.md" "$DIR/plan.md")
if [ -z "$DETECTED" ] || [ "$DETECTED" = "scout" ]; then
  pass "B: 'All done' → empty or plan fallback ('$DETECTED')"
else
  fail "B: 'All done' → got '$DETECTED', expected empty or 'scout'"
fi

# ── Test C: Prose "Complete — awaiting feedback" should not extract "feedback" ──
DIR="$TMPDIR_BASE/c"
mkdir -p "$DIR"
make_checkpoint "$DIR" "Complete — awaiting feedback"
make_plan "$DIR"
DETECTED=$(detect_agent_from_checkpoint "$DIR/checkpoint.md" "$DIR/plan.md")
if [ -z "$DETECTED" ] || [ "$DETECTED" = "scout" ]; then
  pass "C: 'Complete — awaiting feedback' → empty or plan fallback ('$DETECTED')"
else
  fail "C: 'Complete — awaiting feedback' → got '$DETECTED', expected empty or 'scout'"
fi

# ── Test D: Prose "Finished, pending human review" ──
DIR="$TMPDIR_BASE/d"
mkdir -p "$DIR"
make_checkpoint "$DIR" "Finished, pending human review"
make_plan "$DIR"
DETECTED=$(detect_agent_from_checkpoint "$DIR/checkpoint.md" "$DIR/plan.md")
if [ -z "$DETECTED" ] || [ "$DETECTED" = "scout" ]; then
  pass "D: 'Finished, pending human review' → empty or plan fallback ('$DETECTED')"
else
  fail "D: 'Finished, pending human review' → got '$DETECTED', expected empty or 'scout'"
fi

# ── Test E: Canonical "<all tasks complete>" still works ──
DIR="$TMPDIR_BASE/e"
mkdir -p "$DIR"
make_checkpoint "$DIR" "<all tasks complete>"
make_plan "$DIR"
DETECTED=$(detect_agent_from_checkpoint "$DIR/checkpoint.md" "$DIR/plan.md")
if [ "$DETECTED" = "scout" ]; then
  pass "E: '<all tasks complete>' → plan fallback 'scout'"
else
  fail "E: '<all tasks complete>' → got '$DETECTED', expected 'scout'"
fi

# ── Test F: Legitimate task line still extracts correctly ──
DIR="$TMPDIR_BASE/f"
mkdir -p "$DIR"
make_checkpoint "$DIR" "3. Build the search index — **coder**"
DETECTED=$(detect_agent_from_checkpoint "$DIR/checkpoint.md")
if [ "$DETECTED" = "coder" ]; then
  pass "F: Legitimate task '3. Build the search index — **coder**' → 'coder'"
else
  fail "F: Legitimate task line → got '$DETECTED', expected 'coder'"
fi

# ── Test G: TDD annotation in parens must not leak into agent name ──
DIR="$TMPDIR_BASE/g"
mkdir -p "$DIR"
make_checkpoint "$DIR" "- [ ] 2. Add feature (red/green TDD, depends: 1) — **coder**"
DETECTED=$(detect_agent_from_checkpoint "$DIR/checkpoint.md")
if [ "$DETECTED" = "coder" ]; then
  pass "G: TDD annotation in parens → 'coder' (not 'TDD')"
else
  fail "G: TDD annotation in parens → got '$DETECTED', expected 'coder'"
fi

# ── Test H: TDD annotation NOT in parens is rejected by agent-file validation ──
DIR="$TMPDIR_BASE/h"
mkdir -p "$DIR"
make_checkpoint "$DIR" "- [ ] 2. Add feature — **coder** — red/green TDD"
make_plan "$DIR"
DETECTED=$(detect_agent_from_checkpoint "$DIR/checkpoint.md" "$DIR/plan.md")
if [ -z "$DETECTED" ] || [ "$DETECTED" = "scout" ]; then
  pass "H: bare TDD annotation → rejected, falls back to plan ('$DETECTED')"
else
  fail "H: bare TDD annotation → got '$DETECTED', expected empty or plan fallback"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
