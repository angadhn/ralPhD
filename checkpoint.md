# Checkpoint — Fix headless auth for Max plan (OAuth) users

**Thread:** fix-headless-oauth-fallback
**Last updated:** 2026-03-13
**Last agent:** plan
**Status:** planned — ready to execute

## Knowledge State

| Task | Status | Notes |
|------|--------|-------|
| 1. Create `tools/cli.py` | done | CLI dispatcher for ralph tools via Bash |
| 2. Create `templates/tool-via-bash.md` | pending | System prompt template for tool-via-bash instructions |
| 3. Add helpers to `lib/exec.sh` | pending | `build_claude_system_prompt`, `has_anthropic_api_key`, `is_anthropic_model` |
| 4. Auth branch in `ralph-loop.sh` pipe mode | pending | Main fallback logic |
| 5. Auth branch in `run_parallel_phase()` | pending | Same fallback for parallel execution |
| 6. Validate usage JSON parsing | pending | Ensure `claude -p` JSON output is compatible |
| 7. Update `providers.py` error messages | pending | Mention fallback in error text |

## Last Reflection

<none yet>

## Next Task

2. Create `templates/tool-via-bash.md` — System prompt appendix telling Claude Code how to invoke ralph custom tools via Bash. — **coder**
