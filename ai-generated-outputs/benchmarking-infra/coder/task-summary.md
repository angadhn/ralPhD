# Task Summary — Task 13: Per-agent model config

## Changes

### context-budgets.json
- Added `"model"` field to all 12 agents
- Reasoning-heavy agents (critic, deep-reader, paper-writer, provocateur, synthesizer, editor, coherence-reviewer) → `claude-opus-4-6`
- Mechanical/code agents (scout, triage, research-coder, figure-stylist, coder) → `claude-sonnet-4-6`
- Added missing agents (triage, provocateur, synthesizer, editor, coherence-reviewer, coder) that previously had no budget entry

### ralph-loop.sh
- Added `resolve_model()` function: reads per-agent model from context-budgets.json, falls back to `$CLAUDE_MODEL` env var, then to `claude-opus-4-6` default
- Updated 3 call sites (parallel mode, pipe mode, interactive mode) to use `resolve_model` instead of hardcoded `${CLAUDE_MODEL:-claude-opus-4-6}`

### ralph_agent.py
- No changes needed — already accepts `--model` from CLI. The loop resolves the model and passes it via `--model`.

## Files Changed
| File | Action |
|------|--------|
| `context-budgets.json` | MODIFIED — added model field to all agents, added 6 missing agent entries |
| `ralph-loop.sh` | MODIFIED — added resolve_model(), updated 3 call sites |
| `checkpoint.md` | MODIFIED — marked all tasks done |
| `implementation-plan.md` | MODIFIED — checked off task 13 |

## Test Results
- 116/116 passed, 0 failed
- resolve_model() verified: returns correct per-agent models, falls back for unknown agents
