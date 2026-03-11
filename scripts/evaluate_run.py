#!/usr/bin/env python3
"""
evaluate_run.py — Aggregate eval.jsonl into run summaries and comparisons.

Reads logs/eval.jsonl and produces run-level statistics. Supports comparing
multiple runs (tagged by architecture mode) side by side.

Usage:
  python3 scripts/evaluate_run.py                          # Summary of all entries
  python3 scripts/evaluate_run.py --run-tag serial-run-1   # Summary for one run
  python3 scripts/evaluate_run.py --compare serial-run-1 parallel-run-1 single-run-1
  python3 scripts/evaluate_run.py --markdown               # Markdown table output
"""

import argparse
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = SCRIPT_DIR.parent
EVAL_LOG = PROJECT_ROOT / "logs" / "eval.jsonl"


def load_entries(log_path):
    """Load all eval.jsonl entries."""
    if not log_path.exists():
        return []
    entries = []
    with open(log_path) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                entries.append(json.loads(line))
            except json.JSONDecodeError:
                continue
    return entries


def filter_by_tag(entries, run_tag):
    """Filter entries to those matching a specific run tag."""
    return [e for e in entries if e.get("run_tag") == run_tag]


def compute_summary(entries):
    """Compute aggregate statistics for a set of eval entries."""
    if not entries:
        return None

    iterations = len(entries)
    tasks_completed = sum(1 for e in entries if e.get("task_completed", False))

    # Cost
    total_cost = sum(e.get("cost_usd", 0.0) for e in entries)
    cost_per_task = total_cost / tasks_completed if tasks_completed > 0 else 0.0

    # Duration
    total_duration_ms = sum(e.get("duration_ms", 0) for e in entries)

    # Wall-clock from timestamps
    timestamps = []
    for e in entries:
        ts = e.get("timestamp", "")
        if ts:
            for fmt in ("%Y-%m-%dT%H:%M:%S.%fZ", "%Y-%m-%dT%H:%M:%SZ",
                        "%Y-%m-%dT%H:%M:%S.%f%z", "%Y-%m-%dT%H:%M:%S%z"):
                try:
                    timestamps.append(datetime.strptime(ts, fmt).replace(tzinfo=timezone.utc))
                    break
                except ValueError:
                    continue
    wall_clock_ms = 0
    if len(timestamps) >= 2:
        wall_clock_ms = int((max(timestamps) - min(timestamps)).total_seconds() * 1000)

    # Quality gates
    quality_entries = [e for e in entries
                       if "language_check_pass" in e or "journal_check_pass" in e]
    quality_pass = sum(
        1 for e in quality_entries
        if e.get("language_check_pass", True) and e.get("journal_check_pass", True)
    )
    quality_pass_rate = quality_pass / len(quality_entries) if quality_entries else 1.0

    # Context
    context_pcts = [e.get("peak_context_pct", 0) for e in entries]
    avg_context = sum(context_pcts) / len(context_pcts) if context_pcts else 0
    context_yields = sum(1 for e in entries if e.get("context_yield", False))

    # Context distribution buckets
    buckets = {"0-20%": 0, "20-40%": 0, "40-55%": 0, "55%+": 0}
    for pct in context_pcts:
        if pct < 20:
            buckets["0-20%"] += 1
        elif pct < 40:
            buckets["20-40%"] += 1
        elif pct < 55:
            buckets["40-55%"] += 1
        else:
            buckets["55%+"] += 1

    # Productivity
    total_files = sum(e.get("files_changed", 0) for e in entries)
    total_lines_added = sum(e.get("lines_added", 0) for e in entries)
    total_lines_removed = sum(e.get("lines_removed", 0) for e in entries)

    # Tokens
    total_input_tokens = sum(e.get("input_tokens", 0) for e in entries)
    total_output_tokens = sum(e.get("output_tokens", 0) for e in entries)

    # Iterations per task
    iters_per_task = iterations / tasks_completed if tasks_completed > 0 else float("inf")

    # Arch mode (from first entry)
    arch_mode = entries[0].get("arch_mode", "unknown") if entries else "unknown"
    run_tag = entries[0].get("run_tag", "unknown") if entries else "unknown"

    return {
        "run_tag": run_tag,
        "arch_mode": arch_mode,
        "iterations": iterations,
        "tasks_completed": tasks_completed,
        "wall_clock_ms": wall_clock_ms,
        "total_duration_ms": total_duration_ms,
        "total_cost": total_cost,
        "cost_per_task": cost_per_task,
        "quality_pass_rate": quality_pass_rate,
        "iterations_per_task": iters_per_task,
        "avg_context_pct": avg_context,
        "context_yields": context_yields,
        "context_distribution": buckets,
        "total_files_changed": total_files,
        "total_lines_added": total_lines_added,
        "total_lines_removed": total_lines_removed,
        "total_input_tokens": total_input_tokens,
        "total_output_tokens": total_output_tokens,
    }


def fmt_duration(ms):
    """Format milliseconds as Xm Ys."""
    if ms <= 0:
        return "N/A"
    total_s = ms // 1000
    mins = total_s // 60
    secs = total_s % 60
    return "%dm %02ds" % (mins, secs)


def fmt_tokens(n):
    if n >= 1_000_000:
        return "%.1fM" % (n / 1_000_000)
    if n >= 1_000:
        return "%.1fk" % (n / 1_000)
    return str(n)


def fmt_ctx_dist(buckets):
    return ", ".join("%s: %d" % (k, v) for k, v in buckets.items())


def print_summary(summary, fmt="text"):
    """Print a single run summary."""
    if summary is None:
        print("No data.")
        return

    s = summary
    lines = [
        ("Run tag", s["run_tag"]),
        ("Architecture", s["arch_mode"]),
        ("Iterations", str(s["iterations"])),
        ("Tasks completed", "%d" % s["tasks_completed"]),
        ("Wall-clock time", fmt_duration(s["wall_clock_ms"])),
        ("Agent time", fmt_duration(s["total_duration_ms"])),
        ("Total cost", "$%.2f" % s["total_cost"]),
        ("Cost per task", "$%.2f" % s["cost_per_task"]),
        ("Quality pass rate", "%.2f" % s["quality_pass_rate"]),
        ("Iters per task", "%.2f" % s["iterations_per_task"]),
        ("Avg context %%", "%d%%" % int(s["avg_context_pct"])),
        ("Context yields", str(s["context_yields"])),
        ("Context distribution", fmt_ctx_dist(s["context_distribution"])),
        ("Files changed", str(s["total_files_changed"])),
        ("Lines +/-", "+%d / -%d" % (s["total_lines_added"], s["total_lines_removed"])),
        ("Tokens in/out", "%s / %s" % (fmt_tokens(s["total_input_tokens"]),
                                        fmt_tokens(s["total_output_tokens"]))),
    ]

    if fmt == "markdown":
        max_label = max(len(l[0]) for l in lines)
        print("| %-*s | Value |" % (max_label, "Metric"))
        print("| %s | ----- |" % ("-" * max_label))
        for label, val in lines:
            print("| %-*s | %s |" % (max_label, label, val))
    else:
        print("=== Run Summary: %s (%s) ===" % (s["run_tag"], s["arch_mode"]))
        max_label = max(len(l[0]) for l in lines)
        for label, val in lines:
            print("  %-*s  %s" % (max_label + 1, label + ":", val))


def print_comparison(summaries, fmt="text"):
    """Print side-by-side comparison of multiple runs."""
    if not summaries:
        print("No data to compare.")
        return

    tags = [s["run_tag"] for s in summaries]

    rows = [
        ("Architecture", [s["arch_mode"] for s in summaries]),
        ("Iterations", [str(s["iterations"]) for s in summaries]),
        ("Tasks completed", [str(s["tasks_completed"]) for s in summaries]),
        ("Wall-clock time", [fmt_duration(s["wall_clock_ms"]) for s in summaries]),
        ("Total cost", ["$%.2f" % s["total_cost"] for s in summaries]),
        ("Cost per task", ["$%.2f" % s["cost_per_task"] for s in summaries]),
        ("Quality pass rate", ["%.2f" % s["quality_pass_rate"] for s in summaries]),
        ("Iters per task", ["%.2f" % s["iterations_per_task"] for s in summaries]),
        ("Avg context %%", ["%d%%" % int(s["avg_context_pct"]) for s in summaries]),
        ("Context yields", [str(s["context_yields"]) for s in summaries]),
        ("Files changed", [str(s["total_files_changed"]) for s in summaries]),
        ("Lines +/-", ["+%d/-%d" % (s["total_lines_added"], s["total_lines_removed"])
                       for s in summaries]),
        ("Tokens in/out", ["%s/%s" % (fmt_tokens(s["total_input_tokens"]),
                                       fmt_tokens(s["total_output_tokens"]))
                           for s in summaries]),
    ]

    # Compute column widths
    label_width = max(len(r[0]) for r in rows)
    col_widths = []
    for i, tag in enumerate(tags):
        w = len(tag)
        for _, vals in rows:
            w = max(w, len(vals[i]))
        col_widths.append(w)

    if fmt == "markdown":
        header = "| %-*s" % (label_width, "Metric")
        for i, tag in enumerate(tags):
            header += " | %-*s" % (col_widths[i], tag)
        header += " |"
        print(header)

        divider = "| %s" % ("-" * label_width)
        for i in range(len(tags)):
            divider += " | %s" % ("-" * col_widths[i])
        divider += " |"
        print(divider)

        for label, vals in rows:
            line = "| %-*s" % (label_width, label)
            for i, v in enumerate(vals):
                line += " | %-*s" % (col_widths[i], v)
            line += " |"
            print(line)
    else:
        print("=== Run Comparison ===")
        sep = "  "
        header = "%-*s" % (label_width, "Metric")
        for i, tag in enumerate(tags):
            header += sep + "%-*s" % (col_widths[i], tag)
        print(header)

        divider = "-" * label_width
        for i in range(len(tags)):
            divider += sep + "-" * col_widths[i]
        print(divider)

        for label, vals in rows:
            line = "%-*s" % (label_width, label)
            for i, v in enumerate(vals):
                line += sep + "%-*s" % (col_widths[i], v)
            print(line)


def main():
    parser = argparse.ArgumentParser(description="Aggregate eval.jsonl into run summaries")
    parser.add_argument("--eval-log", type=Path, default=EVAL_LOG,
                        help="Path to eval.jsonl")
    parser.add_argument("--run-tag", help="Show summary for a specific run tag")
    parser.add_argument("--compare", nargs="+", metavar="TAG",
                        help="Compare multiple run tags side by side")
    parser.add_argument("--list-tags", action="store_true",
                        help="List all run tags in the eval log")
    parser.add_argument("--markdown", action="store_true",
                        help="Output as markdown table")
    args = parser.parse_args()

    entries = load_entries(args.eval_log)
    if not entries:
        print("No eval data found in %s" % args.eval_log)
        sys.exit(1)

    fmt = "markdown" if args.markdown else "text"

    if args.list_tags:
        tags = sorted(set(e.get("run_tag", "unknown") for e in entries))
        for tag in tags:
            count = sum(1 for e in entries if e.get("run_tag") == tag)
            print("%s (%d entries)" % (tag, count))
        return

    if args.compare:
        summaries = []
        for tag in args.compare:
            filtered = filter_by_tag(entries, tag)
            if not filtered:
                print("Warning: no entries for tag '%s'" % tag, file=sys.stderr)
                continue
            summary = compute_summary(filtered)
            if summary:
                summaries.append(summary)
        print_comparison(summaries, fmt)
        return

    if args.run_tag:
        filtered = filter_by_tag(entries, args.run_tag)
        summary = compute_summary(filtered)
    else:
        summary = compute_summary(entries)

    print_summary(summary, fmt)


if __name__ == "__main__":
    main()
