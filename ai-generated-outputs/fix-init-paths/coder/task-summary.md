# Task Summary — Phase 1: Fix PROJECT_ROOT derivation in init-project.sh

## Files Changed

| File | Change |
|------|--------|
| `scripts/init-project.sh` | Fix PROJECT_ROOT derivation + dangling symlink detection |
| `tests/test-workflow-local.sh` | Add test 15d — Quick Start B cross-directory init |

## What Was Done

### 1. PROJECT_ROOT derivation (scripts/init-project.sh)

Replaced `PROJECT_ROOT="$(pwd)"` (line 39) with logic that derives PROJECT_ROOT
from WORKSPACE after canonicalization:

```bash
if [ "$(basename "$WORKSPACE")" = ".ralph" ]; then
  PROJECT_ROOT="$(dirname "$WORKSPACE")"
else
  PROJECT_ROOT="$WORKSPACE"
fi
```

The assignment was moved to after `WORKSPACE="$(cd "$WORKSPACE" && pwd)"` so
WORKSPACE is already absolute when the heuristic runs. The CI_MODE override
(`PROJECT_ROOT="$WORKSPACE"`) remains unchanged.

**Result:** Quick Start B (`init-project.sh ~/research/my-paper` from any cwd)
now creates content dirs in `~/research/my-paper/`, not in cwd.

### 2. Dangling symlink detection (scripts/init-project.sh)

Changed content symlink creation from `[ ! -e "$link" ]` to
`[ -L "$link" ] || [ ! -e "$link" ]` with `rm -f "$link"` before re-creating.
Applied to both the content-dirs loop and the `inputs` symlink.

**Result:** Dangling symlinks are now replaced on re-init instead of silently
causing `ln -s` failures under `set -euo pipefail`.

### 3. Test 15d — Quick Start B (tests/test-workflow-local.sh)

Added test 15d that:
1. Runs `init-project.sh $LOCAL_QSB` from `/tmp` (different cwd)
2. Verifies all content dirs exist inside `$LOCAL_QSB/`
3. Verifies no content dirs were created in `/tmp/`
4. Verifies `ralphd` and `.ralphrc` exist in `$LOCAL_QSB/`

## Test Results

160/161 passed. 1 pre-existing failure (`tools/__init__.py` registry check)
unrelated to this change (confirmed by running tests before and after).
All test 15 and 15d assertions pass.
