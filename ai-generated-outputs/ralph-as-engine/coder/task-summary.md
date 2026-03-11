# Task 10 Summary — Webhook Callback Step

## What was done

Added an optional webhook/callback step to `ralph-run.yml` that POSTs a JSON summary to an external URL when a run completes. This enables Howler (or any external system) to receive results without polling.

## Changes

### `.github/workflows/ralph-run.yml`
- Added `callback_url` input (optional, default empty, type string)
- Added **Step 8: Webhook callback** between commit-back and upload steps
  - Runs on `always()` — fires even if the loop fails
  - Only runs when `callback_url` is non-empty
  - Builds a structured JSON payload via `jq` with:
    - Event type: `ralph.run.completed`
    - Thread name, status (`completed` or `review_needed`)
    - Config block (mode, autonomy, max_iterations, target, commit_mode)
    - Result block (last_agent, next_task, tasks_done/total, review_needed, checkpoint_summary)
    - Run metadata (run_id, run_url, timestamp)
  - HMAC-SHA256 signature via `CALLBACK_SECRET` secret (optional, sent as `X-Ralph-Signature` header)
  - 3 retries with 5s backoff; failure is non-fatal
  - Uses `curl -sf` for clean error handling
- Updated summary step (now step 10) to include callback info
- Fixed `LAST_AGENT` extraction: `sed 's/.*: *//'` → `sed 's/.*:\*\* *//'` to strip markdown bold markers

### `tests/test-workflow-local.sh`
- Added **Test 10: Webhook Callback Step** with 15 new test cases (10a-10j):
  - YAML input validation
  - Step conditions and env vars
  - Script content inspection (jq, curl, event type, HMAC, retry, non-fatal)
  - JSON payload simulation with field type verification
  - HMAC signature determinism test
  - review_needed payload variation
  - Summary step callback info
  - Step ordering verification

## Test results

**62/62 tests pass** (47 existing + 15 new webhook tests)

## JSON Payload Schema

```json
{
  "event": "ralph.run.completed",
  "timestamp": "2026-03-11T12:00:00Z",
  "thread": "my-thread",
  "status": "completed|review_needed",
  "config": {
    "mode": "build|plan",
    "autonomy": "autopilot|stage-gates|step-by-step",
    "max_iterations": 5,
    "target_repo": "owner/repo",
    "target_ref": "main",
    "commit_mode": "branch|direct|none"
  },
  "result": {
    "last_agent": "coder",
    "next_task": "11. Document API contract — coder",
    "tasks_done": 10,
    "tasks_total": 13,
    "review_needed": false,
    "review_body": null,
    "checkpoint_summary": "..."
  },
  "run": {
    "id": "12345",
    "url": "https://github.com/owner/repo/actions/runs/12345"
  }
}
```
