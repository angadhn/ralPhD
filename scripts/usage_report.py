#!/usr/bin/env python3
"""
usage_report.py — Token usage and cost report for Ralph loop runs.

Reads logs/usage.jsonl and produces a summary table showing per-iteration
token counts, costs, and cumulative totals.

Usage:
  python scripts/usage_report.py                  # Full report
  python scripts/usage_report.py --last 10        # Last 10 iterations
  python scripts/usage_report.py --by-agent       # Totals grouped by agent
  python scripts/usage_report.py --csv            # CSV output
  python scripts/usage_report.py --markdown        # Markdown table
  python scripts/usage_report.py --log FILE       # Use a different log file
"""

import argparse
import json
import sys
from pathlib import Path
from datetime import datetime

# Anthropic pricing (per million tokens) as of 2025-02
# Source: https://docs.anthropic.com/en/docs/about-claude/models
PRICING = {
    "claude-opus-4-6": {
        "input": 15.00,
        "cache_read": 1.50,
        "cache_create": 18.75,
        "output": 75.00,
    },
    "claude-sonnet-4-6": {
        "input": 3.00,
        "cache_read": 0.30,
        "cache_create": 3.75,
        "output": 15.00,
    },
    "claude-haiku-4-5-20251001": {
        "input": 0.80,
        "cache_read": 0.08,
        "cache_create": 1.00,
        "output": 4.00,
    },
}

DEFAULT_LOG = Path(__file__).resolve().parent.parent / "logs" / "usage.jsonl"


def load_entries(log_path: Path) -> list[dict]:
    if not log_path.exists():
        return []
    entries = []
    with open(log_path) as f:
        for line_no, line in enumerate(f, 1):
            line = line.strip()
            if not line:
                continue
            try:
                entries.append(json.loads(line))
            except json.JSONDecodeError:
                print(f"Warning: skipping malformed line {line_no}", file=sys.stderr)
    return entries


def estimate_cost(entry: dict) -> float:
    """Estimate cost from token counts using pricing table.

    If the entry already has cost_usd from Claude CLI, return that.
    Otherwise compute from token counts and pricing table.
    """
    if entry.get("cost_usd") is not None:
        return entry["cost_usd"]

    model = entry.get("model", "")
    pricing = None
    for key in PRICING:
        if key in model:
            pricing = PRICING[key]
            break
    if pricing is None:
        # Unknown model — can't estimate
        return 0.0

    input_tok = entry.get("input_tokens", 0)
    cache_read = entry.get("cache_read_input_tokens", 0)
    cache_create = entry.get("cache_creation_input_tokens", 0)
    output_tok = entry.get("output_tokens", 0)

    cost = (
        (input_tok / 1_000_000) * pricing["input"]
        + (cache_read / 1_000_000) * pricing["cache_read"]
        + (cache_create / 1_000_000) * pricing["cache_create"]
        + (output_tok / 1_000_000) * pricing["output"]
    )
    return cost


def fmt_tokens(n: int) -> str:
    if n >= 1_000_000:
        return f"{n / 1_000_000:.1f}M"
    if n >= 1_000:
        return f"{n / 1_000:.1f}k"
    return str(n)


def print_table(entries: list[dict], fmt: str = "text"):
    if not entries:
        print("No usage data found.")
        return

    headers = ["Iter", "Agent", "Mode", "Input", "Cache R", "Cache W", "Output", "Cost", "Cumul."]
    rows = []
    cumulative = 0.0

    for e in entries:
        cost = estimate_cost(e)
        cumulative += cost
        rows.append([
            str(e.get("iteration", "?")),
            e.get("agent", "?"),
            e.get("loop_mode", "?"),
            fmt_tokens(e.get("input_tokens", 0)),
            fmt_tokens(e.get("cache_read_input_tokens", 0)),
            fmt_tokens(e.get("cache_creation_input_tokens", 0)),
            fmt_tokens(e.get("output_tokens", 0)),
            f"${cost:.4f}",
            f"${cumulative:.4f}",
        ])

    if fmt == "csv":
        print(",".join(headers))
        for row in rows:
            print(",".join(row))
        return

    # Compute column widths
    widths = [len(h) for h in headers]
    for row in rows:
        for i, cell in enumerate(row):
            widths[i] = max(widths[i], len(cell))

    sep = "  "
    if fmt == "markdown":
        header_line = "| " + " | ".join(h.ljust(widths[i]) for i, h in enumerate(headers)) + " |"
        divider = "| " + " | ".join("-" * widths[i] for i in range(len(headers))) + " |"
        print(header_line)
        print(divider)
        for row in rows:
            print("| " + " | ".join(cell.ljust(widths[i]) for i, cell in enumerate(row)) + " |")
    else:
        header_line = sep.join(h.ljust(widths[i]) for i, h in enumerate(headers))
        divider = sep.join("-" * widths[i] for i in range(len(headers)))
        print(header_line)
        print(divider)
        for row in rows:
            print(sep.join(cell.ljust(widths[i]) for i, cell in enumerate(row)))

    # Summary
    total_input = sum(e.get("input_tokens", 0) for e in entries)
    total_cache_read = sum(e.get("cache_read_input_tokens", 0) for e in entries)
    total_cache_create = sum(e.get("cache_creation_input_tokens", 0) for e in entries)
    total_output = sum(e.get("output_tokens", 0) for e in entries)

    print()
    print(f"Iterations: {len(entries)}")
    print(f"Total input: {fmt_tokens(total_input)}  cache read: {fmt_tokens(total_cache_read)}  cache write: {fmt_tokens(total_cache_create)}  output: {fmt_tokens(total_output)}")
    print(f"Total cost:  ${cumulative:.4f}")


def print_by_agent(entries: list[dict], fmt: str = "text"):
    if not entries:
        print("No usage data found.")
        return

    agents: dict[str, dict] = {}
    for e in entries:
        agent = e.get("agent", "unknown")
        if agent not in agents:
            agents[agent] = {
                "count": 0, "input_tokens": 0, "cache_read_input_tokens": 0,
                "cache_creation_input_tokens": 0, "output_tokens": 0, "cost": 0.0,
            }
        a = agents[agent]
        a["count"] += 1
        a["input_tokens"] += e.get("input_tokens", 0)
        a["cache_read_input_tokens"] += e.get("cache_read_input_tokens", 0)
        a["cache_creation_input_tokens"] += e.get("cache_creation_input_tokens", 0)
        a["output_tokens"] += e.get("output_tokens", 0)
        a["cost"] += estimate_cost(e)

    headers = ["Agent", "Iters", "Input", "Cache R", "Cache W", "Output", "Cost"]
    rows = []
    for agent, a in sorted(agents.items(), key=lambda x: -x[1]["cost"]):
        rows.append([
            agent, str(a["count"]),
            fmt_tokens(a["input_tokens"]),
            fmt_tokens(a["cache_read_input_tokens"]),
            fmt_tokens(a["cache_creation_input_tokens"]),
            fmt_tokens(a["output_tokens"]),
            f"${a['cost']:.4f}",
        ])

    widths = [len(h) for h in headers]
    for row in rows:
        for i, cell in enumerate(row):
            widths[i] = max(widths[i], len(cell))

    sep = "  "
    if fmt == "markdown":
        print("| " + " | ".join(h.ljust(widths[i]) for i, h in enumerate(headers)) + " |")
        print("| " + " | ".join("-" * widths[i] for i in range(len(headers))) + " |")
        for row in rows:
            print("| " + " | ".join(cell.ljust(widths[i]) for i, cell in enumerate(row)) + " |")
    else:
        print(sep.join(h.ljust(widths[i]) for i, h in enumerate(headers)))
        print(sep.join("-" * widths[i] for i in range(len(headers))))
        for row in rows:
            print(sep.join(cell.ljust(widths[i]) for i, cell in enumerate(row)))

    total_cost = sum(a["cost"] for a in agents.values())
    print(f"\nTotal: ${total_cost:.4f} across {len(entries)} iterations")


def main():
    parser = argparse.ArgumentParser(description="Ralph token usage and cost report")
    parser.add_argument("--log", type=Path, default=DEFAULT_LOG, help="Path to usage.jsonl")
    parser.add_argument("--last", type=int, metavar="N", help="Show only last N iterations")
    parser.add_argument("--by-agent", action="store_true", help="Group totals by agent")
    parser.add_argument("--csv", action="store_true", help="Output as CSV")
    parser.add_argument("--markdown", action="store_true", help="Output as markdown table")
    args = parser.parse_args()

    entries = load_entries(args.log)
    if args.last:
        entries = entries[-args.last:]

    fmt = "csv" if args.csv else "markdown" if args.markdown else "text"

    if args.by_agent:
        print_by_agent(entries, fmt)
    else:
        print_table(entries, fmt)


if __name__ == "__main__":
    main()
