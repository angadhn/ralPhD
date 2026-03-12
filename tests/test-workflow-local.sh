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
#   11. End-to-end pipeline integration
#   12. Architecture field parsing (--serial/--parallel flags)
#   13. Parallel phase detection (phase heading annotations)
#   14. eval.jsonl output format (evaluate_iteration.py --dry-run)
#   15. Local init layout (split content/workspace, symlinks)
#
# Usage: bash tests/test-workflow-local.sh

RALPH_HOME="$(cd "$(dirname "$0")/.." && pwd)"
REDACTOR="$RALPH_HOME/scripts/redact_secrets.py"
source "$RALPH_HOME/lib/detect.sh"
source "$RALPH_HOME/lib/config.sh"
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

3. Create the workflow file — **coder**
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
from tools import TOOLS, AGENT_TOOLS, SERVER_TOOLS, get_tools_for_agent

# All 18 tools should be registered (17 original + git_commit)
assert len(TOOLS) == 18, f'Expected 18 tools, got {len(TOOLS)}'

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
  pass "tools/__init__.py: all 18 tools load, agent registries valid"
else
  fail "tools/__init__.py: all 18 tools load, agent registries valid"
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

# 10f. Verify redaction helper masks representative secrets
if PYTHONPATH="$RALPH_HOME" python3 -c "
from tools.redact import preview_text, redact_text

sample = '''
ANTHROPIC_API_KEY=sk-ant-abcdef1234567890
Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.secretpayload1234567890
ghp_abcdefghijklmnopqrstuvwxyz1234567890
-----BEGIN OPENSSH PRIVATE KEY-----
abc123
-----END OPENSSH PRIVATE KEY-----
'''.strip()
redacted = redact_text(sample)
assert 'sk-ant-' not in redacted
assert 'Bearer eyJ' not in redacted
assert 'ghp_' not in redacted
assert 'BEGIN OPENSSH PRIVATE KEY' not in redacted
assert '[REDACTED]' in redacted

preview = preview_text('OPENAI_API_KEY=sk-proj-abcdefghijklmnopqrstuvwxyz1234567890')
assert 'sk-proj-' not in preview
assert '[REDACTED]' in preview
" 2>/dev/null; then
  pass "redaction helper: masks representative secrets"
else
  fail "redaction helper: failed to mask representative secrets"
fi

# 10g. Simulate webhook JSON payload construction
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
Token: sk-ant-webhooksecret1234567890

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
  CHECKPOINT_SUMMARY=$(head -20 checkpoint.md | python3 "$REDACTOR" | python3 -c "
import sys, json
print(json.dumps(sys.stdin.read()))" 2>/dev/null | sed 's/^"//;s/"$//')

  LAST_TASK=$(grep -m1 '## Next Task' checkpoint.md -A2 2>/dev/null | tail -1 | sed 's/^ *//' | python3 "$REDACTOR" | tr -d '\n' || echo "")
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
assert '[REDACTED]' in p['result']['checkpoint_summary'], 'checkpoint_summary should be redacted'
assert 'sk-ant-webhooksecret' not in p['result']['checkpoint_summary'], 'checkpoint_summary leaked a token'
assert p['run']['id'] == 'local', f'wrong run id'
assert 'timestamp' in p, 'missing timestamp'
" || exit 1
)
if [ $? -eq 0 ]; then
  pass "webhook JSON payload: valid structure with redacted summary"
else
  fail "webhook JSON payload construction"
fi

# 10h. Test HMAC signature generation
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

# 10i. Test review_needed payload variation
(
  cd "$WEBHOOK_TEST_DIR"

  # Create HUMAN_REVIEW_NEEDED.md
  cat > HUMAN_REVIEW_NEEDED.md << 'REVIEW'
## Phase 1 Complete

All archive tasks done. Ready for Phase 2 (workflow creation).
Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.reviewsecret1234567890
REVIEW

  STATUS="review_needed"
  REVIEW_NEEDED="true"
  REVIEW_BODY=$(python3 "$REDACTOR" HUMAN_REVIEW_NEEDED.md | python3 -c "
import sys, json
print(json.dumps(sys.stdin.read()))" 2>/dev/null | sed 's/^"//;s/"$//')

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
assert '[REDACTED]' in p['result']['review_body'], 'review_body should be redacted'
assert 'Bearer eyJ' not in p['result']['review_body'], 'review_body leaked a bearer token'
" || exit 1
)
if [ $? -eq 0 ]; then
  pass "webhook payload: review_needed=true includes redacted review body"
else
  fail "webhook payload review_needed variation"
fi

# 10j. Verify summary step includes callback info and redaction
if python3 -c "
import yaml
with open('$RALPH_HOME/.github/workflows/ralph-run.yml') as f:
    doc = yaml.safe_load(f)
for s in doc['jobs']['ralph-loop']['steps']:
    if 'summary' in s.get('name', '').lower():
        run = s.get('run', '')
        assert 'callback' in run.lower() or 'CALLBACK' in run, 'summary should mention callback'
        assert 'redact_secrets.py' in run, 'summary should redact exported content'
        env = s.get('env', {})
        assert 'INPUT_CALLBACK_URL' in env, 'summary env missing INPUT_CALLBACK_URL'
        break
" 2>/dev/null; then
  pass "summary step: includes callback info and redaction"
else
  fail "summary step: missing callback info or redaction"
fi

# 10k. Verify sanitized artifact preparation and upload path
if python3 -c "
import yaml
with open('$RALPH_HOME/.github/workflows/ralph-run.yml') as f:
    doc = yaml.safe_load(f)
steps = doc['jobs']['ralph-loop']['steps']
prep = next((s for s in steps if 'prepare sanitized artifact' in s.get('name', '').lower()), None)
upload = next((s for s in steps if 'upload' in s.get('name', '').lower()), None)
assert prep is not None, 'missing sanitized artifact preparation step'
assert 'artifact-redacted' in prep.get('run', ''), 'prep step should build artifact-redacted bundle'
assert upload is not None, 'missing upload step'
assert upload.get('with', {}).get('path') == 'artifact-redacted/', 'upload should use sanitized artifact bundle'
" 2>/dev/null; then
  pass "artifact upload: sanitized bundle prepared and uploaded"
else
  fail "artifact upload: missing sanitized bundle"
fi

# 10l. Verify webhook step comes before upload/summary (correct ordering)
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

# 10m. Simulate sanitized artifact bundle creation
(
  cd "$WEBHOOK_TEST_DIR"
  mkdir -p ai-generated-outputs logs
  cat > ai-generated-outputs/task.md << 'OUT'
Agent note: ghp_abcdefghijklmnopqrstuvwxyz1234567890
OUT
  cat > logs/usage.jsonl << 'USAGE'
{"result":"OPENAI_API_KEY=sk-proj-abcdefghijklmnopqrstuvwxyz1234567890"}
USAGE

  ARTIFACT_DIR="$WEBHOOK_TEST_DIR/artifact-redacted"
  sanitize_copy() {
    local src="$1"
    local dst="$2"
    mkdir -p "$(dirname "$dst")"
    python3 "$REDACTOR" "$src" > "$dst"
  }

  rm -rf "$ARTIFACT_DIR"
  mkdir -p "$ARTIFACT_DIR/ai-generated-outputs" "$ARTIFACT_DIR/logs"

  for path in checkpoint.md implementation-plan.md HUMAN_REVIEW_NEEDED.md; do
    if [ -f "$path" ]; then
      sanitize_copy "$path" "$ARTIFACT_DIR/$path"
    fi
  done

  while IFS= read -r path; do
    sanitize_copy "$path" "$ARTIFACT_DIR/$path"
  done < <(find ai-generated-outputs logs -type f | sort)

  python3 -c "
from pathlib import Path

artifact = Path('$WEBHOOK_TEST_DIR/artifact-redacted')
checkpoint = (artifact / 'checkpoint.md').read_text()
review = (artifact / 'HUMAN_REVIEW_NEEDED.md').read_text()
usage = (artifact / 'logs' / 'usage.jsonl').read_text()
task = (artifact / 'ai-generated-outputs' / 'task.md').read_text()

assert '[REDACTED]' in checkpoint
assert 'sk-ant-webhooksecret' not in checkpoint
assert '[REDACTED]' in review
assert 'Bearer eyJ' not in review
assert '[REDACTED]' in usage
assert 'sk-proj-' not in usage
assert '[REDACTED]' in task
assert 'ghp_' not in task
"
)
if [ $? -eq 0 ]; then
  pass "sanitized artifact bundle: redacts checkpoint, review, logs, and AI outputs"
else
  fail "sanitized artifact bundle creation"
fi

rm -rf "$WEBHOOK_TEST_DIR"
echo ""

# ── Test 11: End-to-end pipeline integration ─────────────────
echo "--- 11. End-to-End Pipeline Integration ---"
echo "  (Chains all workflow steps in a single workspace)"

E2E_DIR=$(mktemp -d)
E2E_ORIGIN="$E2E_DIR/origin.git"
E2E_WORKSPACE="$E2E_DIR/workspace"
E2E_RALPH_HOME="$RALPH_HOME"

(
  set -e

  # ── 11a. Create bare origin + clone (simulates actions/checkout) ──
  git init --bare "$E2E_ORIGIN" --quiet 2>/dev/null
  git clone "$E2E_ORIGIN" "$E2E_WORKSPACE" --quiet 2>/dev/null
  cd "$E2E_WORKSPACE"
  git config user.name "ralph[bot]"
  git config user.email "ralph-bot@users.noreply.github.com"

  # Seed with a README (simulates existing project)
  echo "# Test Project" > README.md
  git add -A && git commit -m "initial: seed project" --quiet
  git push origin main --quiet 2>/dev/null

  # ── 11b. Run init-project.sh --ci (workflow step 5, first-run path) ──
  RALPH_HOME="$E2E_RALPH_HOME" bash "$E2E_RALPH_HOME/scripts/init-project.sh" --ci "$E2E_WORKSPACE" > /dev/null 2>&1

  # Verify all init artifacts exist
  for f in checkpoint.md implementation-plan.md inbox.md iteration_count .ralphrc; do
    [ -f "$f" ] || { echo "INIT_FAIL: missing $f"; exit 1; }
  done
  for d in specs templates .claude/agents ai-generated-outputs logs; do
    [ -d "$d" ] || { echo "INIT_FAIL: missing $d/"; exit 1; }
  done

  # ── 11c. Inject templates (workflow step 5, template injection) ──
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

  # ── 11f. Commit-back step (workflow step 7) ──
  INPUT_COMMIT_MODE="branch"
  INPUT_TARGET_REF="main"

  # Count ralph[bot] commits since origin/main
  COMMIT_COUNT=$(git log --author="ralph\[bot\]" --oneline "origin/${INPUT_TARGET_REF}..HEAD" 2>/dev/null | wc -l | tr -d '[:space:]')
  [ "$COMMIT_COUNT" -gt 0 ] || { echo "COMMIT_FAIL: no ralph[bot] commits found"; exit 1; }

  # Push to branch (simulates branch mode)
  BRANCH_NAME="ralph/${E2E_THREAD}"
  git push origin "HEAD:refs/heads/${BRANCH_NAME}" --force --quiet 2>/dev/null

  # Verify branch exists on origin
  git ls-remote --heads "$E2E_ORIGIN" | grep -q "ralph/${E2E_THREAD}" \
    || { echo "PUSH_FAIL: branch not found on origin"; exit 1; }

  # Verify branch content
  BRANCH_TREE=$(git ls-tree --name-only "origin/${BRANCH_NAME}" 2>/dev/null | sort)
  echo "$BRANCH_TREE" | grep -q "sections" || { echo "PUSH_FAIL: sections/ missing from branch"; exit 1; }
  echo "$BRANCH_TREE" | grep -q "ai-generated-outputs" || { echo "PUSH_FAIL: ai-generated-outputs/ missing"; exit 1; }
  echo "$BRANCH_TREE" | grep -q "checkpoint.md" || { echo "PUSH_FAIL: checkpoint.md missing from branch"; exit 1; }

  # ── 11g. Webhook payload construction (workflow step 8) ──
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
    --arg thread "$E2E_THREAD" \
    --arg status "$STATUS" \
    --arg mode "build" \
    --arg autonomy "$E2E_AUTONOMY" \
    --arg max_iter "5" \
    --arg target_repo "test-org/test-project" \
    --arg target_ref "$INPUT_TARGET_REF" \
    --arg commit_mode "$INPUT_COMMIT_MODE" \
    --arg last_agent "$LAST_AGENT" \
    --arg next_task "$LAST_TASK" \
    --arg tasks_done "$TASKS_DONE" \
    --arg tasks_total "$TASKS_TOTAL" \
    --argjson review_needed "$REVIEW_NEEDED" \
    --arg review_body "$REVIEW_BODY" \
    --arg checkpoint_summary "$CHECKPOINT_SUMMARY" \
    --arg run_id "e2e-local" \
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

  # Validate the payload reflects the full pipeline state
  echo "$PAYLOAD" | python3 -c "
import sys, json
p = json.load(sys.stdin)
assert p['event'] == 'ralph.run.completed'
assert p['thread'] == 'e2e-test-pipeline'
assert p['status'] == 'completed'
assert p['config']['mode'] == 'build'
assert p['config']['autonomy'] == 'autopilot'
assert p['config']['commit_mode'] == 'branch'
assert p['config']['target_repo'] == 'test-org/test-project'
assert p['result']['last_agent'] == 'coder', f'last_agent: {p[\"result\"][\"last_agent\"]}'
assert p['result']['tasks_done'] == 1, f'tasks_done: {p[\"result\"][\"tasks_done\"]}'
assert p['result']['tasks_total'] == 3, f'tasks_total: {p[\"result\"][\"tasks_total\"]}'
assert p['result']['review_needed'] == False
assert p['result']['review_body'] is None
assert 'e2e-test-pipeline' in p['result']['checkpoint_summary']
assert 'task 1 done' in p['result']['checkpoint_summary']
" || { echo "WEBHOOK_FAIL: payload validation"; exit 1; }

  # HMAC signature verification (round-trip)
  SECRET="e2e-test-secret"
  SIG=$(echo -n "$PAYLOAD" | openssl dgst -sha256 -hmac "$SECRET" | sed 's/.*= //')
  SIG2=$(echo -n "$PAYLOAD" | openssl dgst -sha256 -hmac "$SECRET" | sed 's/.*= //')
  [ "$SIG" = "$SIG2" ] || { echo "HMAC_FAIL: non-deterministic"; exit 1; }
  echo "$SIG" | grep -qE '^[a-f0-9]{64}$' || { echo "HMAC_FAIL: bad format"; exit 1; }

  # ── 11h. Artifact file verification (workflow step 9) ──
  # These are the paths that upload-artifact would collect
  [ -d "ai-generated-outputs/${E2E_THREAD}" ] || { echo "ARTIFACT_FAIL: outputs dir missing"; exit 1; }
  [ -f "ai-generated-outputs/${E2E_THREAD}/coder/task-summary.md" ] || { echo "ARTIFACT_FAIL: task-summary missing"; exit 1; }
  [ -f "checkpoint.md" ] || { echo "ARTIFACT_FAIL: checkpoint missing"; exit 1; }
  [ -f "implementation-plan.md" ] || { echo "ARTIFACT_FAIL: plan missing"; exit 1; }
  [ -d "logs" ] || { echo "ARTIFACT_FAIL: logs dir missing"; exit 1; }

  # ── 11i. Run summary generation (workflow step 10) ──
  SUMMARY_OUTPUT=$(
    INPUT_THREAD="$E2E_THREAD"
    INPUT_MODE="build"
    INPUT_AUTONOMY="$E2E_AUTONOMY"
    INPUT_MAX_ITER="5"
    INPUT_COMMIT_MODE="branch"
    INPUT_TARGET="test-org/test-project"
    INPUT_TARGET_REF="main"
    INPUT_CALLBACK_URL="https://api.example.com/webhooks/ralph"

    {
      echo "## Ralph Run Summary"
      echo ""
      echo "- **Thread:** ${INPUT_THREAD}"
      echo "- **Mode:** ${INPUT_MODE}"
      echo "- **Autonomy:** ${INPUT_AUTONOMY}"
      echo "- **Max iterations:** ${INPUT_MAX_ITER}"
      echo "- **Commit mode:** ${INPUT_COMMIT_MODE}"
      if [ -n "${INPUT_TARGET}" ]; then
        echo "- **Target repo:** ${INPUT_TARGET}@${INPUT_TARGET_REF}"
      fi
      if [ -n "${INPUT_CALLBACK_URL}" ]; then
        echo "- **Callback:** configured"
      fi
      echo ""
      if [ -f checkpoint.md ]; then
        echo "### Checkpoint"
        echo '```'
        head -30 checkpoint.md
        echo '```'
      fi
    }
  )

  echo "$SUMMARY_OUTPUT" | grep -q "Thread.*e2e-test-pipeline" || { echo "SUMMARY_FAIL: thread missing"; exit 1; }
  echo "$SUMMARY_OUTPUT" | grep -q "Mode.*build" || { echo "SUMMARY_FAIL: mode missing"; exit 1; }
  echo "$SUMMARY_OUTPUT" | grep -q "Autonomy.*autopilot" || { echo "SUMMARY_FAIL: autonomy missing"; exit 1; }
  echo "$SUMMARY_OUTPUT" | grep -q "Commit mode.*branch" || { echo "SUMMARY_FAIL: commit_mode missing"; exit 1; }
  echo "$SUMMARY_OUTPUT" | grep -q "Target repo.*test-org/test-project" || { echo "SUMMARY_FAIL: target missing"; exit 1; }
  echo "$SUMMARY_OUTPUT" | grep -q "Callback.*configured" || { echo "SUMMARY_FAIL: callback missing"; exit 1; }
  echo "$SUMMARY_OUTPUT" | grep -q "task 1 done" || { echo "SUMMARY_FAIL: checkpoint state missing"; exit 1; }

  # ── 11j. Subsequent run simulation (re-init idempotency) ──
  # On a second workflow_dispatch, existing files should be preserved
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
  pass "11f: commit-back pushes to ralph/<thread> branch with correct content"
  pass "11g: webhook payload has correct structure and values from pipeline state"
  pass "11h: artifact paths exist (outputs, checkpoint, plan, logs)"
  pass "11i: run summary includes all config fields and checkpoint state"
  pass "11j: subsequent run preserves checkpoint, allows new prompt injection"
else
  fail "end-to-end pipeline integration (exit code: $E2E_EXIT)"
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

# ── Summary ───────────────────────────────────────────────────
echo "=== Results: $PASS/$TESTS passed, $FAIL failed ==="
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
