# Checkpoint — Fix headless auth for Max plan (OAuth) users

**Thread:** fix-headless-oauth-fallback
**Last updated:** 2026-03-13
**Last agent:** coder
**Last iteration:** task 6 validation
**Status:** complete — all 7 tasks done

## Knowledge State

| Task | Status | Notes |
|------|--------|-------|
| 1. Create `tools/cli.py` | done | CLI dispatcher for ralph tools via Bash |
| 2. Create `templates/tool-via-bash.md` | done | System prompt appendix for `claude -p` fallback; `{{RALPH_TOOLS}}` placeholder |
| 3. Add helpers to `lib/exec.sh` | done | `build_claude_system_prompt`, `has_anthropic_api_key`, `is_anthropic_model` |
| 4. Auth branch in `ralph-loop.sh` pipe mode | done | Auth-detection + claude -p fallback in pipe mode |
| 5. Auth branch in `run_parallel_phase()` | done | Same fallback per-task in parallel spawn loop |
| 6. Validate usage JSON parsing | done | `claude -p --output-format json` is fully compatible; no code changes needed |
| 7. Update `providers.py` error messages | done | All 3 error paths now mention ralph-loop.sh automatic fallback |

## Last Reflection

Iter-20 (2026-03-13): on track. Tasks 1-2 committed cleanly; foundation for oauth fallback is in place. Proceeding with task 3 (shell helpers in lib/exec.sh) as planned — correct sequence before integrating into execution paths.

## Next Task

All tasks complete. Thread ready to archive.
