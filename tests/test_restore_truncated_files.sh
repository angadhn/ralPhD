#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$SCRIPT_DIR/lib/post-run.sh"

TMPDIR_BASE=$(mktemp -d)
trap 'rm -rf "$TMPDIR_BASE"' EXIT

PASS=0
FAIL=0

pass() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

make_repo() {
  local dir=$1
  mkdir -p "$dir"
  git init -q "$dir"
  git -C "$dir" config user.name "Test User"
  git -C "$dir" config user.email "test@example.com"
}

echo "=== restore_truncated_files tests ==="

# ── Test A: HUMAN_REVIEW_NEEDED.md deletion is preserved ──
DIR="$TMPDIR_BASE/a"
make_repo "$DIR"
cat > "$DIR/HUMAN_REVIEW_NEEDED.md" <<'EOF'
Blocking review content
EOF
git -C "$DIR" add HUMAN_REVIEW_NEEDED.md
git -C "$DIR" commit -q -m "seed review file"
rm "$DIR/HUMAN_REVIEW_NEEDED.md"
(
  cd "$DIR"
  restore_truncated_files
)
if [ ! -f "$DIR/HUMAN_REVIEW_NEEDED.md" ]; then
  pass "A: HUMAN_REVIEW_NEEDED.md deletion is not restored"
else
  fail "A: HUMAN_REVIEW_NEEDED.md deletion was incorrectly restored"
fi

# ── Test B: ordinary truncated file is restored ──
DIR="$TMPDIR_BASE/b"
make_repo "$DIR"
cat > "$DIR/notes.md" <<'EOF'
Important content
EOF
git -C "$DIR" add notes.md
git -C "$DIR" commit -q -m "seed notes file"
: > "$DIR/notes.md"
(
  cd "$DIR"
  restore_truncated_files
)
if [ "$(cat "$DIR/notes.md")" = "Important content" ]; then
  pass "B: ordinary truncated file is restored from HEAD"
else
  fail "B: ordinary truncated file was not restored"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
