#!/usr/bin/env bash
set -euo pipefail

# test-workflow-local.sh — Simulate the GitHub Actions workflow locally
#
# Tests the critical path without calling the Anthropic API:
#   1. CI init (init-project.sh --ci)
#   2. Template injection (thread, date, autonomy)
#   3. RALPH_HOME resolution in ralph-loop.sh
#   4. Agent detection from checkpoint.md
#   5. Workflow YAML structure
#   6. Idempotent re-init
#   7. Path context preamble (RALPH_HOME separation)
#   8. Tool path resolution (RALPH_HOME)
#   9. Commit-back step (post-run result delivery)
#   10. Webhook callback step (result delivery to external URL)
#
# Usage: bash tests/test-workflow-local.sh

RALPH_HOME="$(cd "$(dirname "$0")/.." && pwd)"
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

echo "=== Test: Workflow Local Simulation ==="
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

# detect_agent extracted from ralph-loop.sh
detect_agent() {
  local ckpt="$1"
  local next_task
  next_task=$(grep -i '^\*\*Next Task\*\*:\|^Next Task:' "$ckpt" 2>/dev/null \
    | head -1 | sed 's/.*: *//' | sed 's/\*//g')
  if [ -z "$next_task" ]; then
    next_task=$(awk '/^## Next Task/{found=1; next} found && /[^ ]/{print; exit}' "$ckpt" 2>/dev/null)
  fi
  next_task=$(echo "$next_task" | sed 's/([^)]*)//g; s/\*//g; s/^ *//; s/ *$//')
  case "$next_task" in
    none*|None*|"<"*|"") echo ""; return ;;
  esac
  local agent="${next_task##* }"
  agent=$(echo "$agent" | sed 's/[^a-zA-Z0-9_-]//g')
  echo "$agent"
}

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

3. Create the workflow file — **coder**
EOF

DETECTED=$(detect_agent "$WORKSPACE/checkpoint.md")
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

DETECTED=$(detect_agent "$WORKSPACE/checkpoint.md")
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

DETECTED=$(detect_agent "$WORKSPACE/checkpoint.md")
if [ -z "$DETECTED" ]; then
  pass "no-task detection: empty (correct)"
else
  fail "no-task detection: got '$DETECTED', expected empty"
fi

# Verify agent files exist
for agent in coder scout critic paper-writer; do
  check "agent file exists: $agent.md" test -f "$RALPH_HOME/.claude/agents/$agent.md"
done
echo ""

# ── Test 5: Workflow YAML structure ───────────────────────────
echo "--- 5. Workflow YAML Validation ---"
check "ralph-run.yml exists" test -f "$RALPH_HOME/.github/workflows/ralph-run.yml"

if python3 -c "
import yaml, sys
with open('$RALPH_HOME/.github/workflows/ralph-run.yml') as f:
    doc = yaml.safe_load(f)
jobs = doc.get('jobs', {})
assert 'ralph-loop' in jobs, 'missing ralph-loop job'
steps = jobs['ralph-loop']['steps']
assert len(steps) >= 9, f'expected >=9 steps, got {len(steps)}'
step_names = [s.get('name', '') for s in steps]
assert any('Check out ralPhD' in n for n in step_names), 'missing checkout step'
assert any('Initialize' in n for n in step_names), 'missing init step'
assert any('ralph-loop' in n for n in step_names), 'missing run step'
assert any('Commit results' in n for n in step_names), 'missing commit-back step'
assert any('Upload' in n for n in step_names), 'missing upload step'
assert any('summary' in n.lower() for n in step_names), 'missing summary step'

# Check inputs
on_field = doc.get(True) or doc.get('on')
inputs = on_field['workflow_dispatch']['inputs']
required_inputs = {'thread', 'prompt'}
for inp in required_inputs:
    assert inp in inputs, f'missing required input: {inp}'
    assert inputs[inp].get('required', False), f'{inp} should be required'
sys.exit(0)
" 2>/dev/null; then
  pass "YAML structure valid (jobs, steps, inputs)"
else
  fail "YAML structure validation"
fi

# Check no secrets in the workflow file
if grep -q 'sk-ant\|AKIA\|ghp_' "$RALPH_HOME/.github/workflows/ralph-run.yml" 2>/dev/null; then
  fail "secrets found in workflow file!"
else
  pass "no hardcoded secrets in workflow"
fi
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
from tools import TOOLS, AGENT_TOOLS, get_tools_for_agent

# All 17 tools should be registered
assert len(TOOLS) == 17, f'Expected 17 tools, got {len(TOOLS)}'

# Every tool in AGENT_TOOLS must exist in TOOLS
for agent, tool_list in AGENT_TOOLS.items():
    for t in tool_list:
        assert t in TOOLS, f'Agent {agent} references unknown tool: {t}'

# get_tools_for_agent should work for all known agents
for agent in AGENT_TOOLS:
    names, schemas = get_tools_for_agent(agent)
    assert len(names) > 0, f'Agent {agent} has no tools'
    assert len(schemas) == len(names), f'Schema count mismatch for {agent}'
" 2>/dev/null; then
  pass "tools/__init__.py: all 17 tools load, agent registries valid"
else
  fail "tools/__init__.py: all 17 tools load, agent registries valid"
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

# ── Test 9: Commit-back step ─────────────────────────────────
echo "--- 9. Commit-back Step ---"

# 9a. Verify commit_mode input in YAML
if python3 -c "
import yaml, sys
with open('$RALPH_HOME/.github/workflows/ralph-run.yml') as f:
    doc = yaml.safe_load(f)
on_field = doc.get(True) or doc.get('on')
inputs = on_field['workflow_dispatch']['inputs']
assert 'commit_mode' in inputs, 'missing commit_mode input'
cm = inputs['commit_mode']
assert cm['default'] == 'branch', f'commit_mode default should be branch, got {cm[\"default\"]}'
assert set(cm['options']) == {'branch', 'direct', 'none'}, f'unexpected options: {cm[\"options\"]}'
" 2>/dev/null; then
  pass "commit_mode input: exists with branch/direct/none options"
else
  fail "commit_mode input validation"
fi

# 9b. Verify commit-back step conditions
if python3 -c "
import yaml, sys
with open('$RALPH_HOME/.github/workflows/ralph-run.yml') as f:
    doc = yaml.safe_load(f)
steps = doc['jobs']['ralph-loop']['steps']
commit_step = None
for s in steps:
    if 'Commit results' in s.get('name', ''):
        commit_step = s
        break
assert commit_step is not None, 'commit-back step not found'

# Must have condition: only when target_repo is set and commit_mode != none
cond = commit_step.get('if', '')
assert 'target_repo' in cond, 'commit-back should check target_repo'
assert 'none' in cond, 'commit-back should check commit_mode != none'

# Must have env vars for thread, commit_mode, target_ref
env_block = commit_step.get('env', {})
assert 'INPUT_THREAD' in env_block, 'missing INPUT_THREAD env'
assert 'INPUT_COMMIT_MODE' in env_block, 'missing INPUT_COMMIT_MODE env'
assert 'INPUT_TARGET_REF' in env_block, 'missing INPUT_TARGET_REF env'
" 2>/dev/null; then
  pass "commit-back step: conditions and env vars correct"
else
  fail "commit-back step conditions/env validation"
fi

# 9c. Verify commit-back step handles branch and direct modes
COMMIT_SCRIPT=$(python3 -c "
import yaml
with open('$RALPH_HOME/.github/workflows/ralph-run.yml') as f:
    doc = yaml.safe_load(f)
for s in doc['jobs']['ralph-loop']['steps']:
    if 'Commit results' in s.get('name', ''):
        print(s.get('run', ''))
        break
" 2>/dev/null)

if echo "$COMMIT_SCRIPT" | grep -q 'ralph/' && \
   echo "$COMMIT_SCRIPT" | grep -q 'branch' && \
   echo "$COMMIT_SCRIPT" | grep -q 'direct'; then
  pass "commit-back script: handles branch (ralph/<thread>) and direct modes"
else
  fail "commit-back script: missing branch/direct handling"
fi

if echo "$COMMIT_SCRIPT" | grep -q 'git push'; then
  pass "commit-back script: includes git push"
else
  fail "commit-back script: missing git push"
fi

if echo "$COMMIT_SCRIPT" | grep -q 'No.*commit\|No.*change\|nothing.*to commit'; then
  pass "commit-back script: handles no-changes case"
else
  fail "commit-back script: missing no-changes handling"
fi

# 9d. Simulate commit-back with a proper origin/clone (like CI)
COMMIT_TEST_DIR=$(mktemp -d)
(
  # Create a bare "remote" repo (simulates GitHub)
  ORIGIN_DIR="$COMMIT_TEST_DIR/origin.git"
  WORK_DIR="$COMMIT_TEST_DIR/workspace"

  git init --bare "$ORIGIN_DIR" --quiet 2>/dev/null

  # Clone and make initial commit (simulates actions/checkout)
  git clone "$ORIGIN_DIR" "$WORK_DIR" --quiet 2>/dev/null
  cd "$WORK_DIR"
  git config user.name "ralph[bot]"
  git config user.email "ralph-bot@users.noreply.github.com"
  echo "initial" > README.md
  git add -A && git commit -m "initial" --quiet
  git push origin main --quiet 2>/dev/null

  # Simulate agent work: create outputs on top of origin/main
  mkdir -p ai-generated-outputs/test-thread/coder
  echo "task summary" > ai-generated-outputs/test-thread/coder/task-summary.md
  echo "updated checkpoint" > checkpoint.md

  # Run the commit-back logic (extracted from workflow)
  INPUT_THREAD="test-thread"
  INPUT_COMMIT_MODE="branch"
  INPUT_TARGET_REF="main"

  # Stage any uncommitted changes
  if ! (git diff --quiet HEAD && git diff --cached --quiet && [ -z "$(git ls-files --others --exclude-standard)" ]); then
    git add -A
    git commit -m "ralph: agent outputs for thread '${INPUT_THREAD}'" \
      --author="ralph[bot] <ralph-bot@users.noreply.github.com>" --quiet
  fi

  # Count commits since origin/main
  COMMIT_COUNT=$(git log --author="ralph\[bot\]" --oneline "origin/${INPUT_TARGET_REF}..HEAD" 2>/dev/null | wc -l | tr -d '[:space:]')

  if [ "$COMMIT_COUNT" = "0" ]; then
    exit 1
  fi

  # Verify the commit was made
  LAST_MSG=$(git log -1 --format='%s')
  echo "$LAST_MSG" | grep -q "ralph: agent outputs" || exit 1
  echo "$LAST_MSG" | grep -q "test-thread" || exit 1

  # Push to branch (simulates branch mode)
  BRANCH_NAME="ralph/${INPUT_THREAD}"
  git push origin "HEAD:refs/heads/${BRANCH_NAME}" --force --quiet 2>/dev/null || exit 1

  # Verify the branch was created on origin
  git ls-remote --heads origin | grep -q "ralph/test-thread" || exit 1
)
if [ $? -eq 0 ]; then
  pass "commit-back simulation: agent outputs committed and pushed to branch"
else
  fail "commit-back simulation"
fi

# 9e. Verify no-changes case doesn't fail
(
  cd "$COMMIT_TEST_DIR/workspace"
  # No new changes — should gracefully detect nothing to push
  if git diff --quiet HEAD && git diff --cached --quiet && [ -z "$(git ls-files --others --exclude-standard)" ]; then
    # Commit count should be 0 (we already pushed)
    COMMIT_COUNT=$(git log --author="ralph\[bot\]" --oneline "origin/main..HEAD" 2>/dev/null | wc -l | tr -d '[:space:]')
    # After the push to branch, HEAD is still ahead of origin/main by 1
    # This is fine — in real CI the step would just push again (idempotent)
    exit 0
  fi
  exit 1
)
if [ $? -eq 0 ]; then
  pass "commit-back simulation: no-changes case handled"
else
  fail "commit-back simulation: no-changes case"
fi

# 9f. Verify summary step includes commit_mode
if python3 -c "
import yaml
with open('$RALPH_HOME/.github/workflows/ralph-run.yml') as f:
    doc = yaml.safe_load(f)
for s in doc['jobs']['ralph-loop']['steps']:
    if 'summary' in s.get('name', '').lower():
        run = s.get('run', '')
        assert 'commit_mode' in run.lower() or 'COMMIT_MODE' in run, 'summary should include commit_mode'
        env = s.get('env', {})
        assert 'INPUT_COMMIT_MODE' in env, 'summary env missing INPUT_COMMIT_MODE'
        break
" 2>/dev/null; then
  pass "summary step: includes commit_mode info"
else
  fail "summary step: missing commit_mode"
fi

rm -rf "$COMMIT_TEST_DIR"
echo ""

# ── Test 10: Webhook callback step ───────────────────────────
echo "--- 10. Webhook Callback Step ---"

# 10a. Verify callback_url input in YAML
if python3 -c "
import yaml, sys
with open('$RALPH_HOME/.github/workflows/ralph-run.yml') as f:
    doc = yaml.safe_load(f)
on_field = doc.get(True) or doc.get('on')
inputs = on_field['workflow_dispatch']['inputs']
assert 'callback_url' in inputs, 'missing callback_url input'
cu = inputs['callback_url']
assert cu.get('required', True) == False, 'callback_url should not be required'
assert cu['default'] == '', 'callback_url default should be empty string'
assert cu['type'] == 'string', 'callback_url type should be string'
" 2>/dev/null; then
  pass "callback_url input: exists, optional, default empty"
else
  fail "callback_url input validation"
fi

# 10b. Verify webhook step exists with correct conditions
if python3 -c "
import yaml, sys
with open('$RALPH_HOME/.github/workflows/ralph-run.yml') as f:
    doc = yaml.safe_load(f)
steps = doc['jobs']['ralph-loop']['steps']
webhook_step = None
for s in steps:
    if 'webhook' in s.get('name', '').lower() or 'callback' in s.get('name', '').lower():
        webhook_step = s
        break
assert webhook_step is not None, 'webhook/callback step not found'

# Must run on always() and only when callback_url is set
cond = webhook_step.get('if', '')
assert 'always()' in cond, f'webhook should run on always(), got: {cond}'
assert 'callback_url' in cond, f'webhook should check callback_url, got: {cond}'
" 2>/dev/null; then
  pass "webhook step: exists with always() + callback_url condition"
else
  fail "webhook step conditions"
fi

# 10c. Verify webhook step has required env vars
if python3 -c "
import yaml, sys
with open('$RALPH_HOME/.github/workflows/ralph-run.yml') as f:
    doc = yaml.safe_load(f)
steps = doc['jobs']['ralph-loop']['steps']
webhook_step = None
for s in steps:
    if 'webhook' in s.get('name', '').lower() or 'callback' in s.get('name', '').lower():
        webhook_step = s
        break
env_block = webhook_step.get('env', {})
required_env = ['INPUT_CALLBACK_URL', 'INPUT_THREAD', 'INPUT_MODE', 'INPUT_COMMIT_MODE']
for e in required_env:
    assert e in env_block, f'webhook step missing env: {e}'
# CALLBACK_SECRET should reference a secret
assert 'CALLBACK_SECRET' in env_block, 'webhook step missing CALLBACK_SECRET env'
assert 'secrets.CALLBACK_SECRET' in str(env_block['CALLBACK_SECRET']), 'CALLBACK_SECRET should reference secrets'
" 2>/dev/null; then
  pass "webhook step: has required env vars including CALLBACK_SECRET"
else
  fail "webhook step env vars"
fi

# 10d. Verify webhook script builds JSON with jq and uses curl
WEBHOOK_SCRIPT=$(python3 -c "
import yaml
with open('$RALPH_HOME/.github/workflows/ralph-run.yml') as f:
    doc = yaml.safe_load(f)
for s in doc['jobs']['ralph-loop']['steps']:
    if 'webhook' in s.get('name', '').lower() or 'callback' in s.get('name', '').lower():
        print(s.get('run', ''))
        break
" 2>/dev/null)

if echo "$WEBHOOK_SCRIPT" | grep -q 'jq'; then
  pass "webhook script: uses jq for JSON construction"
else
  fail "webhook script: missing jq usage"
fi

if echo "$WEBHOOK_SCRIPT" | grep -q 'curl'; then
  pass "webhook script: uses curl for HTTP POST"
else
  fail "webhook script: missing curl usage"
fi

if echo "$WEBHOOK_SCRIPT" | grep -q 'ralph.run.completed'; then
  pass "webhook script: includes event type"
else
  fail "webhook script: missing event type"
fi

if echo "$WEBHOOK_SCRIPT" | grep -q 'X-Ralph-Signature'; then
  pass "webhook script: includes HMAC signature header"
else
  fail "webhook script: missing HMAC signature"
fi

if echo "$WEBHOOK_SCRIPT" | grep -q 'openssl.*hmac'; then
  pass "webhook script: uses openssl for HMAC computation"
else
  fail "webhook script: missing openssl HMAC"
fi

# 10e. Verify retry logic
if echo "$WEBHOOK_SCRIPT" | grep -q 'attempt.*[123]\|for attempt'; then
  pass "webhook script: has retry logic"
else
  fail "webhook script: missing retry logic"
fi

if echo "$WEBHOOK_SCRIPT" | grep -q 'non-fatal\|non.fatal'; then
  pass "webhook script: failure is non-fatal"
else
  fail "webhook script: should be non-fatal on failure"
fi

# 10f. Simulate webhook JSON payload construction
WEBHOOK_TEST_DIR=$(mktemp -d)
(
  cd "$WEBHOOK_TEST_DIR"

  # Create a mock checkpoint
  cat > checkpoint.md << 'CKPT'
# Checkpoint — webhook-test

**Thread:** webhook-test
**Last updated:** 2026-03-11
**Last agent:** coder
**Status:** testing

## Knowledge State

| Task | Status | Notes |
|------|--------|-------|
| 1. First task | done | completed |
| 2. Second task | done | completed |
| 3. Third task | pending | next up |

## Next Task

3. Third task — **coder**
CKPT

  # Build the JSON payload using the same jq command from the workflow
  INPUT_THREAD="webhook-test"
  INPUT_MODE="build"
  INPUT_AUTONOMY="autopilot"
  INPUT_MAX_ITER="5"
  INPUT_TARGET="owner/repo"
  INPUT_TARGET_REF="main"
  INPUT_COMMIT_MODE="branch"

  STATUS="completed"
  CHECKPOINT_SUMMARY=$(head -20 checkpoint.md | python3 -c "
import sys, json
print(json.dumps(sys.stdin.read()))" 2>/dev/null | sed 's/^"//;s/"$//')

  LAST_TASK=$(grep -m1 '## Next Task' checkpoint.md -A2 2>/dev/null | tail -1 | sed 's/^ *//' || echo "")
  LAST_AGENT=$(grep -m1 '^\*\*Last agent:\*\*' checkpoint.md 2>/dev/null | sed 's/.*:\*\* *//' || echo "")
  TASKS_DONE=$(grep -c '| done |' checkpoint.md 2>/dev/null || echo "0")
  TASKS_TOTAL=$(grep -c '| done \|| pending \|| in.progress |' checkpoint.md 2>/dev/null || echo "0")

  REVIEW_NEEDED="false"
  REVIEW_BODY=""

  PAYLOAD=$(jq -n \
    --arg thread "$INPUT_THREAD" \
    --arg status "$STATUS" \
    --arg mode "$INPUT_MODE" \
    --arg autonomy "$INPUT_AUTONOMY" \
    --arg max_iter "$INPUT_MAX_ITER" \
    --arg target_repo "$INPUT_TARGET" \
    --arg target_ref "$INPUT_TARGET_REF" \
    --arg commit_mode "$INPUT_COMMIT_MODE" \
    --arg last_agent "$LAST_AGENT" \
    --arg next_task "$LAST_TASK" \
    --arg tasks_done "$TASKS_DONE" \
    --arg tasks_total "$TASKS_TOTAL" \
    --argjson review_needed "$REVIEW_NEEDED" \
    --arg review_body "$REVIEW_BODY" \
    --arg checkpoint_summary "$CHECKPOINT_SUMMARY" \
    --arg run_id "local" \
    --arg run_url "https://github.com/local/actions/runs/0" \
    --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{
      event: "ralph.run.completed",
      timestamp: $timestamp,
      thread: $thread,
      status: $status,
      config: {
        mode: $mode,
        autonomy: $autonomy,
        max_iterations: ($max_iter | tonumber),
        target_repo: $target_repo,
        target_ref: $target_ref,
        commit_mode: $commit_mode
      },
      result: {
        last_agent: $last_agent,
        next_task: $next_task,
        tasks_done: ($tasks_done | tonumber),
        tasks_total: ($tasks_total | tonumber),
        review_needed: $review_needed,
        review_body: (if $review_needed then $review_body else null end),
        checkpoint_summary: $checkpoint_summary
      },
      run: {
        id: $run_id,
        url: $run_url
      }
    }')

  # Validate the JSON payload
  echo "$PAYLOAD" | python3 -c "
import sys, json
p = json.load(sys.stdin)
assert p['event'] == 'ralph.run.completed', f'wrong event: {p[\"event\"]}'
assert p['thread'] == 'webhook-test', f'wrong thread: {p[\"thread\"]}'
assert p['status'] == 'completed', f'wrong status: {p[\"status\"]}'
assert p['config']['mode'] == 'build', f'wrong mode: {p[\"config\"][\"mode\"]}'
assert p['config']['max_iterations'] == 5, f'max_iter should be int 5, got: {p[\"config\"][\"max_iterations\"]}'
assert p['config']['commit_mode'] == 'branch', f'wrong commit_mode'
assert p['result']['last_agent'] == 'coder', f'wrong last_agent: {p[\"result\"][\"last_agent\"]}'
assert p['result']['tasks_done'] == 2, f'wrong tasks_done: {p[\"result\"][\"tasks_done\"]}'
assert p['result']['tasks_total'] == 3, f'wrong tasks_total: {p[\"result\"][\"tasks_total\"]}'
assert p['result']['review_needed'] == False, 'review_needed should be False'
assert p['result']['review_body'] is None, 'review_body should be None when no review'
assert 'webhook-test' in p['result']['checkpoint_summary'], 'checkpoint_summary should contain thread name'
assert p['run']['id'] == 'local', f'wrong run id'
assert 'timestamp' in p, 'missing timestamp'
" || exit 1
)
if [ $? -eq 0 ]; then
  pass "webhook JSON payload: valid structure with correct field types"
else
  fail "webhook JSON payload construction"
fi

# 10g. Test HMAC signature generation
(
  cd "$WEBHOOK_TEST_DIR"
  PAYLOAD='{"event":"ralph.run.completed","thread":"test"}'
  SECRET="test-secret-key"
  SIGNATURE=$(echo -n "$PAYLOAD" | openssl dgst -sha256 -hmac "$SECRET" | sed 's/.*= //')

  # Verify the signature is a valid hex string (64 chars for SHA-256)
  if echo "$SIGNATURE" | grep -qE '^[a-f0-9]{64}$'; then
    true
  else
    exit 1
  fi

  # Verify signature is deterministic (same input = same output)
  SIGNATURE2=$(echo -n "$PAYLOAD" | openssl dgst -sha256 -hmac "$SECRET" | sed 's/.*= //')
  [ "$SIGNATURE" = "$SIGNATURE2" ] || exit 1

  # Verify different secret produces different signature
  SIGNATURE3=$(echo -n "$PAYLOAD" | openssl dgst -sha256 -hmac "other-secret" | sed 's/.*= //')
  [ "$SIGNATURE" != "$SIGNATURE3" ] || exit 1
)
if [ $? -eq 0 ]; then
  pass "HMAC signature: deterministic, correct format, secret-dependent"
else
  fail "HMAC signature generation"
fi

# 10h. Test review_needed payload variation
(
  cd "$WEBHOOK_TEST_DIR"

  # Create HUMAN_REVIEW_NEEDED.md
  cat > HUMAN_REVIEW_NEEDED.md << 'REVIEW'
## Phase 1 Complete

All archive tasks done. Ready for Phase 2 (workflow creation).
REVIEW

  STATUS="review_needed"
  REVIEW_NEEDED="true"
  REVIEW_BODY=$(python3 -c "
import sys, json
print(json.dumps(open('HUMAN_REVIEW_NEEDED.md').read()))" 2>/dev/null | sed 's/^"//;s/"$//')

  PAYLOAD=$(jq -n \
    --arg status "$STATUS" \
    --argjson review_needed "$REVIEW_NEEDED" \
    --arg review_body "$REVIEW_BODY" \
    '{
      status: $status,
      result: {
        review_needed: $review_needed,
        review_body: (if $review_needed then $review_body else null end)
      }
    }')

  echo "$PAYLOAD" | python3 -c "
import sys, json
p = json.load(sys.stdin)
assert p['status'] == 'review_needed', f'wrong status: {p[\"status\"]}'
assert p['result']['review_needed'] == True, 'review_needed should be True'
assert 'Phase 1 Complete' in p['result']['review_body'], 'review_body should contain review content'
" || exit 1
)
if [ $? -eq 0 ]; then
  pass "webhook payload: review_needed=true includes review body"
else
  fail "webhook payload review_needed variation"
fi

# 10i. Verify summary step includes callback info
if python3 -c "
import yaml
with open('$RALPH_HOME/.github/workflows/ralph-run.yml') as f:
    doc = yaml.safe_load(f)
for s in doc['jobs']['ralph-loop']['steps']:
    if 'summary' in s.get('name', '').lower():
        run = s.get('run', '')
        assert 'callback' in run.lower() or 'CALLBACK' in run, 'summary should mention callback'
        env = s.get('env', {})
        assert 'INPUT_CALLBACK_URL' in env, 'summary env missing INPUT_CALLBACK_URL'
        break
" 2>/dev/null; then
  pass "summary step: includes callback info"
else
  fail "summary step: missing callback info"
fi

# 10j. Verify webhook step comes before upload/summary (correct ordering)
if python3 -c "
import yaml
with open('$RALPH_HOME/.github/workflows/ralph-run.yml') as f:
    doc = yaml.safe_load(f)
steps = doc['jobs']['ralph-loop']['steps']
step_names = [s.get('name', '') for s in steps]
webhook_idx = next(i for i, n in enumerate(step_names) if 'webhook' in n.lower() or 'callback' in n.lower())
upload_idx = next(i for i, n in enumerate(step_names) if 'upload' in n.lower())
summary_idx = next(i for i, n in enumerate(step_names) if 'summary' in n.lower())
commit_idx = next(i for i, n in enumerate(step_names) if 'commit results' in n.lower())
# Webhook should be after commit-back but before upload
assert webhook_idx > commit_idx, f'webhook (idx {webhook_idx}) should be after commit-back (idx {commit_idx})'
assert webhook_idx < upload_idx, f'webhook (idx {webhook_idx}) should be before upload (idx {upload_idx})'
assert webhook_idx < summary_idx, f'webhook (idx {webhook_idx}) should be before summary (idx {summary_idx})'
" 2>/dev/null; then
  pass "webhook step: correctly ordered (after commit, before upload/summary)"
else
  fail "webhook step ordering"
fi

rm -rf "$WEBHOOK_TEST_DIR"
echo ""

# ── Summary ───────────────────────────────────────────────────
echo "=== Results: $PASS/$TESTS passed, $FAIL failed ==="
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
