# Checkpoint — ralph-as-engine

**Thread:** ralph-as-engine
**Last updated:** 2026-03-11
**Last agent:** coder
**Status:** Phase 1 in progress (task 3 done)

## Knowledge State

| Task | Status | Notes |
|------|--------|-------|
| 1. Archive all per-thread files | done | archive.sh now handles agent outputs, reflections, inbox |
| 2. Audit for other stale files | done | CHANGELOG.md archived+reset, /tmp/ralph-* cleaned |
| 3. GitHub Actions workflow | done | `.github/workflows/ralph-run.yml` — workflow_dispatch with 7 inputs |
| 4. .ralph init step | pending | template copying for new repos (already partially in workflow step 5) |
| 5. Local workflow test | pending | verify with act or test repo |
| 6. ralph-loop.sh path audit | pending | RALPH_HOME separation |
| 7. Agent prompt path audit | pending | specs/templates via RALPH_HOME |
| 8. ralph_agent.py path audit | pending | tool resolution from RALPH_HOME |
| 9. Commit-back step | pending | push AI outputs to project repo |
| 10. Webhook callback step | pending | summary delivery to Howler |
| 11. API contract docs | pending | workflow_dispatch interface |
| 12. End-to-end test | pending | full integration verification |
| 13. README updates | pending | 12-agent system + Actions docs |

## Last Reflection

Task 3 completed: Created `.github/workflows/ralph-run.yml` with workflow_dispatch trigger. The workflow accepts thread, prompt, autonomy, target_repo, target_ref, max_iterations, and loop_mode inputs. It checks out ralPhD as RALPH_HOME and the target project as workspace, runs init-project.sh if needed, writes the prompt to inbox.md, and runs ralph-loop.sh in pipe mode. Outputs uploaded as artifacts with job summary.

Note: Task 4 (init step) is largely already handled by step 5 of the workflow ("Initialize workspace with ralph") which calls init-project.sh. May be a quick task or can be merged.

## Next Task

4. Add a `.ralph` init step to the workflow — **coder**
