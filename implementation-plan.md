# Implementation Plan — Archive & Template Support

**Thread:** archive-support
**Created:** 2026-03-10

## Tasks

- [x] 1. Create `templates/` directory with `checkpoint.md` and `implementation-plan.md` copied from current root blanks — **HUMAN CHECKPOINT**
- [x] 2. Write `scripts/archive.sh` — reads thread name + date from checkpoint, creates `archive/YYYY-MM-DD_thread/`, moves `checkpoint.md` + `implementation-plan.md` there, copies templates back to root, resets `iteration_count` — **research-coder**
- [x] 3. Update `prompt-plan.md` — add step before planning: check if `implementation-plan.md` has all tasks checked off; if so, ask user whether to archive before proceeding; if yes, run `./scripts/archive.sh` — **paper-writer**
- [x] 4. Create `archive/.gitkeep` so the directory is tracked in git — **HUMAN CHECKPOINT**
- [ ] 5. Meta-test: run `./ralph-loop.sh plan` — plan mode should detect this plan is complete, offer to archive it, and archive to `archive/2026-03-10_archive-support/` — **HUMAN CHECKPOINT**
