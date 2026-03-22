# Open Design Gaps

Residual design limitations identified during the 2026-03-22 bug fix session.
These are not active bugs — the concrete failure modes are fixed. These are
architectural improvements that would make the system more robust at scale.

## What was fixed

7 commits addressed 5 confirmed bugs:

| Bug | Fix | Commit |
|-----|-----|--------|
| Yield signal ignored by ralph_agent.py | `should_yield()` end-of-turn gate | `1e72b86` |
| Circuit breaker lost on Ctrl+C | Remove `$CB_FILE` from cleanup rm -f | `6eb70ed` |
| No context window tracking | `should_stop_for_context()` with input+output+tool estimate | `808a562`, `fa4e9b4`, `d089863` |
| Same-agent parallel collisions | `check_duplicate_agents()` fail-closed + `PARALLEL_TASK_IDX` | `496a230` |
| Lossy checkpoint merge | Write `merged_did`, keep all knowledge rows, harvest base state | `095615a`, `fa4e9b4` |

## What remains

### 1. Cross-agent output path collisions — [#1](https://github.com/angadhn/ralPhD/issues/1)

Same-agent collisions are prevented. Different agents writing to the same
path still cause merge abort + branch preservation. Full solution needs
output-path manifests or agent-level path declarations.

### 2. Arbitrary checkpoint section merging — [#2](https://github.com/angadhn/ralPhD/issues/2)

Known sections (Knowledge State, What I Did) are now properly merged.
Unknown sections and Last Reflection are still dropped/replaced during
parallel checkpoint reconciliation. A generic section-aware merge would
handle any section structure.

### 3. Heuristic token estimation — [#3](https://github.com/angadhn/ralPhD/issues/3)

Context guard uses ~4 chars/token approximation for tool results. Covers
the practical failure mode but could be replaced with tokenizer-accurate
counting for precision. Low priority.
