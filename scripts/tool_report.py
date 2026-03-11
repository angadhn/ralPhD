#!/usr/bin/env python3
"""Tool usage report from logs/usage.jsonl.

Reads usage log, outputs a table: agent, tool, call count, fraction of
iterations where the tool was called. Flags tools appearing in <40% of
iterations as low-usage candidates.

Usage:
  python scripts/tool_report.py                  # plain text table
  python scripts/tool_report.py --markdown        # markdown table
"""

import argparse
import json
import sys
from collections import defaultdict
from pathlib import Path


def load_usage(path: str) -> list[dict]:
    entries = []
    try:
        with open(path) as f:
            for line in f:
                line = line.strip()
                if line:
                    try:
                        entries.append(json.loads(line))
                    except json.JSONDecodeError:
                        continue
    except FileNotFoundError:
        pass
    return entries


def main():
    parser = argparse.ArgumentParser(description="Tool usage report")
    parser.add_argument("--log", default="logs/usage.jsonl", help="Path to usage.jsonl")
    parser.add_argument("--markdown", action="store_true", help="Output as markdown table")
    args = parser.parse_args()

    entries = load_usage(args.log)
    if not entries:
        print("No usage data found." if not args.markdown else "No usage data found.")
        return

    # Count iterations per agent and tool calls per (agent, tool)
    agent_iterations = defaultdict(int)  # agent -> number of iterations
    agent_tool_calls = defaultdict(lambda: defaultdict(int))  # agent -> tool -> call count
    agent_tool_iters = defaultdict(lambda: defaultdict(set))  # agent -> tool -> set of iterations

    for entry in entries:
        agent = entry.get("agent", "unknown")
        iteration = entry.get("iteration", 0)
        tools = entry.get("tools_called", [])
        agent_iterations[agent] += 1

        seen_tools = set()
        for tool in tools:
            agent_tool_calls[agent][tool] += 1
            if tool not in seen_tools:
                agent_tool_iters[agent][tool].add(iteration)
                seen_tools.add(tool)

    # Build rows: (agent, tool, count, fraction, low_usage_flag)
    rows = []
    for agent in sorted(agent_iterations):
        total_iters = agent_iterations[agent]
        for tool in sorted(agent_tool_calls[agent]):
            count = agent_tool_calls[agent][tool]
            iters_with_tool = len(agent_tool_iters[agent][tool])
            fraction = iters_with_tool / total_iters if total_iters > 0 else 0
            flag = fraction < 0.4
            rows.append((agent, tool, count, fraction, flag))

    if not rows:
        print("No tool usage data found (entries exist but no tools_called recorded).")
        return

    if args.markdown:
        print("| Agent | Tool | Calls | Iter % | Flag |")
        print("|-------|------|------:|-------:|------|")
        for agent, tool, count, frac, flag in rows:
            flag_str = "LOW" if flag else ""
            print(f"| {agent} | {tool} | {count} | {frac:.0%} | {flag_str} |")
    else:
        # Plain text table
        hdr = f"{'Agent':<20} {'Tool':<25} {'Calls':>6} {'Iter%':>7} {'Flag':>5}"
        print(hdr)
        print("-" * len(hdr))
        for agent, tool, count, frac, flag in rows:
            flag_str = "LOW" if flag else ""
            print(f"{agent:<20} {tool:<25} {count:>6} {frac:>6.0%} {flag_str:>5}")


if __name__ == "__main__":
    main()
