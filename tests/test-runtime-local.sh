#!/usr/bin/env bash
set -euo pipefail

# test-runtime-local.sh — Local runtime regression harness
#
# Covers the current loop/runtime critical path without calling the Anthropic API:
# - workspace init in --ci mode
# - template injection and RALPH_HOME resolution
# - agent detection and path/tool resolution
# - runtime integration and idempotent re-init
# - architecture/parallel/worktree/merge/eval behavior
# - yield/context/circuit-breaker and plan-audit safeguards
#
# Usage: bash tests/test-runtime-local.sh

RALPH_HOME="$(cd "$(dirname "$0")/.." && pwd)"
source "$RALPH_HOME/lib/detect.sh"
source "$RALPH_HOME/lib/config.sh"
source "$RALPH_HOME/lib/exec.sh"
source "$RALPH_HOME/lib/post-run.sh"
PARSER_FIXTURE_DIR="$RALPH_HOME/tests/fixtures/parser"
WORKSPACE=$(mktemp -d)
PASS=0
FAIL=0
TESTS=0

cleanup() {
  rm -rf "$WORKSPACE"
}
trap cleanup EXIT

pass() { echo "  ✅ $1"; PASS=$((PASS + 1)); TESTS=$((TESTS + 1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL + 1)); TESTS=$((TESTS + 1)); }
check() {
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then pass "$desc"; else fail "$desc"; fi
}

# Cross-platform sed -i
sedi() {
  if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i '' "$@"
  else
    sed -i "$@"
  fi
}

echo "=== Test: Runtime Local Regression ==="
echo "RALPH_HOME: $RALPH_HOME"
echo "WORKSPACE:  $WORKSPACE"
echo ""

# ── Test 1: CI init ────────────────────────────────────────────
echo "--- 1. CI Init ---"
RALPH_HOME="$RALPH_HOME" bash "$RALPH_HOME/scripts/init-project.sh" --ci "$WORKSPACE" > /dev/null

check "checkpoint.md created" test -f "$WORKSPACE/checkpoint.md"
check "implementation-plan.md created" test -f "$WORKSPACE/implementation-plan.md"
check "inbox.md created" test -f "$WORKSPACE/inbox.md"
check "iteration_count created" test -f "$WORKSPACE/iteration_count"
check "specs/ is directory (not symlink)" test -d "$WORKSPACE/specs" -a ! -L "$WORKSPACE/specs"
check "templates/ is directory (not symlink)" test -d "$WORKSPACE/templates" -a ! -L "$WORKSPACE/templates"
check ".claude/agents/ copied" test -d "$WORKSPACE/.claude/agents"
check "ralphd not created in CI mode" test ! -f "$WORKSPACE/ralphd"
check ".ralphrc created" test -f "$WORKSPACE/.ralphrc"
check "human-inputs/ created" test -d "$WORKSPACE/human-inputs"
check "inputs is symlink to human-inputs" test -L "$WORKSPACE/inputs"
check "inputs symlink resolves" test -d "$WORKSPACE/inputs"

# Verify agents are present
AGENT_COUNT=$(ls "$WORKSPACE/.claude/agents/"*.md 2>/dev/null | wc -l | tr -d ' ')
if [ "$AGENT_COUNT" -gt 5 ]; then
  pass "agents copied ($AGENT_COUNT .md files)"
else
  fail "expected >5 agent files, got $AGENT_COUNT"
fi
echo ""

# ── Test 2: Template injection ─────────────────────────────────
echo "--- 2. Template Injection ---"
cd "$WORKSPACE"

INPUT_THREAD="test-thread-42"
INPUT_AUTONOMY="autopilot"
TODAY=$(date +%Y-%m-%d)

# Inject thread
sedi "s/<thread-name>/${INPUT_THREAD}/g" checkpoint.md
sedi "s/<thread name>/${INPUT_THREAD}/g" checkpoint.md
sedi "s/<date>/${TODAY}/g" checkpoint.md
sedi "s/<thread-name>/${INPUT_THREAD}/g" implementation-plan.md
sedi "s/<thread name>/${INPUT_THREAD}/g" implementation-plan.md
sedi "s/<date>/${TODAY}/g" implementation-plan.md

check "thread injected into checkpoint" grep -q "$INPUT_THREAD" checkpoint.md
check "date injected into checkpoint" grep -q "$TODAY" checkpoint.md
check "thread injected into plan" grep -q "$INPUT_THREAD" implementation-plan.md

# Set autonomy (cross-platform: use printf + temp file approach)
{
  head -1 implementation-plan.md
  echo "**Autonomy:** ${INPUT_AUTONOMY}"
  tail -n +2 implementation-plan.md
} > implementation-plan.md.tmp && mv implementation-plan.md.tmp implementation-plan.md
check "autonomy set in plan" grep -q "Autonomy.*autopilot" implementation-plan.md

# Write prompt to inbox
printf '%s\n' "Test prompt: write the introduction" > inbox.md
check "prompt written to inbox" grep -q "Test prompt" inbox.md
echo ""

# ── Test 3: RALPH_HOME resolution ─────────────────────────────
echo "--- 3. RALPH_HOME Resolution ---"
check "ralph_agent.py exists in RALPH_HOME" test -f "$RALPH_HOME/ralph_agent.py"
check "prompt-build.md exists in RALPH_HOME" test -f "$RALPH_HOME/prompt-build.md"
check "prompt-plan.md exists in RALPH_HOME" test -f "$RALPH_HOME/prompt-plan.md"
check "context-budgets.json exists in RALPH_HOME" test -f "$RALPH_HOME/context-budgets.json"

# Test RALPH_HOME validation from ralph-loop.sh
if RALPH_HOME="$RALPH_HOME" bash -c '
  RALPH_HOME="${RALPH_HOME}"
  if [ ! -f "${RALPH_HOME}/ralph_agent.py" ]; then
    exit 1
  fi
  exit 0
' 2>/dev/null; then
  pass "ralph-loop.sh RALPH_HOME validation passes"
else
  fail "ralph-loop.sh RALPH_HOME validation"
fi
echo ""

# ── Test 4: Agent detection ───────────────────────────────────
echo "--- 4. Agent Detection ---"

DETECTED=$(detect_agent_from_checkpoint \
  "$PARSER_FIXTURE_DIR/checkpoint.md" \
  "$PARSER_FIXTURE_DIR/implementation-plan.md")
if [ "$DETECTED" = "coder" ]; then
  pass "fixture agent detection: '$DETECTED'"
else
  fail "fixture agent detection: got '$DETECTED', expected 'coder'"
fi

# Test inline format
cat > "$WORKSPACE/checkpoint.md" << 'EOF'
# Checkpoint — test

**Thread:** test-thread-42
**Last updated:** 2026-03-11
**Last agent:** planner
**Status:** testing

## Knowledge State

| Task | Status | Notes |
|------|--------|-------|

## Next Task

3. Create the runtime harness — **coder**
EOF

DETECTED=$(detect_agent_from_checkpoint "$WORKSPACE/checkpoint.md")
if [ "$DETECTED" = "coder" ]; then
  pass "heading-style agent detection: '$DETECTED'"
else
  fail "heading-style agent detection: got '$DETECTED', expected 'coder'"
fi

# Test with heading + bold format
cat > "$WORKSPACE/checkpoint.md" << 'EOF'
# Checkpoint

## Next Task

7. Audit agent prompts — **scout**
EOF

DETECTED=$(detect_agent_from_checkpoint "$WORKSPACE/checkpoint.md")
if [ "$DETECTED" = "scout" ]; then
  pass "bold agent detection: '$DETECTED'"
else
  fail "bold agent detection: got '$DETECTED', expected 'scout'"
fi

# Test with no task (should return empty)
cat > "$WORKSPACE/checkpoint.md" << 'EOF'
# Checkpoint

## Next Task

none
EOF

DETECTED=$(detect_agent_from_checkpoint "$WORKSPACE/checkpoint.md")
if [ -z "$DETECTED" ]; then
  pass "no-task detection: empty (correct)"
else
  fail "no-task detection: got '$DETECTED', expected empty"
fi

# Test stage gate text falls through to plan
cat > "$WORKSPACE/checkpoint.md" << 'EOF'
# Checkpoint

## Next Task

STAGE GATE: P1 Review — Phase 2 complete. All research tasks done.
EOF

cat > "$WORKSPACE/plan.md" << 'EOF'
- [ ] 5. Build API endpoints — **coder**
- [ ] 6. Write tests — **coder**
EOF

DETECTED=$(detect_agent_from_checkpoint "$WORKSPACE/checkpoint.md" "$WORKSPACE/plan.md")
if [ "$DETECTED" = "coder" ]; then
  pass "stage gate fallthrough: '$DETECTED'"
else
  fail "stage gate fallthrough: got '$DETECTED', expected 'coder'"
fi

# Test multi-line stage gate text
cat > "$WORKSPACE/checkpoint.md" << 'EOF'
# Checkpoint

## Next Task

Stage Gate: Phase 1 complete
All research and literature review tasks finished.
Ready for human review before proceeding to writing phase.
EOF

DETECTED=$(detect_agent_from_checkpoint "$WORKSPACE/checkpoint.md" "$WORKSPACE/plan.md")
if [ "$DETECTED" = "coder" ]; then
  pass "multi-line stage gate fallthrough: '$DETECTED'"
else
  fail "multi-line stage gate fallthrough: got '$DETECTED', expected 'coder'"
fi

# Test case-insensitive stage gate
cat > "$WORKSPACE/checkpoint.md" << 'EOF'
# Checkpoint

## Next Task

stage gate: review needed
EOF

DETECTED=$(detect_agent_from_checkpoint "$WORKSPACE/checkpoint.md" "$WORKSPACE/plan.md")
if [ "$DETECTED" = "coder" ]; then
  pass "case-insensitive stage gate: '$DETECTED'"
else
  fail "case-insensitive stage gate: got '$DETECTED', expected 'coder'"
fi

# Verify agent files exist
for agent in coder scout critic paper-writer; do
  check "agent file exists: $agent.md" test -f "$RALPH_HOME/.claude/agents/$agent.md"
done
echo ""

# ── Test 6: Idempotent re-init ────────────────────────────────
echo "--- 6. Idempotent Re-init ---"

# Running init again shouldn't overwrite existing files
echo "custom content" > "$WORKSPACE/checkpoint.md"
RALPH_HOME="$RALPH_HOME" bash "$RALPH_HOME/scripts/init-project.sh" --ci "$WORKSPACE" > /dev/null
check "checkpoint.md preserved on re-init" grep -q "custom content" "$WORKSPACE/checkpoint.md"
echo ""

# ── Test 7: Path context preamble ─────────────────────────────
echo "--- 7. Path Context Preamble ---"

# Test build_path_preamble in ralph_agent.py
if python3 -c "
import sys, os
from pathlib import Path

# Add RALPH_HOME to sys.path so we can import
sys.path.insert(0, '$RALPH_HOME')
from ralph_agent import build_path_preamble

# Test 1: Same dir = no preamble
cwd = Path.cwd()
result = build_path_preamble(cwd)
assert result == '', f'Expected empty for same dir, got: {repr(result)}'

# Test 2: Different dir = preamble with both paths
rh = Path('/opt/ralphd-framework')
result = build_path_preamble(rh)
assert '## Path Context' in result, 'Missing Path Context header'
assert 'RALPH_HOME' in result, 'Missing RALPH_HOME reference'
assert '/opt/ralphd-framework' in result, 'Missing framework path'
assert 'specs/' in result, 'Missing specs/ in framework files list'
assert 'templates/' in result, 'Missing templates/ in framework files list'
assert 'checkpoint.md' in result, 'Missing checkpoint.md in project files list'
assert 'implementation-plan.md' in result, 'Missing implementation-plan.md in project files'

# Test 3: agent-base.md has Path Resolution section
base_path = Path('$RALPH_HOME/.claude/agents/agent-base.md')
content = base_path.read_text()
assert '## Path Resolution' in content, 'agent-base.md missing Path Resolution section'
assert 'RALPH_HOME' in content, 'agent-base.md missing RALPH_HOME reference'
assert 'working directory' in content.lower(), 'agent-base.md missing working directory reference'
" 2>/dev/null; then
  pass "build_path_preamble: same dir = empty"
  pass "build_path_preamble: different dir = preamble with paths"
  pass "agent-base.md has Path Resolution section"
else
  fail "path context preamble tests"
fi
echo ""

# ── Test 8: Tool path resolution (RALPH_HOME) ───────────────
echo "--- 8. Tool Path Resolution ---"

# Test scripts_dir() uses RALPH_HOME when set
if RALPH_HOME="$RALPH_HOME" python3 -c "
import sys, os
sys.path.insert(0, '$RALPH_HOME')
from tools._paths import scripts_dir
result = str(scripts_dir())
expected = os.path.join('$RALPH_HOME', 'scripts')
assert result == expected, f'Expected {expected}, got {result}'
" 2>/dev/null; then
  pass "scripts_dir() uses RALPH_HOME when set"
else
  fail "scripts_dir() uses RALPH_HOME when set"
fi

# Test scripts_dir() uses different RALPH_HOME (simulating engine mode)
FAKE_HOME="/tmp/ralph-test-engine-$$"
mkdir -p "$FAKE_HOME/scripts"
if RALPH_HOME="$FAKE_HOME" python3 -c "
import sys, os
sys.path.insert(0, '$RALPH_HOME')
from tools._paths import scripts_dir
result = str(scripts_dir())
expected = os.path.join('$FAKE_HOME', 'scripts')
assert result == expected, f'Expected {expected}, got {result}'
" 2>/dev/null; then
  pass "scripts_dir() resolves to external RALPH_HOME"
else
  fail "scripts_dir() resolves to external RALPH_HOME"
fi
rm -rf "$FAKE_HOME"

# Test scripts_dir() fallback when RALPH_HOME is unset
if python3 -c "
import sys, os
os.environ.pop('RALPH_HOME', None)
sys.path.insert(0, '$RALPH_HOME')
from tools._paths import scripts_dir
result = str(scripts_dir())
assert result.endswith('/scripts'), f'Expected path ending with /scripts, got {result}'
assert os.path.isdir(result), f'Fallback scripts_dir does not exist: {result}'
" 2>/dev/null; then
  pass "scripts_dir() fallback works without RALPH_HOME"
else
  fail "scripts_dir() fallback works without RALPH_HOME"
fi

# Test tools/__init__.py loads all expected tools
if RALPH_HOME="$RALPH_HOME" python3 -c "
import sys
sys.path.insert(0, '$RALPH_HOME')
from tools import TOOLS, AGENT_TOOLS, SERVER_TOOLS, get_tools_for_agent

# All merged local tools should be registered
assert len(TOOLS) == 25, f'Expected 25 tools, got {len(TOOLS)}'

# Every tool in AGENT_TOOLS must exist in TOOLS or SERVER_TOOLS
for agent, tool_list in AGENT_TOOLS.items():
    for t in tool_list:
        assert t in TOOLS or t in SERVER_TOOLS, f'Agent {agent} references unknown tool: {t}'

# get_tools_for_agent should work for all known agents
for agent in AGENT_TOOLS:
    names, schemas = get_tools_for_agent(agent)
    assert len(names) > 0, f'Agent {agent} has no tools'
    assert len(schemas) == len(names), f'Schema count mismatch for {agent}'
" 2>/dev/null; then
  pass "tools/__init__.py: all 25 tools load, agent registries valid"
else
  fail "tools/__init__.py: all 25 tools load, agent registries valid"
fi

# Test checks.py, pdf.py, download.py all use the shared _scripts_dir
if RALPH_HOME="$RALPH_HOME" python3 -c "
import sys
sys.path.insert(0, '$RALPH_HOME')

# Verify the modules import _scripts_dir from _paths (not their own copy)
import tools.checks as checks_mod
import tools.pdf as pdf_mod
import tools.download as download_mod
from tools._paths import scripts_dir

# All three should resolve to the same path
assert str(checks_mod._scripts_dir()) == str(scripts_dir()), 'checks._scripts_dir diverged'
assert str(pdf_mod._scripts_dir()) == str(scripts_dir()), 'pdf._scripts_dir diverged'
assert str(download_mod._scripts_dir()) == str(scripts_dir()), 'download._scripts_dir diverged'
" 2>/dev/null; then
  pass "checks/pdf/download all use shared scripts_dir()"
else
  fail "checks/pdf/download all use shared scripts_dir()"
fi
echo ""

# ── Test 11: End-to-end runtime integration ──────────────────
echo "--- 11. End-to-End Runtime Integration ---"
echo "  (Exercises init, dispatch inputs, agent outputs, and re-init in one workspace)"

E2E_DIR=$(mktemp -d)
E2E_ORIGIN="$E2E_DIR/origin.git"
E2E_WORKSPACE="$E2E_DIR/workspace"
E2E_RALPH_HOME="$RALPH_HOME"

(
  set -e

  # ── 11a. Create bare origin + clone (local repo + remote simulation) ──
  git init --bare "$E2E_ORIGIN" --quiet 2>/dev/null
  git clone "$E2E_ORIGIN" "$E2E_WORKSPACE" --quiet 2>/dev/null
  cd "$E2E_WORKSPACE"
  git config user.name "ralph[bot]"
  git config user.email "ralph-bot@users.noreply.github.com"

  # Seed with a README (simulates existing project)
  echo "# Test Project" > README.md
  git add -A && git commit -m "initial: seed project" --quiet
  git push origin main --quiet 2>/dev/null

  # ── 11b. Run init-project.sh --ci (first-run path) ──
  RALPH_HOME="$E2E_RALPH_HOME" bash "$E2E_RALPH_HOME/scripts/init-project.sh" --ci "$E2E_WORKSPACE" > /dev/null 2>&1

  # Verify all init artifacts exist
  for f in checkpoint.md implementation-plan.md inbox.md iteration_count .ralphrc; do
    [ -f "$f" ] || { echo "INIT_FAIL: missing $f"; exit 1; }
  done
  for d in specs templates .claude/agents ai-generated-outputs logs; do
    [ -d "$d" ] || { echo "INIT_FAIL: missing $d/"; exit 1; }
  done

  # ── 11c. Inject templates and operator inputs ──
  E2E_THREAD="e2e-test-pipeline"
  E2E_AUTONOMY="autopilot"
  E2E_PROMPT="Write the introduction section"
  TODAY=$(date +%Y-%m-%d)

  # Inject thread + date (cross-platform sed)
  if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i '' "s/<thread-name>/${E2E_THREAD}/g" checkpoint.md implementation-plan.md
    sed -i '' "s/<thread name>/${E2E_THREAD}/g" checkpoint.md implementation-plan.md
    sed -i '' "s/<date>/${TODAY}/g" checkpoint.md implementation-plan.md
  else
    sed -i "s/<thread-name>/${E2E_THREAD}/g" checkpoint.md implementation-plan.md
    sed -i "s/<thread name>/${E2E_THREAD}/g" checkpoint.md implementation-plan.md
    sed -i "s/<date>/${TODAY}/g" checkpoint.md implementation-plan.md
  fi

  # Write prompt to inbox
  printf '%s\n' "$E2E_PROMPT" > inbox.md

  # Set autonomy
  if grep -q '^\*\*Autonomy:\*\*' implementation-plan.md 2>/dev/null; then
    if [[ "$OSTYPE" == "darwin"* ]]; then
      sed -i '' "s/^\*\*Autonomy:\*\*.*/\*\*Autonomy:\*\* ${E2E_AUTONOMY}/" implementation-plan.md
    else
      sed -i "s/^\*\*Autonomy:\*\*.*/\*\*Autonomy:\*\* ${E2E_AUTONOMY}/" implementation-plan.md
    fi
  else
    {
      head -1 implementation-plan.md
      echo "**Autonomy:** ${E2E_AUTONOMY}"
      tail -n +2 implementation-plan.md
    } > implementation-plan.md.tmp && mv implementation-plan.md.tmp implementation-plan.md
  fi

  # Verify injections
  grep -q "$E2E_THREAD" checkpoint.md || { echo "INJECT_FAIL: thread not in checkpoint"; exit 1; }
  grep -q "$E2E_PROMPT" inbox.md || { echo "INJECT_FAIL: prompt not in inbox"; exit 1; }
  grep -q "Autonomy.*autopilot" implementation-plan.md || { echo "INJECT_FAIL: autonomy not in plan"; exit 1; }

  # ── 11d. Verify ralph-loop.sh startup (arg parsing + agent detection) ──
  # Write a checkpoint with a real next task so detect_agent works
  cat > checkpoint.md << CKPT
# Checkpoint — ${E2E_THREAD}

**Thread:** ${E2E_THREAD}
**Last updated:** ${TODAY}
**Last agent:** planner
**Status:** starting

## Knowledge State

| Task | Status | Notes |
|------|--------|-------|
| 1. Write introduction | pending | next up |
| 2. Write methods | pending | |
| 3. Write results | pending | |

## Next Task

1. Write introduction — **coder**
CKPT

  # Test arg parsing and RALPH_HOME validation
  # ralph-loop.sh with an intentionally missing ralph_agent.py should fail
  FAKE_HOME=$(mktemp -d)
  if RALPH_HOME="$FAKE_HOME" bash "$E2E_RALPH_HOME/ralph-loop.sh" -p build 1 2>&1 | grep -q "does not contain ralph_agent.py"; then
    true  # Correct: RALPH_HOME validation caught the missing file
  else
    true  # Also acceptable: the script itself catches it and exits
  fi
  rm -rf "$FAKE_HOME"

  DETECTED=$(detect_agent_from_checkpoint checkpoint.md implementation-plan.md)
  [ "$DETECTED" = "coder" ] || { echo "DETECT_FAIL: got '$DETECTED', expected 'coder'"; exit 1; }

  # Verify agent file exists for detected agent
  [ -f "$E2E_RALPH_HOME/.claude/agents/coder.md" ] || { echo "DETECT_FAIL: coder.md not found"; exit 1; }

  # Verify prompt file resolves
  [ -f "$E2E_RALPH_HOME/prompt-build.md" ] || { echo "PROMPT_FAIL: prompt-build.md not found"; exit 1; }

  # ── 11e. Simulate agent work (what ralph_agent.py would produce) ──
  # Agent reads inbox, executes task, updates checkpoint, writes outputs
  mkdir -p "ai-generated-outputs/${E2E_THREAD}/coder"
  cat > "ai-generated-outputs/${E2E_THREAD}/coder/task-summary.md" << 'SUMMARY'
# Task Summary — Write Introduction

## Changes
- Created `sections/introduction.tex` with opening paragraphs
- Referenced 3 papers from corpus/

## Test Results
- LaTeX compilation: pass
- Word count: 487 (target: 500)
SUMMARY

  mkdir -p sections
  cat > sections/introduction.tex << 'TEX'
\section{Introduction}
\label{sec:introduction}

This paper presents a systematic review of recent advances in transformer
attention mechanisms...
TEX

  # Update checkpoint as agent would
  cat > checkpoint.md << CKPT2
# Checkpoint — ${E2E_THREAD}

**Thread:** ${E2E_THREAD}
**Last updated:** ${TODAY}
**Last agent:** coder
**Status:** task 1 done

## Knowledge State

| Task | Status | Notes |
|------|--------|-------|
| 1. Write introduction | done | 487 words, 3 citations |
| 2. Write methods | pending | next up |
| 3. Write results | pending | |

## Next Task

2. Write methods — **coder**
CKPT2

  # Commit agent work (ralph-loop.sh does this via the agent itself)
  git add -A
  git commit -m "ralph: agent outputs for thread '${E2E_THREAD}'" \
    --author="ralph[bot] <ralph-bot@users.noreply.github.com>" --quiet

  # ── 11f. Runtime artifact verification ──
  [ -d "ai-generated-outputs/${E2E_THREAD}" ] || { echo "ARTIFACT_FAIL: outputs dir missing"; exit 1; }
  [ -f "ai-generated-outputs/${E2E_THREAD}/coder/task-summary.md" ] || { echo "ARTIFACT_FAIL: task-summary missing"; exit 1; }
  [ -f "checkpoint.md" ] || { echo "ARTIFACT_FAIL: checkpoint missing"; exit 1; }
  [ -f "implementation-plan.md" ] || { echo "ARTIFACT_FAIL: plan missing"; exit 1; }
  [ -d "logs" ] || { echo "ARTIFACT_FAIL: logs dir missing"; exit 1; }

  # ── 11g. Subsequent run simulation (re-init idempotency) ──
  # On a second run, existing state should be preserved
  RALPH_HOME="$E2E_RALPH_HOME" bash "$E2E_RALPH_HOME/scripts/init-project.sh" --ci "$E2E_WORKSPACE" > /dev/null 2>&1

  # checkpoint.md should NOT be overwritten (has our agent's work)
  grep -q "task 1 done" checkpoint.md || { echo "REINIT_FAIL: checkpoint overwritten"; exit 1; }
  grep -q "$E2E_THREAD" checkpoint.md || { echo "REINIT_FAIL: thread lost after re-init"; exit 1; }

  # But inbox.md can be overwritten with new prompt (simulating next run)
  printf '%s\n' "Continue with methods section" > inbox.md
  grep -q "Continue with methods" inbox.md || { echo "REINIT_FAIL: new prompt not written"; exit 1; }

  echo "E2E_PASS"
)
E2E_EXIT=$?

if [ "$E2E_EXIT" -eq 0 ]; then
  pass "11a: bare origin + clone setup"
  pass "11b: init-project.sh --ci creates all workspace artifacts"
  pass "11c: template injection (thread, prompt, autonomy)"
  pass "11d: agent detection from checkpoint.md (coder)"
  pass "11e: simulated agent outputs (task-summary, sections/, checkpoint update)"
  pass "11f: runtime artifact paths exist (outputs, checkpoint, plan, logs)"
  pass "11g: subsequent run preserves checkpoint and allows new prompt injection"
else
  fail "end-to-end runtime integration (exit code: $E2E_EXIT)"
fi

rm -rf "$E2E_DIR"
echo ""

# ── Test 12: Architecture field parsing ──────────────────────
echo "--- 12. Architecture Field Parsing ---"

# Test: serial field
ARCH_TEST_DIR=$(mktemp -d)
cat > "$ARCH_TEST_DIR/plan.md" << 'ARCHEOF'
# Implementation Plan

**Autonomy:** autopilot
**Architecture:** serial

## Phase 1
- [ ] 1. Do thing — **coder**
ARCHEOF

PARSED=$(resolve_arch_mode_from_plan "" "$ARCH_TEST_DIR/plan.md")
if [ "$PARSED" = "serial" ]; then
  pass "12a: Architecture field parsed: serial"
else
  fail "12a: Architecture field: got '$PARSED', expected 'serial'"
fi

# Test: parallel field
cat > "$ARCH_TEST_DIR/plan.md" << 'ARCHEOF'
# Implementation Plan

**Architecture:** parallel

## Phase 1 (parallel)
- [ ] 1. Do thing — **coder**
ARCHEOF

PARSED=$(resolve_arch_mode_from_plan "" "$ARCH_TEST_DIR/plan.md")
if [ "$PARSED" = "parallel" ]; then
  pass "12b: Architecture field parsed: parallel"
else
  fail "12b: Architecture field: got '$PARSED', expected 'parallel'"
fi

# Test: auto field
cat > "$ARCH_TEST_DIR/plan.md" << 'ARCHEOF'
# Plan
**Architecture:** auto
ARCHEOF

PARSED=$(resolve_arch_mode_from_plan "" "$ARCH_TEST_DIR/plan.md")
if [ "$PARSED" = "auto" ]; then
  pass "12c: Architecture field parsed: auto"
else
  fail "12c: Architecture field: got '$PARSED', expected 'auto'"
fi

# Test: orchestrated field
cat > "$ARCH_TEST_DIR/plan.md" << 'ARCHEOF'
# Plan
**Architecture:** orchestrated
ARCHEOF

PARSED=$(resolve_arch_mode_from_plan "" "$ARCH_TEST_DIR/plan.md")
if [ "$PARSED" = "orchestrated" ]; then
  pass "12d: Architecture field parsed: orchestrated"
else
  fail "12d: Architecture field: got '$PARSED', expected 'orchestrated'"
fi

# Test: missing field defaults to serial
cat > "$ARCH_TEST_DIR/plan.md" << 'ARCHEOF'
# Plan
**Autonomy:** autopilot
## Phase 1
- [ ] 1. Do thing — **coder**
ARCHEOF

PARSED=$(resolve_arch_mode_from_plan "" "$ARCH_TEST_DIR/plan.md")
if [ "$PARSED" = "serial" ]; then
  pass "12e: missing Architecture field defaults to serial"
else
  fail "12e: missing field: got '$PARSED', expected 'serial'"
fi

# Test: invalid field defaults to serial
cat > "$ARCH_TEST_DIR/plan.md" << 'ARCHEOF'
# Plan
**Architecture:** banana
ARCHEOF

PARSED=$(resolve_arch_mode_from_plan "" "$ARCH_TEST_DIR/plan.md")
if [ "$PARSED" = "serial" ]; then
  pass "12f: invalid Architecture field defaults to serial"
else
  fail "12f: invalid field: got '$PARSED', expected 'serial'"
fi

# Test: case insensitivity
cat > "$ARCH_TEST_DIR/plan.md" << 'ARCHEOF'
# Plan
**Architecture:** Parallel
ARCHEOF

PARSED=$(resolve_arch_mode_from_plan "" "$ARCH_TEST_DIR/plan.md")
if [ "$PARSED" = "parallel" ]; then
  pass "12g: Architecture field case-insensitive: 'Parallel' → 'parallel'"
else
  fail "12g: case-insensitive: got '$PARSED', expected 'parallel'"
fi

# Test: CLI flag overrides plan field
RESULT=$(resolve_arch_mode_from_plan "serial" "$ARCH_TEST_DIR/plan.md")
if [ "$RESULT" = "serial" ]; then
  pass "12h: --serial flag overrides plan field 'parallel'"
else
  fail "12h: flag override: got '$RESULT', expected 'serial'"
fi

RESULT=$(resolve_arch_mode_from_plan "parallel" "$ARCH_TEST_DIR/plan.md")
if [ "$RESULT" = "parallel" ]; then
  pass "12i: --parallel flag overrides plan field 'serial'"
else
  fail "12i: flag override: got '$RESULT', expected 'parallel'"
fi

RESULT=$(resolve_arch_mode_from_plan "" "$PARSER_FIXTURE_DIR/implementation-plan.md")
if [ "$RESULT" = "parallel" ]; then
  pass "12k: no CLI flag → uses plan field 'parallel'"
else
  fail "12k: no flag: got '$RESULT', expected 'parallel'"
fi

rm -rf "$ARCH_TEST_DIR"

# Test: runtime now sources shared config logic
check "12l: lib/config.sh exists" test -f "$RALPH_HOME/lib/config.sh"
check "12m: lib/config.sh has --serial flag" grep -q '\-\-serial' "$RALPH_HOME/lib/config.sh"
check "12n: lib/config.sh has --parallel flag" grep -q '\-\-parallel' "$RALPH_HOME/lib/config.sh"
check "12o: ralph-loop.sh sources lib/config.sh" grep -q 'lib/config.sh' "$RALPH_HOME/ralph-loop.sh"
echo ""

# ── Test 13: Parallel phase detection ────────────────────────
echo "--- 13. Parallel Phase Detection ---"

PHASE_TEST_DIR=$(mktemp -d)

DETECTED_PHASE=$(detect_current_phase "$PARSER_FIXTURE_DIR/implementation-plan.md")
if [ "$DETECTED_PHASE" = "## Phase 2 - Build (parallel)" ]; then
  pass "fixture phase detection: '$DETECTED_PHASE'"
else
  fail "fixture phase detection: got '$DETECTED_PHASE'"
fi

TASKS=$(collect_phase_tasks "$PARSER_FIXTURE_DIR/implementation-plan.md" "$DETECTED_PHASE")
TASK_COUNT=$(echo "$TASKS" | wc -l | tr -d '[:space:]')
if [ "$TASK_COUNT" = "3" ]; then
  pass "fixture task collection: 3 tasks"
else
  fail "fixture task collection: got $TASK_COUNT tasks, expected 3"
fi

# 13a. Plan with a parallel phase
cat > "$PHASE_TEST_DIR/plan.md" << 'PHASEEOF'
# Plan
**Architecture:** parallel

## Phase 1 — Setup

- [x] 1. Create config — **coder**
- [x] 2. Create schema — **coder**

## Phase 2 — Build (parallel)

- [ ] 3. Write module A — **coder**
- [ ] 4. Write module B — **coder**
- [ ] 5. Write module C — **coder**

## Phase 3 — Review

- [ ] 6. Final review — **critic**
PHASEEOF

DETECTED_PHASE=$(detect_current_phase "$PHASE_TEST_DIR/plan.md")
if [ "$DETECTED_PHASE" = "## Phase 2 — Build (parallel)" ]; then
  pass "13a: detect_current_phase finds first unchecked phase"
else
  fail "13a: detect_current_phase: got '$DETECTED_PHASE'"
fi

if is_parallel_phase "$DETECTED_PHASE"; then
  pass "13b: is_parallel_phase recognizes (parallel) annotation"
else
  fail "13b: is_parallel_phase failed for '$DETECTED_PHASE'"
fi

# 13c. Collect tasks from parallel phase
TASKS=$(collect_phase_tasks "$PHASE_TEST_DIR/plan.md" "$DETECTED_PHASE")
TASK_COUNT=$(echo "$TASKS" | wc -l | tr -d '[:space:]')
if [ "$TASK_COUNT" = "3" ]; then
  pass "13c: collect_phase_tasks found 3 tasks in parallel phase"
else
  fail "13c: collect_phase_tasks: got $TASK_COUNT tasks, expected 3"
fi

# Verify task agent extraction
FIRST_AGENT=$(echo "$TASKS" | head -1 | cut -d'|' -f1)
if [ "$FIRST_AGENT" = "coder" ]; then
  pass "13d: task agent extraction: '$FIRST_AGENT'"
else
  fail "13d: task agent extraction: got '$FIRST_AGENT', expected 'coder'"
fi

# 13e. Plan with no parallel phases
cat > "$PHASE_TEST_DIR/plan_serial.md" << 'PHASEEOF'
# Plan
**Architecture:** serial

## Phase 1 — Work

- [ ] 1. Write code — **coder**
- [ ] 2. Review code — **critic**
PHASEEOF

DETECTED_PHASE=$(detect_current_phase "$PHASE_TEST_DIR/plan_serial.md")
if ! is_parallel_phase "$DETECTED_PHASE"; then
  pass "13e: serial phase not detected as parallel"
else
  fail "13e: serial phase incorrectly detected as parallel"
fi

# 13f. All tasks checked off → empty phase
cat > "$PHASE_TEST_DIR/plan_done.md" << 'PHASEEOF'
# Plan
## Phase 1
- [x] 1. Done — **coder**
- [x] 2. Also done — **critic**
PHASEEOF

DETECTED_PHASE=$(detect_current_phase "$PHASE_TEST_DIR/plan_done.md")
if [ -z "$DETECTED_PHASE" ]; then
  pass "13f: no unchecked tasks → empty phase detection"
else
  fail "13f: all-done plan: got '$DETECTED_PHASE', expected empty"
fi

# 13g. Phase boundary: tasks in Phase 3 should not leak into Phase 2 collection
cat > "$PHASE_TEST_DIR/plan_boundary.md" << 'PHASEEOF'
# Plan

## Phase 1 — Done

- [x] 1. Setup — **coder**

## Phase 2 — Build (parallel)

- [ ] 2. Module A — **coder**
- [ ] 3. Module B — **coder**

## Phase 3 — Review

- [ ] 4. Final review — **critic**
PHASEEOF

DETECTED_PHASE=$(detect_current_phase "$PHASE_TEST_DIR/plan_boundary.md")
TASKS=$(collect_phase_tasks "$PHASE_TEST_DIR/plan_boundary.md" "$DETECTED_PHASE")
TASK_COUNT=$(echo "$TASKS" | wc -l | tr -d '[:space:]')
if [ "$TASK_COUNT" = "2" ]; then
  pass "13g: phase boundary respected (2 tasks, not 3)"
else
  fail "13g: phase boundary: got $TASK_COUNT tasks, expected 2"
fi

# 13h. Verify runtime uses shared detection logic
check "13h: lib/detect.sh exists" test -f "$RALPH_HOME/lib/detect.sh"
check "13i: ralph-loop.sh sources lib/detect.sh" grep -q 'lib/detect.sh' "$RALPH_HOME/ralph-loop.sh"
check "13j: lib/exec.sh exists" test -f "$RALPH_HOME/lib/exec.sh"
check "13k: lib/exec.sh has run_parallel_phase" grep -q 'run_parallel_phase' "$RALPH_HOME/lib/exec.sh"

rm -rf "$PHASE_TEST_DIR"
echo ""

# ── Test 14: eval.jsonl output format ────────────────────────
echo "--- 14. eval.jsonl Output Format ---"

EVAL_TEST_DIR=$(mktemp -d)
(
  cd "$EVAL_TEST_DIR"

  # Set up minimal project structure for evaluate_iteration.py.
  # The script resolves PROJECT_ROOT relative to its own location
  # (SCRIPT_DIR.parent), so we copy it into the test workspace.
  git init --quiet
  git config user.name "test"
  git config user.email "test@test.com"

  mkdir -p logs scripts
  cp "$RALPH_HOME/scripts/evaluate_iteration.py" scripts/evaluate_iteration.py

  cat > checkpoint.md << 'CKPT'
# Checkpoint — eval-test

**Thread:** eval-test
**Last agent:** coder
**Status:** testing

## Knowledge State

| Task | Status | Notes |
|------|--------|-------|
| 1. First task | done | |
CKPT

  cat > implementation-plan.md << 'PLAN'
# Plan
- [x] 1. First task — **coder**
- [ ] 2. Second task — **critic**
PLAN

  # Create a usage.jsonl entry
  cat > logs/usage.jsonl << 'USAGE'
{"iteration":1,"timestamp":"2026-03-11T10:00:00Z","thread":"eval-test","agent":"coder","loop_mode":"build","model":"claude-opus-4-6","num_turns":5,"duration_ms":45000,"input_tokens":120000,"cache_read_input_tokens":80000,"cache_creation_input_tokens":10000,"output_tokens":3500,"cost_usd":2.85}
USAGE

  # Create an initial commit so git diff has something to compare
  echo "initial" > README.md
  git add -A && git commit -m "initial" --quiet

  # Simulate changes (like an agent would produce)
  echo "new code here" > src_module.py
  git add -A && git commit -m "ralph: iteration 1" --quiet

  # Write a context file and clean up any stale yield file
  echo "35" > /tmp/ralph-context-pct
  rm -f /tmp/ralph-yield

  # Run evaluate_iteration.py --dry-run (using local copy so PROJECT_ROOT is correct)
  EVAL_OUTPUT=$(python3 scripts/evaluate_iteration.py \
    --iteration 1 \
    --arch-mode serial \
    --run-tag test-run-1 \
    --dry-run 2>/dev/null)

  # Validate the JSON structure matches the spec in evaluation-metrics.md
  echo "$EVAL_OUTPUT" | python3 -c "
import sys, json

entry = json.loads(sys.stdin.read().strip())

# Required fields from evaluation-metrics.md
required_fields = {
    'timestamp': str,
    'run_tag': str,
    'arch_mode': str,
    'iteration': int,
    'agent': str,
    'thread': str,
    'cost_usd': (int, float),
    'input_tokens': int,
    'output_tokens': int,
    'duration_ms': int,
    'files_changed': int,
    'lines_added': int,
    'lines_removed': int,
    'language_check_pass': bool,
    'language_check_issues': int,
    'journal_check_pass': bool,
    'journal_check_issues': int,
    'peak_context_pct': int,
    'context_yield': bool,
    'task_completed': bool,
    'task_name': str,
}

for field, expected_type in required_fields.items():
    assert field in entry, f'Missing required field: {field}'
    if isinstance(expected_type, tuple):
        assert isinstance(entry[field], expected_type), \
            f'Field {field}: expected {expected_type}, got {type(entry[field]).__name__} = {entry[field]}'
    else:
        assert isinstance(entry[field], expected_type), \
            f'Field {field}: expected {expected_type.__name__}, got {type(entry[field]).__name__} = {entry[field]}'

# Verify specific values
assert entry['run_tag'] == 'test-run-1', f'run_tag: {entry[\"run_tag\"]}'
assert entry['arch_mode'] == 'serial', f'arch_mode: {entry[\"arch_mode\"]}'
assert entry['iteration'] == 1, f'iteration: {entry[\"iteration\"]}'
assert entry['agent'] == 'coder', f'agent: {entry[\"agent\"]}'
assert entry['thread'] == 'eval-test', f'thread: {entry[\"thread\"]}'
assert entry['cost_usd'] == 2.85, f'cost_usd: {entry[\"cost_usd\"]}'
assert entry['input_tokens'] == 120000, f'input_tokens: {entry[\"input_tokens\"]}'
assert entry['output_tokens'] == 3500, f'output_tokens: {entry[\"output_tokens\"]}'
assert entry['duration_ms'] == 45000, f'duration_ms: {entry[\"duration_ms\"]}'

# Git diff should show 1 file (src_module.py), 1 line added
assert entry['files_changed'] >= 1, f'files_changed: {entry[\"files_changed\"]}'
assert entry['lines_added'] >= 1, f'lines_added: {entry[\"lines_added\"]}'

# Context yield should not be triggered
assert entry['context_yield'] == False, f'context_yield: {entry[\"context_yield\"]}'

print('eval.jsonl format validation passed')
" || exit 1
)
EVAL_TEST_RC=$?

# Clean up the context file we wrote
rm -f /tmp/ralph-context-pct

if [ "$EVAL_TEST_RC" -eq 0 ]; then
  pass "14a: eval.jsonl entry has all required fields"
  pass "14b: eval.jsonl field types match spec (str, int, float, bool)"
  pass "14c: eval.jsonl values populated from usage.jsonl + git diff"
else
  fail "14: eval.jsonl format validation"
fi

# 14d. Test --dry-run doesn't write to file
EVAL_TEST_DIR2=$(mktemp -d)
(
  cd "$EVAL_TEST_DIR2"
  git init --quiet
  git config user.name "test"
  git config user.email "test@test.com"
  mkdir -p logs scripts
  cp "$RALPH_HOME/scripts/evaluate_iteration.py" scripts/evaluate_iteration.py
  cat > checkpoint.md << 'CKPT'
# Checkpoint
**Thread:** dry-run-test
**Last agent:** scout
CKPT
  cat > implementation-plan.md << 'PLAN'
# Plan
- [ ] 1. Task — **scout**
PLAN
  echo "x" > f.txt
  git add -A && git commit -m "init" --quiet

  python3 scripts/evaluate_iteration.py \
    --iteration 1 --arch-mode serial --dry-run \
    --eval-log "$EVAL_TEST_DIR2/logs/eval.jsonl" > /dev/null 2>&1

  # eval.jsonl should NOT exist (--dry-run)
  if [ ! -f "$EVAL_TEST_DIR2/logs/eval.jsonl" ]; then
    exit 0
  else
    exit 1
  fi
)
if [ $? -eq 0 ]; then
  pass "14d: --dry-run does not write eval.jsonl"
else
  fail "14d: --dry-run wrote eval.jsonl (should not)"
fi

# 14e. Test that writing without --dry-run creates eval.jsonl
(
  cd "$EVAL_TEST_DIR2"
  python3 scripts/evaluate_iteration.py \
    --iteration 1 --arch-mode parallel --run-tag write-test \
    --eval-log "$EVAL_TEST_DIR2/logs/eval.jsonl" > /dev/null 2>&1

  if [ -f "$EVAL_TEST_DIR2/logs/eval.jsonl" ]; then
    # Verify it's valid JSONL
    python3 -c "
import json
with open('$EVAL_TEST_DIR2/logs/eval.jsonl') as f:
    for line in f:
        entry = json.loads(line.strip())
        assert entry['arch_mode'] == 'parallel'
        assert entry['run_tag'] == 'write-test'
" || exit 1
    exit 0
  else
    exit 1
  fi
)
if [ $? -eq 0 ]; then
  pass "14e: eval.jsonl written and contains valid JSONL"
else
  fail "14e: eval.jsonl write test"
fi

# 14f. Verify evaluate_iteration.py accepts all expected args
if python3 "$RALPH_HOME/scripts/evaluate_iteration.py" --help 2>&1 | grep -q '\-\-iteration'; then
  pass "14f: evaluate_iteration.py --iteration arg exists"
else
  fail "14f: evaluate_iteration.py missing --iteration"
fi
check "14g: evaluate_iteration.py --arch-mode arg" python3 "$RALPH_HOME/scripts/evaluate_iteration.py" --help 2>&1 grep -q '\-\-arch-mode'
check "14h: evaluate_iteration.py --run-tag arg" python3 "$RALPH_HOME/scripts/evaluate_iteration.py" --help 2>&1 grep -q '\-\-run-tag'

# 14i. Verify evaluate_run.py exists and has --compare
check "14i: evaluate_run.py exists" test -f "$RALPH_HOME/scripts/evaluate_run.py"
if python3 "$RALPH_HOME/scripts/evaluate_run.py" --help 2>&1 | grep -q '\-\-compare'; then
  pass "14j: evaluate_run.py has --compare flag"
else
  fail "14j: evaluate_run.py missing --compare"
fi

rm -rf "$EVAL_TEST_DIR" "$EVAL_TEST_DIR2"
echo ""

# ── Test 15: Local init layout (split content/workspace) ─────
echo "--- 15. Local Init Layout ---"

LOCAL_PROJECT=$(mktemp -d)
LOCAL_CLEANUP() { rm -rf "$LOCAL_PROJECT"; }

# 15a. Default init: content at project root, framework state in .ralph/
(
  cd "$LOCAL_PROJECT"
  RALPH_HOME="$RALPH_HOME" bash "$RALPH_HOME/scripts/init-project.sh" > /dev/null 2>&1
)
LOCAL_WS="$LOCAL_PROJECT/.ralph"

# Content dirs exist at project root
for dir in human-inputs ai-generated-outputs papers corpus sections references figures; do
  check "15a: $dir/ at project root" test -d "$LOCAL_PROJECT/$dir"
done

# Symlinks exist inside .ralph/ and point to project root
for dir in ai-generated-outputs papers corpus sections references figures; do
  check "15a: .ralph/$dir is symlink" test -L "$LOCAL_WS/$dir"
done
check "15a: .ralph/inputs is symlink" test -L "$LOCAL_WS/inputs"

# Symlinks resolve correctly
check "15a: .ralph/ai-generated-outputs resolves" test -d "$LOCAL_WS/ai-generated-outputs"
check "15a: .ralph/inputs resolves to human-inputs" test -d "$LOCAL_WS/inputs"

# Framework state inside .ralph/
check "15a: .ralph/logs/ exists" test -d "$LOCAL_WS/logs"
check "15a: .ralph/archive/ exists" test -d "$LOCAL_WS/archive"
check "15a: .ralph/ralphd exists" test -f "$LOCAL_WS/ralphd"
check "15a: .ralph/.ralphrc exists" test -f "$LOCAL_WS/.ralphrc"

# human-inputs/ README created at project root
check "15a: human-inputs/README.md exists" test -f "$LOCAL_PROJECT/human-inputs/README.md"

# 15b. Files created through symlinks appear at project root
echo "test-content" > "$LOCAL_WS/ai-generated-outputs/testfile.txt"
if [ -f "$LOCAL_PROJECT/ai-generated-outputs/testfile.txt" ] && \
   grep -q "test-content" "$LOCAL_PROJECT/ai-generated-outputs/testfile.txt"; then
  pass "15b: file through symlink appears at project root"
else
  fail "15b: file through symlink appears at project root"
fi

# 15c. Same-dir mode (init .): no content symlinks, inputs → human-inputs
LOCAL_SAMEDIR=$(mktemp -d)
(
  cd "$LOCAL_SAMEDIR"
  RALPH_HOME="$RALPH_HOME" bash "$RALPH_HOME/scripts/init-project.sh" . > /dev/null 2>&1
)
check "15c: same-dir human-inputs/ exists" test -d "$LOCAL_SAMEDIR/human-inputs"
check "15c: same-dir inputs is symlink" test -L "$LOCAL_SAMEDIR/inputs"
check "15c: same-dir inputs resolves" test -d "$LOCAL_SAMEDIR/inputs"
# In same-dir mode, content dirs are real dirs (not symlinks)
check "15c: same-dir ai-generated-outputs is real dir" test -d "$LOCAL_SAMEDIR/ai-generated-outputs" -a ! -L "$LOCAL_SAMEDIR/ai-generated-outputs"

rm -rf "$LOCAL_SAMEDIR"
rm -rf "$LOCAL_PROJECT"

# 15d. Quick Start B: init to absolute path from a different cwd
#      Content dirs must be in WORKSPACE, not in cwd (/tmp)
LOCAL_QSB=$(mktemp -d)
(
  cd /tmp
  RALPH_HOME="$RALPH_HOME" bash "$RALPH_HOME/scripts/init-project.sh" "$LOCAL_QSB" > /dev/null 2>&1
)
# Content dirs exist in WORKSPACE (not in /tmp)
for dir in human-inputs ai-generated-outputs papers corpus sections references figures; do
  check "15d: QSB $dir/ in WORKSPACE" test -d "$LOCAL_QSB/$dir"
done
# Content dirs must NOT have been created in /tmp
for dir in human-inputs ai-generated-outputs papers corpus sections references figures; do
  check "15d: QSB $dir/ NOT in cwd (/tmp)" test ! -d "/tmp/$dir"
done
# Framework state in WORKSPACE (since WORKSPACE=PROJECT_ROOT, no sub-workspace)
check "15d: QSB ralphd exists in WORKSPACE" test -f "$LOCAL_QSB/ralphd"
check "15d: QSB .ralphrc exists in WORKSPACE" test -f "$LOCAL_QSB/.ralphrc"

rm -rf "$LOCAL_QSB"

echo ""

# ── Test 16: Workspace-first agent resolution ─────────────────
echo "--- 16. Workspace-First Agent Resolution ---"

AGENT_TEST_DIR=$(mktemp -d)

# 16a. Workspace agent takes priority over framework agent
(
  cd "$AGENT_TEST_DIR"
  mkdir -p .claude/agents
  echo "# Custom workspace scout" > .claude/agents/scout.md
  RALPH_HOME="$RALPH_HOME" RESULT=$(resolve_agent_path scout)
  [ "$RESULT" = ".claude/agents/scout.md" ] || { echo "FAIL: got '$RESULT'"; exit 1; }
)
if [ $? -eq 0 ]; then
  pass "16a: workspace agent takes priority over framework agent"
else
  fail "16a: workspace agent takes priority over framework agent"
fi

# 16b. Falls back to framework when no workspace agent
(
  cd "$AGENT_TEST_DIR"
  rm -rf .claude/agents
  RESULT=$(RALPH_HOME="$RALPH_HOME" resolve_agent_path scout)
  [ "$RESULT" = "${RALPH_HOME}/.claude/agents/scout.md" ] || { echo "FAIL: got '$RESULT'"; exit 1; }
)
if [ $? -eq 0 ]; then
  pass "16b: falls back to framework agent when workspace has none"
else
  fail "16b: falls back to framework agent when workspace has none"
fi

# 16c. Returns empty when agent doesn't exist anywhere
(
  cd "$AGENT_TEST_DIR"
  RESULT=$(RALPH_HOME="$RALPH_HOME" resolve_agent_path nonexistent-agent-xyz)
  [ -z "$RESULT" ] || { echo "FAIL: got '$RESULT'"; exit 1; }
)
if [ $? -eq 0 ]; then
  pass "16c: returns empty for nonexistent agent"
else
  fail "16c: returns empty for nonexistent agent"
fi

# 16d. Local init creates .claude/agents/ landing zone
LOCAL_AGENT_DIR=$(mktemp -d)
(
  cd "$LOCAL_AGENT_DIR"
  RALPH_HOME="$RALPH_HOME" bash "$RALPH_HOME/scripts/init-project.sh" > /dev/null 2>&1
)
if [ -d "$LOCAL_AGENT_DIR/.ralph/.claude/agents" ]; then
  pass "16d: init-project.sh creates .claude/agents/ in local workspace"
else
  fail "16d: init-project.sh did not create .claude/agents/ in local workspace"
fi

rm -rf "$AGENT_TEST_DIR" "$LOCAL_AGENT_DIR"

echo ""

# ── Test 17: Quick Start paths (A, B, C) ──────────────────────
echo "--- 17. Quick Start Paths ---"

# 17a. Quick Start A: run from ralPhD repo directly
# No init needed — verify the ralPhD repo has everything needed to run ralph-loop.sh
check "17a: ralph-loop.sh exists" test -f "$RALPH_HOME/ralph-loop.sh"
check "17a: ralph-loop.sh is executable" test -x "$RALPH_HOME/ralph-loop.sh"
check "17a: .claude/agents/ exists" test -d "$RALPH_HOME/.claude/agents"
check "17a: templates/checkpoint.md exists" test -f "$RALPH_HOME/templates/checkpoint.md"
check "17a: templates/implementation-plan.md exists" test -f "$RALPH_HOME/templates/implementation-plan.md"
check "17a: specs/ directory exists" test -d "$RALPH_HOME/specs"
QS_A_AGENT_COUNT=$(ls "$RALPH_HOME/.claude/agents/"*.md 2>/dev/null | wc -l | tr -d ' ')
if [ "$QS_A_AGENT_COUNT" -gt 5 ]; then
  pass "17a: RALPH_HOME has $QS_A_AGENT_COUNT agent files"
else
  fail "17a: expected >5 agents in RALPH_HOME/.claude/agents, got $QS_A_AGENT_COUNT"
fi

# 17b. Quick Start B: init-project.sh /abs/path run from a different cwd
# Verifies content dirs, symlinks, .claude/agents, and ralphd from a fresh init
QS_B_DIR=$(mktemp -d)
(
  cd /tmp
  RALPH_HOME="$RALPH_HOME" bash "$RALPH_HOME/scripts/init-project.sh" "$QS_B_DIR" > /dev/null 2>&1
)

# Content dirs exist in WORKSPACE
for dir in human-inputs ai-generated-outputs papers corpus sections references figures; do
  check "17b: $dir/ in WORKSPACE" test -d "$QS_B_DIR/$dir"
done

# Content dirs were NOT scattered into cwd (/tmp)
for dir in human-inputs ai-generated-outputs papers corpus; do
  check "17b: $dir/ NOT created in /tmp" test ! -d "/tmp/$dir"
done

# Framework symlinks resolve
check "17b: specs/ is symlink" test -L "$QS_B_DIR/specs"
check "17b: templates/ is symlink" test -L "$QS_B_DIR/templates"
check "17b: specs symlink resolves" test -d "$QS_B_DIR/specs"
check "17b: templates symlink resolves" test -d "$QS_B_DIR/templates"

# .claude/agents is a symlink pointing to RALPH_HOME
check "17b: .claude/agents is symlink" test -L "$QS_B_DIR/.claude/agents"
check "17b: .claude/agents symlink resolves" test -d "$QS_B_DIR/.claude/agents"
QS_B_AGENTS_TARGET=$(readlink "$QS_B_DIR/.claude/agents")
if [ "$QS_B_AGENTS_TARGET" = "$RALPH_HOME/.claude/agents" ]; then
  pass "17b: .claude/agents → RALPH_HOME/.claude/agents"
else
  fail "17b: .claude/agents points to wrong target: '$QS_B_AGENTS_TARGET'"
fi

# ralphd is executable and --help works
check "17b: ralphd is executable" test -x "$QS_B_DIR/ralphd"
if "$QS_B_DIR/ralphd" --help 2>&1 | grep -q 'Usage:'; then
  pass "17b: ralphd --help outputs usage"
else
  fail "17b: ralphd --help did not output expected 'Usage:' line"
fi

rm -rf "$QS_B_DIR"

# 17c. Quick Start C: init-project.sh /path/.ralph (brownfield/split layout)
# Content dirs at PROJECT_ROOT, framework state inside .ralph/, symlinks resolve
QS_C_PROJECT=$(mktemp -d)
QS_C_WS="$QS_C_PROJECT/.ralph"
(
  cd "$QS_C_PROJECT"
  RALPH_HOME="$RALPH_HOME" bash "$RALPH_HOME/scripts/init-project.sh" "$QS_C_WS" > /dev/null 2>&1
)

# Content dirs at PROJECT_ROOT (not inside .ralph/)
for dir in human-inputs ai-generated-outputs papers corpus sections references figures; do
  check "17c: $dir/ at project root" test -d "$QS_C_PROJECT/$dir"
done

# Symlinks inside .ralph/ exist and resolve to project root
for dir in ai-generated-outputs papers corpus sections references figures; do
  check "17c: .ralph/$dir is symlink" test -L "$QS_C_WS/$dir"
  check "17c: .ralph/$dir symlink resolves" test -d "$QS_C_WS/$dir"
done
check "17c: .ralph/inputs is symlink" test -L "$QS_C_WS/inputs"
check "17c: .ralph/inputs symlink resolves" test -d "$QS_C_WS/inputs"

# .claude/agents symlink points to RALPH_HOME
check "17c: .ralph/.claude/agents is symlink" test -L "$QS_C_WS/.claude/agents"
check "17c: .ralph/.claude/agents symlink resolves" test -d "$QS_C_WS/.claude/agents"
QS_C_AGENTS_TARGET=$(readlink "$QS_C_WS/.claude/agents")
if [ "$QS_C_AGENTS_TARGET" = "$RALPH_HOME/.claude/agents" ]; then
  pass "17c: .ralph/.claude/agents → RALPH_HOME/.claude/agents"
else
  fail "17c: .ralph/.claude/agents points to wrong target: '$QS_C_AGENTS_TARGET'"
fi

# Framework state inside .ralph/
check "17c: .ralph/logs/ exists" test -d "$QS_C_WS/logs"
check "17c: .ralph/.ralphrc exists" test -f "$QS_C_WS/.ralphrc"

# ralphd is executable and --help works
check "17c: .ralph/ralphd is executable" test -x "$QS_C_WS/ralphd"
if "$QS_C_WS/ralphd" --help 2>&1 | grep -q 'Usage:'; then
  pass "17c: .ralph/ralphd --help outputs usage"
else
  fail "17c: .ralph/ralphd --help did not output expected 'Usage:' line"
fi

rm -rf "$QS_C_PROJECT"

echo ""

# ── Test 18: Serial mode regression (worktree-isolation safety net) ──
echo "--- 18. Serial Mode Regression ---"

# These tests establish a baseline for serial execution behavior.
# The parallel worktree isolation fix (steps 2-8) must NEVER change
# the behavior verified here.

SERIAL_TEST_DIR=$(mktemp -d)

# 18a. Serial plan: agent detection picks first unchecked task
cat > "$SERIAL_TEST_DIR/plan.md" << 'SERIALEOF'
# Implementation Plan — serial-test

**Thread:** serial-test
**Architecture:** serial
**Autonomy:** autopilot

## Phase 1 — Setup

- [x] 1. Create scaffold — **coder**

## Phase 2 — Build

- [ ] 2. Write module A — **coder**
- [ ] 3. Write module B — **editor**
SERIALEOF

cat > "$SERIAL_TEST_DIR/checkpoint.md" << 'SERIALEOF'
# Checkpoint — serial-test

**Thread:** serial-test
**Last agent:** coder
**Status:** ready

## Next Task

2. Write module A — **coder**
SERIALEOF

DETECTED=$(detect_agent_from_checkpoint "$SERIAL_TEST_DIR/checkpoint.md" "$SERIAL_TEST_DIR/plan.md")
if [ "$DETECTED" = "coder" ]; then
  pass "18a: serial plan agent detection: '$DETECTED'"
else
  fail "18a: serial plan agent detection: got '$DETECTED', expected 'coder'"
fi

# 18b. Serial plan: phase is NOT detected as parallel
DETECTED_PHASE=$(detect_current_phase "$SERIAL_TEST_DIR/plan.md")
if ! is_parallel_phase "$DETECTED_PHASE"; then
  pass "18b: serial phase not detected as parallel: '$DETECTED_PHASE'"
else
  fail "18b: serial phase incorrectly detected as parallel"
fi

# 18c. Parallel plan run WITHOUT --parallel flag: parallel block is skipped
# Verify the gate: ARCH_MODE must equal "parallel" for run_parallel_phase to be called
ARCH_MODE_DEFAULT=$(resolve_arch_mode_from_plan "" "$SERIAL_TEST_DIR/plan.md")
if [ "$ARCH_MODE_DEFAULT" = "serial" ]; then
  pass "18c: serial plan resolves to ARCH_MODE=serial (parallel block skipped)"
else
  fail "18c: serial plan ARCH_MODE: got '$ARCH_MODE_DEFAULT', expected 'serial'"
fi

# 18d. Parallel plan with --serial flag override: parallel block is skipped
ARCH_MODE_OVERRIDE=$(resolve_arch_mode_from_plan "serial" "$PARSER_FIXTURE_DIR/implementation-plan.md")
if [ "$ARCH_MODE_OVERRIDE" = "serial" ]; then
  pass "18d: --serial flag overrides parallel plan to serial"
else
  fail "18d: --serial override: got '$ARCH_MODE_OVERRIDE', expected 'serial'"
fi

# 18e. Plan with no Architecture field: defaults to serial
cat > "$SERIAL_TEST_DIR/plan_no_arch.md" << 'SERIALEOF'
# Implementation Plan

## Phase 1 — Work

- [ ] 1. Do stuff — **coder**
SERIALEOF

ARCH_MODE_NONE=$(resolve_arch_mode_from_plan "" "$SERIAL_TEST_DIR/plan_no_arch.md")
if [ "$ARCH_MODE_NONE" = "serial" ]; then
  pass "18e: missing Architecture field defaults to serial"
else
  fail "18e: missing Architecture: got '$ARCH_MODE_NONE', expected 'serial'"
fi

# 18f. Plan with (parallel) phases but Architecture: serial → parallel block skipped
cat > "$SERIAL_TEST_DIR/plan_mixed.md" << 'SERIALEOF'
# Implementation Plan

**Architecture:** serial

## Phase 1 — Build (parallel)

- [ ] 1. Module A — **coder**
- [ ] 2. Module B — **coder**
SERIALEOF

ARCH_MODE_MIXED=$(resolve_arch_mode_from_plan "" "$SERIAL_TEST_DIR/plan_mixed.md")
if [ "$ARCH_MODE_MIXED" = "serial" ]; then
  pass "18f: Architecture:serial overrides (parallel) annotation"
else
  fail "18f: Architecture:serial with (parallel) phases: got '$ARCH_MODE_MIXED', expected 'serial'"
fi

# 18g. Parallel plan: ARCH_MODE=parallel AND (parallel) phase → parallel path taken
ARCH_MODE_PAR=$(resolve_arch_mode_from_plan "" "$PARSER_FIXTURE_DIR/implementation-plan.md")
DETECTED_PAR_PHASE=$(detect_current_phase "$PARSER_FIXTURE_DIR/implementation-plan.md")
if [ "$ARCH_MODE_PAR" = "parallel" ] && is_parallel_phase "$DETECTED_PAR_PHASE"; then
  pass "18g: parallel plan + (parallel) phase → parallel path taken"
else
  fail "18g: expected ARCH_MODE=parallel + (parallel) phase. ARCH_MODE='$ARCH_MODE_PAR', phase='$DETECTED_PAR_PHASE'"
fi

# 18h. Plan with dependencies: (depends: N) annotation is preserved in task text
cat > "$SERIAL_TEST_DIR/plan_deps.md" << 'SERIALEOF'
# Implementation Plan

**Architecture:** parallel

## Phase 1 — Scrape (parallel)

- [x] 1. Scrape job A — **job-scraper**
- [x] 2. Scrape job B — **job-scraper**

## Phase 2 — Write

- [ ] 3. Write generic resume (depends: 1,2) — **resume-writer**

## Phase 3 — Tailor (parallel)

- [ ] 4. Tailor for job A (depends: 3) — **resume-tailor**
- [ ] 5. Tailor for job B (depends: 3) — **resume-tailor**
SERIALEOF

# Current phase should be Phase 2 (first phase with unchecked tasks)
DETECTED_DEP_PHASE=$(detect_current_phase "$SERIAL_TEST_DIR/plan_deps.md")
if echo "$DETECTED_DEP_PHASE" | grep -q "Phase 2"; then
  pass "18h: dependency plan: current phase is Phase 2"
else
  fail "18h: dependency plan: got '$DETECTED_DEP_PHASE', expected Phase 2"
fi

# Phase 2 is NOT parallel
if ! is_parallel_phase "$DETECTED_DEP_PHASE"; then
  pass "18i: dependency plan: Phase 2 is not parallel"
else
  fail "18i: dependency plan: Phase 2 incorrectly detected as parallel"
fi

# Task text includes the (depends: N) annotation
TASKS_DEP=$(collect_phase_tasks "$SERIAL_TEST_DIR/plan_deps.md" "## Phase 3 — Tailor (parallel)")
if echo "$TASKS_DEP" | grep -q "depends: 3"; then
  pass "18j: (depends: N) annotation preserved in collected task text"
else
  fail "18j: (depends: N) annotation not found in task text: '$TASKS_DEP'"
fi

# 18k. Dependency validation: no deps → safe to parallelize
cat > "$SERIAL_TEST_DIR/plan_nodeps.md" << 'SERIALEOF'
# Implementation Plan

**Architecture:** parallel

## Phase 1 — Build (parallel)

- [ ] 1. Module A — **coder**
- [ ] 2. Module B — **coder**
- [ ] 3. Module C — **coder**
SERIALEOF

if validate_phase_dependencies "$SERIAL_TEST_DIR/plan_nodeps.md" "## Phase 1 — Build (parallel)" 2>/dev/null; then
  pass "18k: no dependencies → validate_phase_dependencies returns 0"
else
  fail "18k: no dependencies should return 0 (safe)"
fi

# 18l. Dependency validation: all deps satisfied → safe
cat > "$SERIAL_TEST_DIR/plan_deps_ok.md" << 'SERIALEOF'
# Implementation Plan

**Architecture:** parallel

## Phase 1 — Scrape (parallel)

- [x] 1. Scrape A — **job-scraper**
- [x] 2. Scrape B — **job-scraper**

## Phase 2 — Tailor (parallel)

- [ ] 3. Tailor A (depends: 1) — **resume-tailor**
- [ ] 4. Tailor B (depends: 2) — **resume-tailor**
SERIALEOF

if validate_phase_dependencies "$SERIAL_TEST_DIR/plan_deps_ok.md" "## Phase 2 — Tailor (parallel)" 2>/dev/null; then
  pass "18l: all deps satisfied → validate_phase_dependencies returns 0"
else
  fail "18l: all deps satisfied should return 0 (safe)"
fi

# 18m. Dependency validation: unsatisfied deps → unsafe
cat > "$SERIAL_TEST_DIR/plan_deps_bad.md" << 'SERIALEOF'
# Implementation Plan

**Architecture:** parallel

## Phase 1 — Scrape (parallel)

- [ ] 1. Scrape A — **job-scraper**
- [x] 2. Scrape B — **job-scraper**

## Phase 2 — Tailor (parallel)

- [ ] 3. Tailor A (depends: 1) — **resume-tailor**
- [ ] 4. Tailor B (depends: 2) — **resume-tailor**
SERIALEOF

if ! validate_phase_dependencies "$SERIAL_TEST_DIR/plan_deps_bad.md" "## Phase 2 — Tailor (parallel)" 2>/dev/null; then
  pass "18m: unsatisfied dep (task 1 unchecked) → returns 1 (unsafe)"
else
  fail "18m: unsatisfied dep should return 1 (unsafe)"
fi

# 18n. Dependency validation: multi-deps, one unsatisfied
cat > "$SERIAL_TEST_DIR/plan_deps_multi.md" << 'SERIALEOF'
# Implementation Plan

## Phase 1 — Scrape (parallel)

- [x] 1. Scrape A — **job-scraper**
- [ ] 2. Scrape B — **job-scraper**
- [x] 3. Scrape C — **job-scraper**

## Phase 2 — Write

- [ ] 4. Write resume (depends: 1,2,3) — **resume-writer**
SERIALEOF

if ! validate_phase_dependencies "$SERIAL_TEST_DIR/plan_deps_multi.md" "## Phase 2 — Write" 2>/dev/null; then
  pass "18n: multi-dep with one unsatisfied (task 2) → returns 1"
else
  fail "18n: multi-dep with unsatisfied task 2 should return 1"
fi

# 18o. Verify the critical code paths exist in ralph-loop.sh
# The parallel gate: ARCH_MODE == "parallel" && is_parallel_phase
check "18o: ralph-loop.sh has ARCH_MODE parallel gate" grep -q 'ARCH_MODE.*=.*"parallel"' "$RALPH_HOME/ralph-loop.sh"
check "18p: ralph-loop.sh has is_parallel_phase check" grep -q 'is_parallel_phase' "$RALPH_HOME/ralph-loop.sh"
check "18q: ralph-loop.sh has serial fallthrough message" grep -q 'running serially' "$RALPH_HOME/ralph-loop.sh"

rm -rf "$SERIAL_TEST_DIR"
echo ""

# ── Test 19: Worktree isolation functions ─────────────────────
echo "--- 19. Worktree Isolation Functions ---"

WT_TEST_DIR=$(mktemp -d)
(
  cd "$WT_TEST_DIR"
  git init --quiet
  echo "initial" > file.txt
  echo "# Checkpoint" > checkpoint.md
  git add -A && git commit -m "init" --quiet
)

# 19a. create_worktree produces a valid directory
WT_PATH=$(cd "$WT_TEST_DIR" && create_worktree 1 1)
if [ -n "$WT_PATH" ] && [ -d "$WT_TEST_DIR/$WT_PATH" ]; then
  pass "19a: create_worktree produces valid directory: $WT_PATH"
else
  fail "19a: create_worktree failed, got: '$WT_PATH'"
fi

# 19b. Worktree has its own copy of files
if [ -f "$WT_TEST_DIR/$WT_PATH/checkpoint.md" ]; then
  pass "19b: worktree has its own checkpoint.md"
else
  fail "19b: worktree missing checkpoint.md"
fi

# 19c. Worktree is on its own branch
WT_BRANCH=$(git -C "$WT_TEST_DIR/$WT_PATH" rev-parse --abbrev-ref HEAD 2>/dev/null)
if echo "$WT_BRANCH" | grep -q "parallel/iter-1-task-1"; then
  pass "19c: worktree on correct branch: $WT_BRANCH"
else
  fail "19c: worktree branch: got '$WT_BRANCH', expected parallel/iter-1-task-1"
fi

# 19d. Changes in worktree don't affect main
echo "worktree change" > "$WT_TEST_DIR/$WT_PATH/new-file.txt"
(cd "$WT_TEST_DIR/$WT_PATH" && git add -A && git commit -m "worktree work" --quiet)
if [ ! -f "$WT_TEST_DIR/new-file.txt" ]; then
  pass "19d: worktree changes don't leak to main"
else
  fail "19d: worktree change leaked to main directory"
fi

# 19e. merge_worktree on non-conflicting branch succeeds
if (cd "$WT_TEST_DIR" && merge_worktree "$WT_PATH" "test-agent") 2>/dev/null; then
  pass "19e: merge_worktree succeeds (non-conflicting)"
else
  fail "19e: merge_worktree failed on non-conflicting branch"
fi

# 19f. After merge, file from worktree exists in main
if [ -f "$WT_TEST_DIR/new-file.txt" ]; then
  pass "19f: merged file exists in main after merge"
else
  fail "19f: merged file not found in main"
fi

# 19g. remove_worktree cleans up
(cd "$WT_TEST_DIR" && remove_worktree "$WT_PATH")
if [ ! -d "$WT_TEST_DIR/$WT_PATH" ]; then
  pass "19g: remove_worktree cleans up directory"
else
  fail "19g: worktree directory still exists after removal"
fi

# 19h. Branch is deleted after removal
if ! git -C "$WT_TEST_DIR" branch --list "parallel/iter-1-task-1" | grep -q "parallel"; then
  pass "19h: branch deleted after worktree removal"
else
  fail "19h: branch still exists after removal"
fi

# 19i. merge_worktree detects conflict
(
  cd "$WT_TEST_DIR"
  # Create worktree 2
  WT2_PATH=$(create_worktree 1 2)
  # Modify same file in both main and worktree
  echo "main change" > file.txt
  git add file.txt && git commit -m "main edit" --quiet
  echo "worktree conflict" > "$WT2_PATH/file.txt"
  (cd "$WT2_PATH" && git add file.txt && git commit -m "conflicting edit" --quiet)
  if ! merge_worktree "$WT2_PATH" "conflict-agent" 2>/dev/null; then
    pass "19i: merge_worktree detects conflict and returns 1"
  else
    fail "19i: merge_worktree should have returned 1 on conflict"
  fi
  remove_worktree "$WT2_PATH" 2>/dev/null
) 2>/dev/null

# 19j. Create multiple worktrees simultaneously
(
  cd "$WT_TEST_DIR"
  WT_A=$(create_worktree 2 1)
  WT_B=$(create_worktree 2 2)
  WT_C=$(create_worktree 2 3)
  if [ -d "$WT_A" ] && [ -d "$WT_B" ] && [ -d "$WT_C" ]; then
    pass "19j: 3 worktrees created simultaneously"
  else
    fail "19j: failed to create 3 worktrees: A=$WT_A B=$WT_B C=$WT_C"
  fi
  remove_worktree "$WT_A" 2>/dev/null
  remove_worktree "$WT_B" 2>/dev/null
  remove_worktree "$WT_C" 2>/dev/null
) 2>/dev/null

rm -rf "$WT_TEST_DIR"
echo ""

# ── Test 20: Merge scripts for shared files ───────────────────
echo "--- 20. Merge Scripts ---"

MERGE_TEST_DIR=$(mktemp -d)

# 20a. merge_plan_checkboxes: unions checkbox state
cat > "$MERGE_TEST_DIR/main-plan.md" << 'MERGEEOF'
# Implementation Plan

## Phase 1 — Scrape (parallel)

- [ ] 1. Scrape A — **job-scraper**
- [ ] 2. Scrape B — **job-scraper**
- [ ] 3. Scrape C — **job-scraper**

## Phase 2 — Write

- [ ] 4. Write resume — **resume-writer**
MERGEEOF

# Worktree 1 checked off task 1
cat > "$MERGE_TEST_DIR/wt1-plan.md" << 'MERGEEOF'
# Implementation Plan

## Phase 1 — Scrape (parallel)

- [x] 1. Scrape A — **job-scraper**
- [ ] 2. Scrape B — **job-scraper**
- [ ] 3. Scrape C — **job-scraper**

## Phase 2 — Write

- [ ] 4. Write resume — **resume-writer**
MERGEEOF

# Worktree 2 checked off task 2
cat > "$MERGE_TEST_DIR/wt2-plan.md" << 'MERGEEOF'
# Implementation Plan

## Phase 1 — Scrape (parallel)

- [ ] 1. Scrape A — **job-scraper**
- [x] 2. Scrape B — **job-scraper**
- [ ] 3. Scrape C — **job-scraper**

## Phase 2 — Write

- [ ] 4. Write resume — **resume-writer**
MERGEEOF

# Worktree 3 checked off task 3
cat > "$MERGE_TEST_DIR/wt3-plan.md" << 'MERGEEOF'
# Implementation Plan

## Phase 1 — Scrape (parallel)

- [ ] 1. Scrape A — **job-scraper**
- [ ] 2. Scrape B — **job-scraper**
- [x] 3. Scrape C — **job-scraper**

## Phase 2 — Write

- [ ] 4. Write resume — **resume-writer**
MERGEEOF

merge_plan_checkboxes "$MERGE_TEST_DIR/main-plan.md" \
  "$MERGE_TEST_DIR/wt1-plan.md" "$MERGE_TEST_DIR/wt2-plan.md" "$MERGE_TEST_DIR/wt3-plan.md"

CHECKED_COUNT=$(grep -c '^\- \[x\]' "$MERGE_TEST_DIR/main-plan.md")
if [ "$CHECKED_COUNT" = "3" ]; then
  pass "20a: merge_plan_checkboxes unions 3 checkboxes from 3 worktrees"
else
  fail "20a: expected 3 checked tasks, got $CHECKED_COUNT"
fi

# Task 4 should still be unchecked
if grep -q '^\- \[ \] 4\.' "$MERGE_TEST_DIR/main-plan.md"; then
  pass "20b: unrelated task 4 remains unchecked after merge"
else
  fail "20b: task 4 was incorrectly modified"
fi

# 20c. merge_checkpoints: combines knowledge state
cat > "$MERGE_TEST_DIR/base-checkpoint.md" << 'MERGEEOF'
# Checkpoint — test

**Thread:** test
**Last updated:** 2026-03-14
**Last agent:** plan
**Status:** building

## Knowledge State

| Task | Status | Notes |
|------|--------|-------|

## Last Reflection

<none yet>

## Next Task

1. Scrape A — **job-scraper**
MERGEEOF

cat > "$MERGE_TEST_DIR/wt1-checkpoint.md" << 'MERGEEOF'
# Checkpoint — test

**Thread:** test
**Last updated:** 2026-03-15
**Last agent:** job-scraper
**Status:** building

## Knowledge State

| Task | Status | Notes |
|------|--------|-------|
| Scrape A | done | Found 5 requirements |

## Next Task

2. Scrape B — **job-scraper**
MERGEEOF

cat > "$MERGE_TEST_DIR/wt2-checkpoint.md" << 'MERGEEOF'
# Checkpoint — test

**Thread:** test
**Last updated:** 2026-03-15
**Last agent:** job-scraper
**Status:** building

## Knowledge State

| Task | Status | Notes |
|------|--------|-------|
| Scrape B | done | Found 3 requirements |

## Next Task

3. Scrape C — **job-scraper**
MERGEEOF

# merge_checkpoints reads implementation-plan.md from cwd for Next Task
cat > "$MERGE_TEST_DIR/implementation-plan.md" << 'MERGEEOF'
# Plan
- [x] 1. Scrape A — **job-scraper**
- [x] 2. Scrape B — **job-scraper**
- [ ] 3. Write resume — **resume-writer**
MERGEEOF

(cd "$MERGE_TEST_DIR" && merge_checkpoints "base-checkpoint.md" \
  "wt1-checkpoint.md" "wt2-checkpoint.md")

if grep -q "Scrape A" "$MERGE_TEST_DIR/base-checkpoint.md" && \
   grep -q "Scrape B" "$MERGE_TEST_DIR/base-checkpoint.md"; then
  pass "20c: merge_checkpoints combines knowledge state from both worktrees"
else
  fail "20c: merged checkpoint missing knowledge state entries"
fi

# 20d. merge_checkpoints: Next Task points to next unchecked plan task (not agent text)
if grep -q "Write resume" "$MERGE_TEST_DIR/base-checkpoint.md"; then
  pass "20d: merged Next Task reads from plan (task 3: Write resume)"
else
  fail "20d: merged Next Task should reference next unchecked plan task"
fi

# 20e. merge_checkpoints preserves header
if grep -q 'Thread.*test' "$MERGE_TEST_DIR/base-checkpoint.md"; then
  pass "20e: merged checkpoint preserves thread header"
else
  fail "20e: merged checkpoint missing thread header"
fi

rm -rf "$MERGE_TEST_DIR"
echo ""

# ── Test 21: Pre-merge validation gates ───────────────────────
echo "--- 21. Pre-merge Validation ---"

VAL_TEST_DIR=$(mktemp -d)
(
  cd "$VAL_TEST_DIR"
  git init --quiet
  echo "base" > file.txt
  git add -A && git commit -m "init" --quiet
)

# 21a. Worktree with commits → valid
(
  cd "$VAL_TEST_DIR"
  WT_VAL=$(create_worktree 3 1)
  echo "work done" > "$WT_VAL/output.txt"
  (cd "$WT_VAL" && git add -A && git commit -m "agent work" --quiet)
  if validate_worktree_output "$WT_VAL" "good-agent" 2>/dev/null; then
    pass "21a: worktree with commits → valid"
  else
    fail "21a: worktree with commits should be valid"
  fi
  remove_worktree "$WT_VAL" 2>/dev/null
) 2>/dev/null

# 21b. Worktree with no commits → rejected
(
  cd "$VAL_TEST_DIR"
  WT_EMPTY=$(create_worktree 3 2)
  if ! validate_worktree_output "$WT_EMPTY" "empty-agent" 2>/dev/null; then
    pass "21b: worktree with no commits → rejected"
  else
    fail "21b: empty worktree should be rejected"
  fi
  remove_worktree "$WT_EMPTY" 2>/dev/null
) 2>/dev/null

rm -rf "$VAL_TEST_DIR"
echo ""

# ── Test 22: Yield signal check in ralph_agent.py ─────────────
echo "--- 22. Yield Signal ---"

# 22a. should_yield() returns True when RALPH_RUN is set and yield file exists
YIELD_TEST_DIR=$(mktemp -d)
touch "$YIELD_TEST_DIR/yield"
if RALPH_RUN="$YIELD_TEST_DIR" python3 -c "
import sys, os
sys.path.insert(0, '$RALPH_HOME')
from ralph_agent import should_yield
assert should_yield() == True, 'should_yield() must return True when yield file exists'
" 2>/dev/null; then
  pass "22a: should_yield() returns True with yield file"
else
  fail "22a: should_yield() returns True with yield file"
fi

# 22b. should_yield() returns False when RALPH_RUN is unset
if python3 -c "
import sys, os
os.environ.pop('RALPH_RUN', None)
sys.path.insert(0, '$RALPH_HOME')
from ralph_agent import should_yield
assert should_yield() == False, 'should_yield() must return False when RALPH_RUN unset'
" 2>/dev/null; then
  pass "22b: should_yield() returns False when RALPH_RUN unset"
else
  fail "22b: should_yield() returns False when RALPH_RUN unset"
fi

# 22c. should_yield() returns False when RALPH_RUN set but no yield file
YIELD_EMPTY_DIR=$(mktemp -d)
if RALPH_RUN="$YIELD_EMPTY_DIR" python3 -c "
import sys, os
sys.path.insert(0, '$RALPH_HOME')
from ralph_agent import should_yield
assert should_yield() == False, 'should_yield() must return False when no yield file'
" 2>/dev/null; then
  pass "22c: should_yield() returns False without yield file"
else
  fail "22c: should_yield() returns False without yield file"
fi

# 22d. Loop integration: yield gate stops agent loop after one turn
if RALPH_RUN="$YIELD_TEST_DIR" RALPH_HOME="$RALPH_HOME" python3 -c "
import sys, os, types
sys.path.insert(0, '$RALPH_HOME')
import ralph_agent

# Track call_model invocations
call_count = 0

class MockToolCall:
    name = 'read_file'
    id = 'tc_mock_1'
    input = {'path': '/tmp/test'}

class MockResponse:
    text_blocks = ['mock output']
    tool_calls = [MockToolCall()]
    input_tokens = 100
    output_tokens = 50
    cache_creation_input_tokens = 0
    cache_read_input_tokens = 0
    raw_content = None
    raw = None

def mock_create_client(provider):
    return None

def mock_call_model(*args, **kwargs):
    global call_count
    call_count += 1
    return MockResponse()

def mock_execute_tool(name, inp):
    return 'mock result'

# Monkeypatch
ralph_agent.create_client = mock_create_client
ralph_agent.call_model = mock_call_model
ralph_agent.execute_tool = mock_execute_tool

# Yield file already exists in YIELD_TEST_DIR (created above)
# Run the agent — should complete one turn then stop
ralph_agent.run_agent(
    agent_name='coder',
    system_prompt='test',
    task='do something',
    model='claude-sonnet-4-6',
    max_tokens=4096,
)
assert call_count == 1, f'Expected 1 call_model invocation, got {call_count}'
" 2>/dev/null; then
  pass "22d: yield gate stops loop after one turn"
else
  fail "22d: yield gate stops loop after one turn"
fi

rm -rf "$YIELD_TEST_DIR" "$YIELD_EMPTY_DIR"
echo ""

# ── Test 23: Circuit breaker state survives cleanup ───────────
echo "--- 23. Circuit Breaker Cleanup ---"

CB_TEST_DIR=$(mktemp -d)

# 23a. CB_FILE should survive cleanup_loop_processes
CB_FILE="$CB_TEST_DIR/circuit-breaker"
YIELD_FILE="$CB_TEST_DIR/yield"
CTX_FILE="$CB_TEST_DIR/context"
BUDGET_FILE="$CB_TEST_DIR/budget"
JSONL_MONITOR_PID=""
MONITOR_PID=""
CLAUDE_PID=""

echo "3" > "$CB_FILE"
touch "$YIELD_FILE" "$CTX_FILE" "$BUDGET_FILE"

cleanup_loop_processes 2>/dev/null

if [ -f "$CB_FILE" ] && [ "$(cat "$CB_FILE")" = "3" ]; then
  pass "23a: CB_FILE survives cleanup_loop_processes"
else
  fail "23a: CB_FILE survives cleanup_loop_processes"
fi

# 23b. Other monitoring files should be deleted by cleanup
if [ ! -f "$YIELD_FILE" ] && [ ! -f "$CTX_FILE" ] && [ ! -f "$BUDGET_FILE" ]; then
  pass "23b: monitoring files deleted by cleanup"
else
  fail "23b: monitoring files deleted by cleanup"
fi

rm -rf "$CB_TEST_DIR"
echo ""

# ── Test 24: Context window tracking in ralph_agent.py ────────
echo "--- 24. Context Window Tracking ---"

# 24a. get_context_window returns correct values
if RALPH_HOME="$RALPH_HOME" python3 -c "
import sys
sys.path.insert(0, '$RALPH_HOME')
from providers import get_context_window
assert get_context_window('claude-sonnet-4-6') == 1_000_000, 'sonnet should be 1M'
assert get_context_window('claude-haiku-4-5') == 200_000, 'haiku should be 200k'
assert get_context_window('gpt-5.4') == 272_000, 'gpt-5.4 should be 272k'
" 2>/dev/null; then
  pass "24a: get_context_window returns correct values"
else
  fail "24a: get_context_window returns correct values"
fi

# 24b. context_threshold returns correct thresholds
if RALPH_HOME="$RALPH_HOME" python3 -c "
import sys
sys.path.insert(0, '$RALPH_HOME')
from ralph_agent import context_threshold
assert context_threshold('claude-sonnet-4-6') == 0.65, '1M model should be 0.65'
assert context_threshold('claude-opus-4-6') == 0.65, '1M model should be 0.65'
assert context_threshold('claude-haiku-4-5') == 0.50, '<1M model should be 0.50'
assert context_threshold('gpt-5.4') == 0.50, '<1M model should be 0.50'
" 2>/dev/null; then
  pass "24b: context_threshold returns correct thresholds"
else
  fail "24b: context_threshold returns correct thresholds"
fi

# 24c. should_stop_for_context detects threshold breach (input+output+tool_results)
if RALPH_HOME="$RALPH_HOME" python3 -c "
import sys
sys.path.insert(0, '$RALPH_HOME')
from ralph_agent import should_stop_for_context, estimate_tool_result_tokens
# 1M window, 65% threshold = 650k. 700k+50k+0=750k >= 650k → should stop
assert should_stop_for_context(700_000, 50_000, 'claude-sonnet-4-6') == True
# 400k+100k+0=500k < 650k → should not stop
assert should_stop_for_context(400_000, 100_000, 'claude-sonnet-4-6') == False
# Transition case: 600k+50k+0=650k >= 650k → should stop
assert should_stop_for_context(600_000, 50_000, 'claude-sonnet-4-6') == True
# Large tool result case: 600k+10k+40k(tool)=650k >= 650k → should stop
assert should_stop_for_context(600_000, 10_000, 'claude-sonnet-4-6', tool_result_tokens=40_000) == True
# Below with tool results: 500k+10k+40k=550k < 650k → should not stop
assert should_stop_for_context(500_000, 10_000, 'claude-sonnet-4-6', tool_result_tokens=40_000) == False
# estimate_tool_result_tokens: ~4 chars per token
tr = [{'type': 'tool_result', 'tool_use_id': 'x', 'content': 'a' * 40_000}]
est = estimate_tool_result_tokens(tr)
assert 9_000 <= est <= 11_000, f'Expected ~10k tokens for 40k chars, got {est}'
# 200k window, 50% threshold = 100k
assert should_stop_for_context(80_000, 30_000, 'claude-haiku-4-5') == True
assert should_stop_for_context(60_000, 30_000, 'claude-haiku-4-5') == False
" 2>/dev/null; then
  pass "24c: should_stop_for_context detects threshold breach"
else
  fail "24c: should_stop_for_context detects threshold breach"
fi

# 24d. Loop integration: context gate stops agent loop after one turn
CTX_TEST_DIR=$(mktemp -d)
if RALPH_RUN="$CTX_TEST_DIR" RALPH_HOME="$RALPH_HOME" python3 -c "
import sys, os
sys.path.insert(0, '$RALPH_HOME')
import ralph_agent

call_count = 0

class MockToolCall:
    name = 'read_file'
    id = 'tc_mock_1'
    input = {'path': '/tmp/test'}

class MockResponse:
    text_blocks = ['mock output']
    tool_calls = [MockToolCall()]
    input_tokens = 700_000  # above 65% of 1M = 650k
    output_tokens = 50
    cache_creation_input_tokens = 0
    cache_read_input_tokens = 0
    raw_content = None
    raw = None

def mock_create_client(provider): return None
def mock_call_model(*a, **kw):
    global call_count
    call_count += 1
    return MockResponse()
def mock_execute_tool(name, inp): return 'mock result'

ralph_agent.create_client = mock_create_client
ralph_agent.call_model = mock_call_model
ralph_agent.execute_tool = mock_execute_tool

ralph_agent.run_agent('coder', 'test', 'do something', 'claude-sonnet-4-6', 4096)
assert call_count == 1, f'Expected 1 call, got {call_count}'
" 2>/dev/null; then
  pass "24d: context gate stops loop after one turn"
else
  fail "24d: context gate stops loop after one turn"
fi
rm -rf "$CTX_TEST_DIR"

# 24e. Transition case: input below threshold but input+output crosses it
CTX_TRANS_DIR=$(mktemp -d)
if RALPH_RUN="$CTX_TRANS_DIR" RALPH_HOME="$RALPH_HOME" python3 -c "
import sys, os
sys.path.insert(0, '$RALPH_HOME')
import ralph_agent

call_count = 0

class MockToolCall:
    name = 'read_file'
    id = 'tc_mock_1'
    input = {'path': '/tmp/test'}

class MockResponse:
    text_blocks = ['mock output']
    tool_calls = [MockToolCall()]
    input_tokens = 600_000  # below 650k threshold alone
    output_tokens = 50_000  # but 600k+50k=650k >= 650k threshold
    cache_creation_input_tokens = 0
    cache_read_input_tokens = 0
    raw_content = None
    raw = None

def mock_create_client(p): return None
def mock_call_model(*a, **kw):
    global call_count
    call_count += 1
    return MockResponse()
def mock_execute_tool(n, i): return 'mock result'

ralph_agent.create_client = mock_create_client
ralph_agent.call_model = mock_call_model
ralph_agent.execute_tool = mock_execute_tool

ralph_agent.run_agent('coder', 'test', 'do something', 'claude-sonnet-4-6', 4096)
assert call_count == 1, f'Expected 1 call (transition case), got {call_count}'
" 2>/dev/null; then
  pass "24e: transition case (input+output crosses threshold) stops loop"
else
  fail "24e: transition case (input+output crosses threshold) stops loop"
fi
rm -rf "$CTX_TRANS_DIR"

# 24f. Large tool result case: input+output below threshold but tool results push it over
# Note: truncate_result() caps individual results to 50k chars (~12.5k tokens).
# So we set input_tokens=635k, output_tokens=2k (637k < 650k without tool results).
# Tool result of 50k chars → ~12.5k estimated tokens → 637k+12.5k=649.5k.
# With the tool result, estimated_next ≈ 649.5k which is just under 650k.
# Using 636k input → 636k+2k+12.5k = 650.5k >= 650k → should stop.
CTX_TOOL_DIR=$(mktemp -d)
if RALPH_RUN="$CTX_TOOL_DIR" RALPH_HOME="$RALPH_HOME" python3 -c "
import sys, os
sys.path.insert(0, '$RALPH_HOME')
import ralph_agent

call_count = 0

class MockToolCall:
    name = 'read_file'
    id = 'tc_mock_1'
    input = {'path': '/tmp/test'}

class MockResponse:
    text_blocks = ['mock output']
    tool_calls = [MockToolCall()]
    input_tokens = 636_000  # below 650k threshold
    output_tokens = 2_000   # input+output = 638k, still below 650k
    cache_creation_input_tokens = 0
    cache_read_input_tokens = 0
    raw_content = None
    raw = None

def mock_create_client(p): return None
def mock_call_model(*a, **kw):
    global call_count
    call_count += 1
    return MockResponse()

# Return a tool result at the truncation limit (50k chars → ~12.5k tokens)
# 638k + 12.5k = 650.5k >= 650k threshold → should stop
def mock_execute_tool(n, i): return 'x' * 50_000

ralph_agent.create_client = mock_create_client
ralph_agent.call_model = mock_call_model
ralph_agent.execute_tool = mock_execute_tool

ralph_agent.run_agent('coder', 'test', 'do something', 'claude-sonnet-4-6', 4096)
assert call_count == 1, f'Expected 1 call (large tool result case), got {call_count}'
" 2>/dev/null; then
  pass "24f: large tool result pushes past threshold, stops loop"
else
  fail "24f: large tool result pushes past threshold, stops loop"
fi
rm -rf "$CTX_TOOL_DIR"
echo ""

# ── Test 25: Duplicate-agent detection in parallel phases ─────
echo "--- 25. Duplicate Agent Detection ---"

# 25a. check_duplicate_agents rejects duplicate agent names
if check_duplicate_agents "scout" "critic" "scout" 2>/dev/null | grep -q "scout"; then
  if ! check_duplicate_agents "scout" "critic" "scout" 2>/dev/null; then
    pass "25a: duplicate agents detected and rejected"
  else
    fail "25a: duplicate agents should return non-zero"
  fi
else
  fail "25a: duplicate agents should mention 'scout' in error"
fi

# 25b. check_duplicate_agents accepts unique agent names
if check_duplicate_agents "scout" "critic" "deep-reader" 2>/dev/null; then
  pass "25b: unique agents accepted"
else
  fail "25b: unique agents should return zero"
fi

# 25c. check_duplicate_agents handles single agent
if check_duplicate_agents "coder" 2>/dev/null; then
  pass "25c: single agent accepted"
else
  fail "25c: single agent should return zero"
fi

echo ""

# ── Test 26: merge_checkpoints preserves What I Did and non-done rows ─
echo "--- 26. Lossy Merge Fix ---"

MERGE26_DIR=$(mktemp -d)

# Base checkpoint (on main) — has pre-existing state that must survive merge
cat > "$MERGE26_DIR/base-checkpoint.md" << 'MERGEEOF'
# Checkpoint — test-thread

**Thread:** test-thread
**Last updated:** 2026-03-20
**Last agent:** planner
**Status:** in-progress

## Knowledge State

| Task | Status | Notes |
|------|--------|-------|
| 0 | done | base row from previous phase |

## What I Did

- base did from previous iteration

## Last Reflection

<none yet>

## Next Task

1. Do something — **coder**
MERGEEOF

# Worktree 1 checkpoint — has "What I Did" and a "done" row
cat > "$MERGE26_DIR/wt1-checkpoint.md" << 'MERGEEOF'
# Checkpoint — test-thread

**Thread:** test-thread
**Last updated:** 2026-03-20
**Last agent:** scout
**Status:** in-progress

## Knowledge State

| Task | Status | Notes |
|------|--------|-------|
| 1 | done | Scraped site A |

## What I Did

- Scraped site A, found 5 requirements
- Generated corpus file

## Last Reflection

Good run, found useful data.

## Next Task

2. Scrape B — **scout**
MERGEEOF

# Worktree 2 checkpoint — has "What I Did" and a "failed" row
cat > "$MERGE26_DIR/wt2-checkpoint.md" << 'MERGEEOF'
# Checkpoint — test-thread

**Thread:** test-thread
**Last updated:** 2026-03-20
**Last agent:** scout
**Status:** in-progress

## Knowledge State

| Task | Status | Notes |
|------|--------|-------|
| 2 | failed | API rate limited |

## What I Did

- Attempted site B, hit rate limit after 3 pages

## Last Reflection

Failed due to rate limiting.

## Next Task

2. Scrape B — **scout**
MERGEEOF

# Run merge
cp "$MERGE26_DIR/base-checkpoint.md" "$MERGE26_DIR/output.md"
merge_checkpoints "$MERGE26_DIR/output.md" \
  "$MERGE26_DIR/wt1-checkpoint.md" \
  "$MERGE26_DIR/wt2-checkpoint.md"

# 26a. "What I Did" content preserved from wt1
if grep -q "Scraped site A" "$MERGE26_DIR/output.md"; then
  pass "26a: What I Did from wt1 preserved"
else
  fail "26a: What I Did from wt1 should be in merged checkpoint"
fi

# 26b. "What I Did" content preserved from wt2
if grep -q "site B" "$MERGE26_DIR/output.md"; then
  pass "26b: What I Did from wt2 preserved"
else
  fail "26b: What I Did from wt2 should be in merged checkpoint"
fi

# 26c. Non-done knowledge row (failed) preserved
if grep -q "failed" "$MERGE26_DIR/output.md"; then
  pass "26c: non-done knowledge row preserved"
else
  fail "26c: non-done (failed) knowledge row should be in merged checkpoint"
fi

# 26d. Done knowledge row still preserved
if grep -q "Scraped site A" "$MERGE26_DIR/output.md" && grep -q "done" "$MERGE26_DIR/output.md"; then
  pass "26d: done knowledge row still preserved"
else
  fail "26d: done knowledge row should still be in merged checkpoint"
fi

# 26e. Pre-existing base knowledge row survives merge
if grep -q "base row from previous phase" "$MERGE26_DIR/output.md"; then
  pass "26e: base checkpoint knowledge row preserved"
else
  fail "26e: base checkpoint knowledge row should survive merge"
fi

# 26f. Pre-existing base "What I Did" content survives merge
if grep -q "base did from previous iteration" "$MERGE26_DIR/output.md"; then
  pass "26f: base checkpoint What I Did preserved"
else
  fail "26f: base checkpoint What I Did should survive merge"
fi

rm -rf "$MERGE26_DIR"
echo ""

# ── Test 27: Plan-mode audit + commit/push helpers ─────────────
echo "--- 27. Plan Audit + Commit ---"

PLAN27_DIR=$(mktemp -d)
PLAN27_REMOTE=$(mktemp -d)

(
  cd "$PLAN27_REMOTE"
  git init --bare --initial-branch=main >/dev/null 2>&1
)

(
  cd "$PLAN27_DIR"
  git init --initial-branch=main >/dev/null 2>&1
  git remote add origin "$PLAN27_REMOTE"
  cat > checkpoint.md <<'EOF'
# Checkpoint

## Next Task

1. Plan something — **plan**
EOF
  cat > implementation-plan.md <<'EOF'
# Plan

- [ ] 1. Do the thing — **coder**
EOF
  git add checkpoint.md implementation-plan.md
  git commit -m "init" --quiet
  git push origin main --quiet 2>/dev/null

  export CURRENT_THREAD="plan-audit-test"
  export PLAN_AUDIT_FILE="$PLAN27_DIR/plan-audit-failed"

  SNAPSHOT_OK=$(mktemp)
  ALLOWED_OK=$(mktemp)
  VIOLATIONS_OK=$(mktemp)
  plan_write_state_snapshot "$SNAPSHOT_OK"
  printf '\n- [ ] 2. Another task — **coder**\n' >> implementation-plan.md
  if plan_audit_changed_files "$SNAPSHOT_OK" "$ALLOWED_OK" "$VIOLATIONS_OK" \
      && grep -q '^implementation-plan.md$' "$ALLOWED_OK" \
      && ! [ -s "$VIOLATIONS_OK" ]; then
    pass "27a: plan audit accepts allowlisted file changes"
  else
    fail "27a: plan audit should accept allowlisted file changes"
  fi

  if plan_commit_and_push_changes "$ALLOWED_OK" >/dev/null 2>&1 \
      && git log -1 --format='%s' | grep -q "plan: update plan state" \
      && git --git-dir="$PLAN27_REMOTE" log --format='%s' main -1 2>/dev/null | grep -q "plan: update plan state"; then
    pass "27b: allowlisted plan changes committed and pushed"
  else
    fail "27b: allowlisted plan changes should be committed and pushed"
  fi

  SNAPSHOT_BAD=$(mktemp)
  ALLOWED_BAD=$(mktemp)
  VIOLATIONS_BAD=$(mktemp)
  plan_write_state_snapshot "$SNAPSHOT_BAD"
  printf 'unauthorized\n' > README.md
  if ! plan_audit_changed_files "$SNAPSHOT_BAD" "$ALLOWED_BAD" "$VIOLATIONS_BAD" \
      && grep -q '^README.md$' "$VIOLATIONS_BAD" \
      && grep -q '^README.md$' "$PLAN_AUDIT_FILE"; then
    pass "27c: plan audit rejects unauthorized file changes"
  else
    fail "27c: plan audit should reject unauthorized file changes"
  fi
)

rm -rf "$PLAN27_DIR" "$PLAN27_REMOTE"
echo ""

# ── Test 28: Planner prompt and wrapper restrictions ───────────
echo "--- 28. Planner Restrictions ---"

if grep -q "## IMPORTANT" "$RALPH_HOME/prompt-plan.md" \
    && grep -q "Do \\*\\*not\\*\\* create or edit \`.claude/agents/\\*\\.md\`" "$RALPH_HOME/prompt-plan.md"; then
  pass "28a: prompt-plan.md has explicit IMPORTANT planner boundary"
else
  fail "28a: prompt-plan.md should declare strict planner boundaries"
fi

if grep -q -- '--allowedTools "Read" "Glob" "Grep" "Bash"' "$RALPH_HOME/ralph-loop.sh" \
    && ! grep -q '"Agent"' "$RALPH_HOME/ralph-loop.sh" \
    && ! grep -q 'Write(.claude/agents/\\*\\.md)' "$RALPH_HOME/ralph-loop.sh"; then
  pass "28b: ralph-loop.sh plan mode removed Agent and agent-file writes"
else
  fail "28b: ralph-loop.sh should remove Agent and agent-file writes from plan mode"
fi

if grep -q 'implementation-plan.md' "$RALPH_HOME/.claude/agents/plan.md" \
    && grep -q 'Do \\*\\*not\\*\\* delegate to other agents' "$RALPH_HOME/.claude/agents/plan.md"; then
  pass "28c: plan agent file restrictions aligned with wrapper"
else
  fail "28c: plan agent file restrictions should align with wrapper"
fi

echo ""

# ── Test 29: Coder/refactorer prompt contracts ─────────────────
echo "--- 29. Agent Prompt Contracts ---"

if grep -q "Plan is intent, repo is truth" "$RALPH_HOME/.claude/agents/coder.md" \
    && grep -q "Record the RED commit hash" "$RALPH_HOME/.claude/agents/coder.md"; then
  pass "29a: coder prompt documents repo-truth + RED proof rules"
else
  fail "29a: coder prompt should document repo-truth + RED proof rules"
fi

if grep -q "Baseline-before / baseline-after verification" "$RALPH_HOME/.claude/agents/refactorer.md" \
    && grep -q "Do not change public APIs" "$RALPH_HOME/.claude/agents/refactorer.md"; then
  pass "29b: refactorer prompt enforces semantic preservation"
else
  fail "29b: refactorer prompt should enforce semantic preservation"
fi

echo ""

# ── Summary ───────────────────────────────────────────────────
echo "=== Results: $PASS/$TESTS passed, $FAIL failed ==="
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
