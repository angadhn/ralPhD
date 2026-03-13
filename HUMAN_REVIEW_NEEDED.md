# Human Review Needed — Phase 3 → 4 Gate

## What was completed (Phases 1–3)

**Phase 1** — Fixed `PROJECT_ROOT` derivation in `init-project.sh`: derived from WORKSPACE argument (not `pwd`), fixed dangling symlink detection.

**Phase 2** — Symlinked `.claude/agents/` to `RALPH_HOME` in local mode; added self-healing for `.claude/agents` in the embedded ralphd launcher.

**Phase 3** — Fixed ralphd launcher cwd and self-healing:
- Added `cd "$SCRIPT_DIR"` before `exec ralph-loop.sh` so all relative paths resolve against the workspace
- Removed `basename = .ralph` guard from content symlink self-healing so it works for any workspace directory name

All phases: 160/161 tests pass (1 pre-existing failure unrelated to these changes).

## What Phase 4 will do

**Phase 4** — Update README and api-contract layout docs:
- Update Quick Start B in README.md to clarify content dirs are created inside the workspace (not cwd)
- Update directory tree in `specs/api-contract.md` to reflect that split layout only applies to brownfield `.ralph/` case (Quick Start C), not Quick Start B
- Verify Quick Start A (run from ralPhD repo) is unaffected

## Files to be modified in Phase 4

- `README.md`
- `specs/api-contract.md`
