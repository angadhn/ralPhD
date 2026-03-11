# API Contract — `ralph-run.yml` workflow_dispatch

How to trigger ralPhD as an engine from external systems (GitHub API,
Howler edge functions, `gh` CLI). This documents the contract between
the caller and the `.github/workflows/ralph-run.yml` workflow.

---

## Trigger

**Event:** `workflow_dispatch`
**Endpoint:** `POST /repos/{owner}/{repo}/actions/workflows/ralph-run.yml/dispatches`
**Auth:** GitHub token with `actions:write` scope on the ralPhD repo.

```bash
# gh CLI
gh workflow run ralph-run.yml \
  -f thread="my-thread" \
  -f prompt="Write the introduction section" \
  -f autonomy="stage-gates" \
  -f target_repo="org/my-paper" \
  -f max_iterations="5"
```

```javascript
// GitHub API (from Howler edge function)
await octokit.actions.createWorkflowDispatch({
  owner: "you",
  repo: "ralPhD",
  workflow_id: "ralph-run.yml",
  ref: "main",
  inputs: {
    thread: "my-thread",
    prompt: "Write the introduction section",
    autonomy: "stage-gates",
    target_repo: "org/my-paper",
    max_iterations: "5"
  }
});
```

---

## Inputs

| Input | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `thread` | string | **yes** | — | Thread name. Used for checkpoint identification, output directory (`ai-generated-outputs/<thread>/`), and commit branch naming (`ralph/<thread>`). Must be URL-safe. |
| `prompt` | string | **yes** | — | Task prompt or planning instruction. Written to `inbox.md` in the workspace so the dispatcher picks it up as operator input. |
| `autonomy` | choice | no | `stage-gates` | Controls how far the loop runs without pausing. Options: `autopilot` (run all tasks), `stage-gates` (pause at phase boundaries), `step-by-step` (pause after every task). |
| `target_repo` | string | no | `""` | Target project repo in `owner/name` format. When empty, ralPhD runs against itself. When set, the repo is checked out as the workspace and ralPhD runs as the engine (`RALPH_HOME`). |
| `target_ref` | string | no | `main` | Branch or ref of the target repo to check out. |
| `max_iterations` | string | no | `5` | Safety cap on loop iterations. The loop exits after this many iterations even if work remains. |
| `loop_mode` | choice | no | `build` | `build` executes tasks from the implementation plan. `plan` generates/refines the implementation plan. |
| `commit_mode` | choice | no | `branch` | How to push results back to the target repo. `branch` pushes to `ralph/<thread>`, `direct` pushes to `target_ref`, `none` skips pushing (artifact only). Ignored when `target_repo` is empty. |
| `callback_url` | string | no | `""` | Webhook URL. When set, a JSON summary is POSTed here after the run completes (success or failure). See [Webhook Callback](#webhook-callback) below. |

### Input constraints

- `thread`: no spaces, no slashes. Used in branch names and directory paths.
- `prompt`: any UTF-8 string. Written as-is to `inbox.md`.
- `max_iterations`: string representation of an integer (GitHub Actions limitation — all inputs are strings).
- `target_repo`: must be accessible with the `TARGET_REPO_TOKEN` secret.
- `callback_url`: must be an HTTPS URL reachable from GitHub Actions runners.

---

## Secrets & Variables

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `ANTHROPIC_API_KEY` | secret | **yes** | API key for Claude. Used by `ralph_agent.py`. |
| `TARGET_REPO_TOKEN` | secret | conditional | GitHub PAT with `contents:write` on the target repo. Required when `target_repo` is set. |
| `CALLBACK_SECRET` | secret | no | HMAC-SHA256 key for signing webhook payloads. When set, the `X-Ralph-Signature` header is included. |
| `CLAUDE_MODEL` | variable | no | Model name override. Defaults to `claude-sonnet-4-6` if not set. |

---

## Expected Repo Structure

### Target repo (workspace) — first run

The workspace needs **no** pre-existing ralph files. On first run, the workflow's
init step (`init-project.sh --ci`) creates everything:

```
workspace/
├── checkpoint.md               # From templates/checkpoint.md
├── implementation-plan.md      # From templates/implementation-plan.md
├── inbox.md                    # Created, populated with prompt input
├── iteration_count             # Set to 0
├── specs/                      # Copied from RALPH_HOME/specs/
├── templates/                  # Copied from RALPH_HOME/templates/
├── .claude/agents/             # Copied from RALPH_HOME/.claude/agents/
└── (standard directories)      # ai-generated-outputs/, papers/, corpus/, etc.
```

The init step then injects the `thread`, `prompt`, and `autonomy` values into
the copied templates (replacing `<thread-name>`, `<date>`, etc.).

### Target repo — subsequent runs

On subsequent runs (when `checkpoint.md` and `implementation-plan.md` already exist),
the init step:

1. Skips `init-project.sh` (files exist)
2. Still injects `prompt` into `inbox.md` (overwritten each run)
3. Still injects `autonomy` into `implementation-plan.md` (updated in place)
4. Template placeholders (`<thread-name>`, `<date>`) are replaced only if still present

This means agents resume from where they left off — `checkpoint.md` carries the
state from the previous run.

### ralPhD repo (engine)

The ralPhD repo is checked out to `ralph-home/` and referenced via `RALPH_HOME`.
No modifications are made to it during the run. The engine provides:

- `ralph-loop.sh` — the iteration loop
- `ralph_agent.py` — the Python agent runner
- `.claude/agents/` — agent prompt files
- `tools/` — tool implementations
- `scripts/` — helper scripts
- `specs/` — quality standards (copied to workspace on first init)
- `templates/` — starter files (copied to workspace on first init)

---

## Outputs

### 1. Committed changes (target repo)

When `commit_mode` is `branch` or `direct` and `target_repo` is set:

- All agent-produced files are committed with author `ralph[bot] <ralph-bot@users.noreply.github.com>`
- Branch mode: pushed to `ralph/<thread>` (force push)
- Direct mode: pushed to `target_ref` (fast-forward)
- Files typically modified: `checkpoint.md`, `implementation-plan.md`, `CHANGELOG.md`,
  `ai-generated-outputs/`, `sections/`, `references/`, `figures/`

### 2. Artifacts

Always uploaded (even when `commit_mode=none`):

- **Name:** `ralph-outputs-<thread>`
- **Retention:** 30 days
- **Contents:**
  - `ai-generated-outputs/` — all agent outputs
  - `checkpoint.md` — final state
  - `implementation-plan.md` — updated plan
  - `logs/` — usage tracking (`usage.jsonl`)

### 3. Run summary

A markdown summary is written to `$GITHUB_STEP_SUMMARY`, visible on the
Actions run page. Includes thread info, config, checkpoint state, and
whether human review was requested.

### 4. HUMAN_REVIEW_NEEDED.md

When an agent encounters something requiring human judgment (or when
`autonomy=step-by-step` / `stage-gates` hits a boundary), this file is
created in the workspace. The webhook payload's `result.review_needed`
field reflects this.

---

## Webhook Callback

When `callback_url` is set, the workflow POSTs a JSON payload **after every run**
(success or failure — uses `if: always()`).

### Request

```
POST <callback_url>
Content-Type: application/json
User-Agent: ralph-bot/1.0
X-Ralph-Signature: sha256=<hex-digest>   (only when CALLBACK_SECRET is set)
```

### Signature verification

When `CALLBACK_SECRET` is configured, the payload is signed with HMAC-SHA256:

```
signature = HMAC-SHA256(CALLBACK_SECRET, raw_json_body)
header = "sha256=" + hex(signature)
```

Verify by recomputing the HMAC over the raw request body and comparing with
the `X-Ralph-Signature` header value.

```javascript
// Node.js verification example
const crypto = require('crypto');
const expected = crypto.createHmac('sha256', CALLBACK_SECRET)
  .update(rawBody)
  .digest('hex');
const received = req.headers['x-ralph-signature']?.replace('sha256=', '');
const valid = crypto.timingSafeEqual(
  Buffer.from(expected), Buffer.from(received)
);
```

### Payload schema

```jsonc
{
  "event": "ralph.run.completed",       // always this value
  "timestamp": "2026-03-11T14:30:00Z",  // ISO 8601 UTC

  "thread": "my-thread",                // from input
  "status": "completed",                // "completed" or "review_needed"

  "config": {
    "mode": "build",                     // loop_mode input
    "autonomy": "stage-gates",           // autonomy input
    "max_iterations": 5,                 // number
    "target_repo": "org/my-paper",       // "" if self
    "target_ref": "main",
    "commit_mode": "branch"
  },

  "result": {
    "last_agent": "paper-writer",        // from checkpoint.md
    "next_task": "12. Review ...",       // next task from checkpoint
    "tasks_done": 8,                     // count from Knowledge State table
    "tasks_total": 13,                   // count from Knowledge State table
    "review_needed": false,              // true if HUMAN_REVIEW_NEEDED.md exists
    "review_body": null,                 // contents of HUMAN_REVIEW_NEEDED.md or null
    "checkpoint_summary": "..."          // first 20 lines of checkpoint.md
  },

  "run": {
    "id": "12345678",                    // GITHUB_RUN_ID
    "url": "https://github.com/you/ralPhD/actions/runs/12345678"
  }
}
```

### Retry behavior

- 3 attempts, 5 seconds between retries
- Uses `curl -sf` (fail silently on HTTP errors)
- Non-fatal: callback failure does not fail the workflow run

---

## Run Lifecycle

```
1. Check out ralPhD → ralph-home/
2. Check out target repo → workspace/    (or symlink ralph-home)
3. Set up Python 3.11 + dependencies
4. Install system tools (jq)
5. Initialize workspace:
   a. Run init-project.sh --ci (if first run)
   b. Inject thread/date into templates
   c. Write prompt to inbox.md
   d. Set autonomy in implementation-plan.md
   e. Configure git user as ralph[bot]
6. Run ralph-loop.sh -p <mode> <max_iterations>
   └─ Each iteration: dispatcher → agent → commit → repeat
7. Commit results back to target repo (if commit_mode != none)
8. POST webhook callback (if callback_url set)
9. Upload artifacts
10. Generate run summary
```

Steps 8-10 run with `if: always()` — they execute even if the loop fails.

---

## Error Handling

| Scenario | Behavior |
|----------|----------|
| Loop hits max_iterations | Exits normally. Checkpoint shows remaining work. Webhook status = `completed`. |
| Agent writes HUMAN_REVIEW_NEEDED.md | Loop pauses. Webhook status = `review_needed`. Next run can resume. |
| Agent crashes mid-iteration | Loop exits with error. Webhook still fires (always). Artifact still uploaded. |
| Target repo push fails | Step fails but webhook + artifact still execute. |
| Webhook delivery fails | Retried 3x. Non-fatal — run still succeeds. |
| ANTHROPIC_API_KEY missing | ralph_agent.py fails immediately. Webhook fires with error context. |
| TARGET_REPO_TOKEN missing | Checkout step fails. No agent work is done. |

---

## Concurrency

The workflow does **not** set a concurrency group by default. If you need to
prevent parallel runs on the same thread, add to the caller or fork the workflow:

```yaml
concurrency:
  group: ralph-${{ inputs.thread }}
  cancel-in-progress: false
```

---

## Examples

### Minimal trigger — run against self

```bash
gh workflow run ralph-run.yml \
  -f thread="cleanup" \
  -f prompt="Archive stale files and update README"
```

### Full trigger — external repo with callback

```bash
gh workflow run ralph-run.yml \
  -f thread="intro-draft" \
  -f prompt="Write the introduction section based on the synthesizer outline" \
  -f autonomy="autopilot" \
  -f target_repo="myorg/climate-paper" \
  -f target_ref="draft-v2" \
  -f max_iterations="10" \
  -f loop_mode="build" \
  -f commit_mode="branch" \
  -f callback_url="https://api.howler.app/webhooks/ralph"
```

### Plan mode — generate implementation plan

```bash
gh workflow run ralph-run.yml \
  -f thread="research-plan" \
  -f prompt="Plan a systematic review of transformer attention mechanisms" \
  -f loop_mode="plan" \
  -f max_iterations="3"
```

### Howler edge function (TypeScript)

```typescript
import { Octokit } from "@octokit/rest";

export async function triggerRalph(params: {
  thread: string;
  prompt: string;
  targetRepo: string;
  callbackUrl: string;
}) {
  const octokit = new Octokit({ auth: process.env.GITHUB_TOKEN });

  const { data } = await octokit.actions.createWorkflowDispatch({
    owner: "your-org",
    repo: "ralPhD",
    workflow_id: "ralph-run.yml",
    ref: "main",
    inputs: {
      thread: params.thread,
      prompt: params.prompt,
      target_repo: params.targetRepo,
      callback_url: params.callbackUrl,
      autonomy: "autopilot",
      max_iterations: "10",
      commit_mode: "branch",
    },
  });

  // workflow_dispatch returns 204 No Content on success
  // Poll for run status or wait for webhook callback
}
```

### Webhook receiver (Express)

```typescript
import crypto from "crypto";
import express from "express";

const app = express();
app.use(express.raw({ type: "application/json" }));

app.post("/webhooks/ralph", (req, res) => {
  // Verify signature
  const secret = process.env.CALLBACK_SECRET;
  if (secret) {
    const sig = req.headers["x-ralph-signature"];
    const expected = "sha256=" +
      crypto.createHmac("sha256", secret).update(req.body).digest("hex");
    if (!crypto.timingSafeEqual(Buffer.from(sig ?? ""), Buffer.from(expected))) {
      return res.status(401).send("Invalid signature");
    }
  }

  const payload = JSON.parse(req.body);
  console.log(`Ralph run completed: ${payload.thread}`);
  console.log(`  Status: ${payload.status}`);
  console.log(`  Progress: ${payload.result.tasks_done}/${payload.result.tasks_total}`);
  console.log(`  Next: ${payload.result.next_task}`);

  if (payload.result.review_needed) {
    // Surface to user in Howler chat
    notifyUser(payload.thread, payload.result.review_body);
  }

  res.status(200).send("OK");
});
```
