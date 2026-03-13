# Reflection — Iteration 20 — 2026-03-13

## Trajectory: on track

## Working
- New thread (fix-headless-oauth-fallback) started cleanly; tasks 1 and 2 committed without issues
- `tools/cli.py` provides a clean Bash-invocable dispatcher for ralph tools
- `templates/tool-via-bash.md` gives Claude Code the system prompt appendix it needs to call ralph tools via Bash
- Commit history is tidy; stage-gate pacing appropriate

## Not working
- Nothing wasting effort; the foundation (tasks 1-2) is in place and correct

## Next 5 iterations should focus on
1. Task 3: Add `build_claude_system_prompt()`, `has_anthropic_api_key()`, `is_anthropic_model()` to `lib/exec.sh`
2. Task 4: Auth-detection branch in `ralph-loop.sh` pipe mode
3. Task 5: Same fallback in `run_parallel_phase()` in `lib/exec.sh`
4. Task 6: Validate usage JSON parsing in `lib/post-run.sh`
5. Task 7: Update `providers.py` error messages

## Adjustments
None — proceed with Task 3 as planned. The implementation sequence is sound: build helpers first (task 3), then integrate them in execution paths (tasks 4-5), then validate output compatibility (task 6), then polish messaging (task 7).
