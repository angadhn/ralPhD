#!/usr/bin/env bash
# RED test: validate_plan_tdd_structure rejects plans where coder TDD tasks
# are missing required RED:/GREEN:/VERIFY:/Commits: sub-fields.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$SCRIPT_DIR/lib/post-run.sh"

TMPDIR_BASE=$(mktemp -d)
trap 'rm -rf "$TMPDIR_BASE"' EXIT

PASS=0
FAIL=0

pass() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

echo "=== Plan TDD structure validation tests ==="

# ── Test A: coder TDD task missing RED: line → reject ──
DIR="$TMPDIR_BASE/a"
mkdir -p "$DIR"
cat > "$DIR/plan.md" <<'EOF'
# Implementation Plan

## Tasks

- [ ] 1. Add feature (red/green TDD) — **coder**
  GREEN: lib/foo.sh
  VERIFY: bash tests/test_foo.sh
  Commits: test(red): x and fix(green): y
EOF

if type validate_plan_tdd_structure &>/dev/null; then
  if ! validate_plan_tdd_structure "$DIR/plan.md"; then
    pass "A: missing RED: → rejected"
  else
    fail "A: missing RED: → should have been rejected"
  fi
else
  fail "A: validate_plan_tdd_structure function not found"
fi

# ── Test B: coder TDD task missing GREEN: line → reject ──
DIR="$TMPDIR_BASE/b"
mkdir -p "$DIR"
cat > "$DIR/plan.md" <<'EOF'
# Implementation Plan

## Tasks

- [ ] 1. Add feature (red/green TDD) — **coder**
  RED: tests/test_foo.sh test_a
  VERIFY: bash tests/test_foo.sh
  Commits: test(red): x and fix(green): y
EOF

if type validate_plan_tdd_structure &>/dev/null; then
  if ! validate_plan_tdd_structure "$DIR/plan.md"; then
    pass "B: missing GREEN: → rejected"
  else
    fail "B: missing GREEN: → should have been rejected"
  fi
else
  fail "B: validate_plan_tdd_structure function not found"
fi

# ── Test C: complete coder TDD task (all 4 fields) → accept ──
DIR="$TMPDIR_BASE/c"
mkdir -p "$DIR"
cat > "$DIR/plan.md" <<'EOF'
# Implementation Plan

## Tasks

- [ ] 1. Add feature (red/green TDD) — **coder**
  RED: tests/test_foo.sh
  GREEN: lib/foo.sh
  VERIFY: bash tests/test_foo.sh
  Commits: test(red): x and fix(green): y
EOF

if type validate_plan_tdd_structure &>/dev/null; then
  if validate_plan_tdd_structure "$DIR/plan.md"; then
    pass "C: all fields present → accepted"
  else
    fail "C: all fields present → incorrectly rejected"
  fi
else
  fail "C: validate_plan_tdd_structure function not found"
fi

# ── Test D: non-coder task (critic, no TDD annotation) → accept ──
DIR="$TMPDIR_BASE/d"
mkdir -p "$DIR"
cat > "$DIR/plan.md" <<'EOF'
# Implementation Plan

## Tasks

- [ ] 1. Review code quality — **critic**
EOF

if type validate_plan_tdd_structure &>/dev/null; then
  if validate_plan_tdd_structure "$DIR/plan.md"; then
    pass "D: non-coder task → accepted"
  else
    fail "D: non-coder task → incorrectly rejected"
  fi
else
  fail "D: validate_plan_tdd_structure function not found"
fi

# ── Test E: coder task WITHOUT "red/green TDD" annotation → accept ──
DIR="$TMPDIR_BASE/e"
mkdir -p "$DIR"
cat > "$DIR/plan.md" <<'EOF'
# Implementation Plan

## Tasks

- [ ] 1. Update prompt text — **coder**
EOF

if type validate_plan_tdd_structure &>/dev/null; then
  if validate_plan_tdd_structure "$DIR/plan.md"; then
    pass "E: coder non-TDD task → accepted"
  else
    fail "E: coder non-TDD task → incorrectly rejected"
  fi
else
  fail "E: validate_plan_tdd_structure function not found"
fi

# ── Test F: RED: line with placeholder ellipsis → reject ──
DIR="$TMPDIR_BASE/f"
mkdir -p "$DIR"
cat > "$DIR/plan.md" <<'EOF'
# Implementation Plan

## Tasks

- [ ] 1. Fix bug (red/green TDD) — **coder**
  RED: ...
  GREEN: lib/foo.sh — patch the parser
  VERIFY: bash tests/test_foo.sh
  Commits: test(red): x and fix(green): y
EOF

if type validate_plan_tdd_structure &>/dev/null; then
  if ! validate_plan_tdd_structure "$DIR/plan.md"; then
    pass "F: RED: with placeholder '...' → rejected"
  else
    fail "F: RED: with placeholder '...' → should have been rejected"
  fi
else
  fail "F: validate_plan_tdd_structure function not found"
fi

# ── Test G: GREEN: line with TBD placeholder → reject ──
DIR="$TMPDIR_BASE/g"
mkdir -p "$DIR"
cat > "$DIR/plan.md" <<'EOF'
# Implementation Plan

## Tasks

- [ ] 1. Fix bug (red/green TDD) — **coder**
  RED: tests/test_foo.sh test_regression
  GREEN: TBD
  VERIFY: bash tests/test_foo.sh
  Commits: test(red): x and fix(green): y
EOF

if type validate_plan_tdd_structure &>/dev/null; then
  if ! validate_plan_tdd_structure "$DIR/plan.md"; then
    pass "G: GREEN: with placeholder 'TBD' → rejected"
  else
    fail "G: GREEN: with placeholder 'TBD' → should have been rejected"
  fi
else
  fail "G: validate_plan_tdd_structure function not found"
fi

# ── Test H: RED: line with "write a test showing" placeholder → reject ──
DIR="$TMPDIR_BASE/h"
mkdir -p "$DIR"
cat > "$DIR/plan.md" <<'EOF'
# Implementation Plan

## Tasks

- [ ] 1. Fix bug (red/green TDD) — **coder**
  RED: write a test showing the parser crashes on empty input
  GREEN: lib/parser.sh — handle empty input
  VERIFY: bash tests/test_parser.sh
  Commits: test(red): x and fix(green): y
EOF

if type validate_plan_tdd_structure &>/dev/null; then
  if ! validate_plan_tdd_structure "$DIR/plan.md"; then
    pass "H: RED: with 'write a test showing' placeholder → rejected"
  else
    fail "H: RED: with 'write a test showing' placeholder → should have been rejected"
  fi
else
  fail "H: validate_plan_tdd_structure function not found"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
