#!/usr/bin/env bash
# RED test: multi-task completion in a single iteration goes undetected.
#
# Bug: ralph-loop.sh has no post-iteration validator. An agent can check
# off 2+ tasks in one iteration and the loop never notices.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$SCRIPT_DIR/lib/post-run.sh"

TMPDIR_BASE=$(mktemp -d)
trap 'rm -rf "$TMPDIR_BASE"' EXIT

PASS=0
FAIL=0

pass() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

# -- Helper: create a plan file --
make_plan() {
  local file=$1
  shift
  {
    echo "# Implementation Plan"
    echo ""
    echo "## Tasks"
    echo ""
    local num=1
    for spec in "$@"; do
      local state="${spec:0:1}"
      local desc="${spec:2}"
      echo "- [${state}] ${num}. ${desc}"
      num=$((num + 1))
    done
  } > "$file"
}

echo "=== One-task-per-iteration enforcement tests ==="

# ── Test A: 2 tasks newly completed → violation ──
DIR="$TMPDIR_BASE/a"
mkdir -p "$DIR"
make_plan "$DIR/before.md" \
  "x Previous task — **coder**" \
  "  Second task — **scout**" \
  "  Third task — **critic**"
make_plan "$DIR/after.md" \
  "x Previous task — **coder**" \
  "x Second task — **scout**" \
  "x Third task — **critic**"

if type validate_single_task_completion &>/dev/null; then
  if ! validate_single_task_completion "$DIR/before.md" "$DIR/after.md"; then
    pass "A: 2 new tasks completed → violation detected"
  else
    fail "A: 2 new tasks completed → no violation detected (should reject)"
  fi
else
  fail "A: validate_single_task_completion function not found"
fi

# ── Test B: 1 task newly completed → allowed ──
DIR="$TMPDIR_BASE/b"
mkdir -p "$DIR"
make_plan "$DIR/before.md" \
  "x Previous task — **coder**" \
  "  Second task — **scout**" \
  "  Third task — **critic**"
make_plan "$DIR/after.md" \
  "x Previous task — **coder**" \
  "x Second task — **scout**" \
  "  Third task — **critic**"

if type validate_single_task_completion &>/dev/null; then
  if validate_single_task_completion "$DIR/before.md" "$DIR/after.md"; then
    pass "B: 1 new task completed → allowed"
  else
    fail "B: 1 new task completed → incorrectly rejected"
  fi
else
  fail "B: validate_single_task_completion function not found"
fi

# ── Test C: 0 tasks newly completed → allowed ──
DIR="$TMPDIR_BASE/c"
mkdir -p "$DIR"
make_plan "$DIR/before.md" \
  "x Previous task — **coder**" \
  "  Second task — **scout**"
make_plan "$DIR/after.md" \
  "x Previous task — **coder**" \
  "  Second task — **scout**"

if type validate_single_task_completion &>/dev/null; then
  if validate_single_task_completion "$DIR/before.md" "$DIR/after.md"; then
    pass "C: 0 new tasks → allowed"
  else
    fail "C: 0 new tasks → incorrectly rejected"
  fi
else
  fail "C: validate_single_task_completion function not found"
fi

# ── Test D: 3 tasks newly completed (from zero) → violation ──
DIR="$TMPDIR_BASE/d"
mkdir -p "$DIR"
make_plan "$DIR/before.md" \
  "  First task — **coder**" \
  "  Second task — **scout**" \
  "  Third task — **critic**"
make_plan "$DIR/after.md" \
  "x First task — **coder**" \
  "x Second task — **scout**" \
  "x Third task — **critic**"

if type validate_single_task_completion &>/dev/null; then
  if ! validate_single_task_completion "$DIR/before.md" "$DIR/after.md"; then
    pass "D: 3 new tasks completed → violation detected"
  else
    fail "D: 3 new tasks completed → no violation detected (should reject)"
  fi
else
  fail "D: validate_single_task_completion function not found"
fi

# ── Test E: task unchecked (regression) → allowed (not this validator's job) ──
DIR="$TMPDIR_BASE/e"
mkdir -p "$DIR"
make_plan "$DIR/before.md" \
  "x First task — **coder**" \
  "x Second task — **scout**"
make_plan "$DIR/after.md" \
  "x First task — **coder**" \
  "  Second task — **scout**"

if type validate_single_task_completion &>/dev/null; then
  if validate_single_task_completion "$DIR/before.md" "$DIR/after.md"; then
    pass "E: task unchecked (negative diff) → allowed"
  else
    fail "E: task unchecked → incorrectly rejected"
  fi
else
  fail "E: validate_single_task_completion function not found"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
