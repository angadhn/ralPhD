# logs/

Runtime logs from the Ralph loop.

## Files

- `usage.jsonl` — One JSON line per iteration with token counts, cost, model, agent, and duration. Written by `ralph-loop.sh` after each iteration.

## Reporting

```bash
python3 scripts/usage_report.py        # Summary of token usage and costs
python3 scripts/usage_report.py -v     # Per-iteration breakdown
```
