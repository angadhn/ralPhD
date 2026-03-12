#!/usr/bin/env python3
"""
ralph_agent.py — Thin agent runner with per-agent tool registries.

Replaces `claude -p` inside ralph-loop.sh. Loads an agent .md file as the
system prompt, registers only the tools that agent needs, and loops until
the model stops requesting tools.

Tool definitions live in tools/ (core.py, checks.py, pdf.py). This file
is just the loop, auth, and CLI.

Usage:
  python ralph_agent.py --agent paper-writer --task "Write the methods section"
  python ralph_agent.py --agent critic --task "$(cat prompt-build.md)"
"""

import argparse
import json
import os
import sys

from pathlib import Path

from tools.redact import preview_text, redact_text
from tools import execute_tool, get_tools_for_agent
from tools._pricing import PRICING
from providers import (
    detect_provider, create_client, call_model,
    format_assistant_message, format_tool_results,
    get_transient_errors, get_status_error_class,
)


def truncate_result(result: str, limit: int = 50000) -> str:
    """Truncate tool results while preserving complete lines/JSON entries.

    If the result exceeds `limit` chars, keep complete lines from the start
    up to the limit, then append a summary of what was dropped.
    """
    if len(result) <= limit:
        return result

    total_chars = len(result)
    lines = result.split("\n")
    total_lines = len(lines)

    kept = []
    kept_chars = 0
    kept_count = 0

    for line in lines:
        # +1 for the newline we'll rejoin with
        if kept_chars + len(line) + 1 > limit:
            break
        kept.append(line)
        kept_chars += len(line) + 1
        kept_count += 1

    # If even the first line exceeds the limit, keep it truncated
    if not kept:
        kept.append(lines[0][:limit])
        kept_count = 1

    dropped = total_lines - kept_count
    summary = (
        f"\n\n[truncated: kept {kept_count} of {total_lines} lines, "
        f"{kept_chars} of {total_chars} chars — {dropped} lines dropped]"
    )
    return "\n".join(kept) + summary


def load_env():
    """Load .env file if it exists (avoids needing python-dotenv)."""
    env_path = Path(__file__).parent / ".env"
    if env_path.exists():
        for line in env_path.read_text().splitlines():
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                key, _, value = line.partition("=")
                os.environ.setdefault(key.strip(), value.strip())


load_env()


# ── Path context ───────────────────────────────────────────────

def build_path_preamble(ralph_home: Path) -> str:
    """Build a preamble that tells the agent where framework vs project files are.

    When RALPH_HOME == CWD, paths resolve either way — the preamble is still
    injected for consistency but doesn't change behavior.
    """
    cwd = Path.cwd().resolve()
    rh = ralph_home.resolve()

    if rh == cwd:
        # Self-hosted mode: framework IS the project. No prefix needed.
        return ""

    return (
        "## Path Context\n"
        "\n"
        "ralPhD is running as an engine on a separate project.\n"
        f"- **RALPH_HOME** (framework): `{rh}`\n"
        f"- **Working directory** (project): `{cwd}`\n"
        "\n"
        "File paths in this prompt use short names. Resolve them as follows:\n"
        "- **Framework files** — prefix with RALPH_HOME:\n"
        "  `specs/*`, `templates/*`, `prompt-*.md`\n"
        f"  Example: `specs/writing-style.md` → `{rh}/specs/writing-style.md`\n"
        "- **Agent files** — workspace-first: `.claude/agents/{{name}}.md` checks\n"
        "  project dir first, then RALPH_HOME\n"
        "- **Project files** — use as-is (relative to working directory):\n"
        "  `checkpoint.md`, `implementation-plan.md`, `inbox.md`,\n"
        "  `AI-generated-outputs/*`, `sections/*`, `figures/*`, `corpus/*`,\n"
        "  `references/*`, `papers/*`, `logs/*`\n"
        "\n"
    )


# ── Agent loop ─────────────────────────────────────────────────

def run_agent(agent_name: str, system_prompt: str, task: str, model: str,
              max_tokens: int, output_json: str = None):
    import time as _time
    start_ms = int(_time.time() * 1000)

    provider = detect_provider(model)
    client = create_client(provider)

    # Build tool list for this agent
    tool_names, tools = get_tools_for_agent(agent_name)

    print(f"Agent: {agent_name}", file=sys.stderr)
    print(f"Provider: {provider}", file=sys.stderr)
    print(f"Tools: {', '.join(tool_names)}", file=sys.stderr)
    print(f"Model: {model}", file=sys.stderr)
    print("", file=sys.stderr)

    messages = [{"role": "user", "content": task}]
    num_turns = 0
    total_input = 0
    total_output = 0
    total_cache_create = 0
    total_cache_read = 0
    tools_called = []

    _TRANSIENT = get_transient_errors(provider)
    _STATUS_ERROR = get_status_error_class(provider)
    _MAX_RETRIES = 3
    _RETRY_DELAYS = [5, 15, 45]

    while True:
        # Retry transient API errors (rate limit, overload, network).
        # Non-transient errors (auth, bad request) propagate immediately.
        response = None
        for _attempt in range(_MAX_RETRIES + 1):
            try:
                response = call_model(
                    client, provider, model, system_prompt,
                    tools, messages, max_tokens,
                )
                break
            except Exception as e:
                if _STATUS_ERROR and isinstance(e, _STATUS_ERROR):
                    if e.status_code in (500, 529) and _attempt < _MAX_RETRIES:
                        delay = _RETRY_DELAYS[_attempt]
                        print(f"  [retry] API error ({e.status_code}), attempt {_attempt + 1}/{_MAX_RETRIES}, waiting {delay}s", file=sys.stderr)
                        _time.sleep(delay)
                        continue
                    raise
                if _TRANSIENT and isinstance(e, _TRANSIENT):
                    if _attempt < _MAX_RETRIES:
                        delay = _RETRY_DELAYS[_attempt]
                        print(f"  [retry] {type(e).__name__}, attempt {_attempt + 1}/{_MAX_RETRIES}, waiting {delay}s", file=sys.stderr)
                        _time.sleep(delay)
                        continue
                    raise
                raise

        if response is None:
            raise RuntimeError("API call failed after all retries")
        num_turns += 1
        total_input += response.input_tokens
        total_output += response.output_tokens
        total_cache_create += response.cache_creation_input_tokens
        total_cache_read += response.cache_read_input_tokens

        # Add assistant response to conversation
        messages.append(format_assistant_message(provider, response))

        # Process response
        tool_results = []
        for text in response.text_blocks:
            print(text)
        for tc in response.tool_calls:
            tool_input = redact_text(json.dumps(tc.input, indent=None))
            print(f"  [tool] {tc.name}({tool_input})", file=sys.stderr)
            tools_called.append(tc.name)
            try:
                result = execute_tool(tc.name, tc.input)
            except Exception as e:
                result = f"Tool error: {type(e).__name__}: {e}"
            if isinstance(result, list):
                # Multimodal result (image + text content blocks)
                text_parts = [b["text"] for b in result if b.get("type") == "text"]
                log_preview = "; ".join(text_parts) if text_parts else "(image content)"
                print(f"  [result] {preview_text(log_preview)}", file=sys.stderr)
                tool_results.append({"type": "tool_result", "tool_use_id": tc.id, "content": result})
            else:
                result = truncate_result(result)
                print(f"  [result] {preview_text(result)}", file=sys.stderr)
                tool_results.append({
                    "type": "tool_result",
                    "tool_use_id": tc.id,
                    "content": result,
                })

        # If no tools were called, agent is done
        if not tool_results:
            break

        # Feed results back, loop again
        messages.append(format_tool_results(provider, tool_results))

    duration_ms = int(_time.time() * 1000) - start_ms

    # Compute cost from token usage
    prices = PRICING.get(model, PRICING["claude-sonnet-4-6"])
    total_cost_usd = round(
        (total_input * prices["input"]
         + total_output * prices["output"]
         + total_cache_read * prices["cache_read"]
         + total_cache_create * prices["cache_create"]) / 1_000_000,
        6,
    )

    # Write usage JSON compatible with ralph-loop.sh's jq parsing
    usage = {
        "is_error": False,
        "num_turns": num_turns,
        "duration_ms": duration_ms,
        "total_cost_usd": total_cost_usd,
        "tools_called": tools_called,
        "result": preview_text(response.text_blocks[0] if response.text_blocks else ""),
        "usage": {
            "input_tokens": total_input,
            "output_tokens": total_output,
            "cache_creation_input_tokens": total_cache_create,
            "cache_read_input_tokens": total_cache_read,
        },
        "modelUsage": {
            model: {
                "inputTokens": total_input,
                "outputTokens": total_output,
                "cacheCreationInputTokens": total_cache_create,
                "cacheReadInputTokens": total_cache_read,
            }
        },
    }
    usage_json = json.dumps(usage)
    if output_json:
        with open(output_json, "w") as f:
            f.write(redact_text(usage_json))
    print(redact_text(usage_json), file=sys.stderr)


# ── CLI ────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description="Ralph agent runner")
    parser.add_argument("--agent", required=True, help="Agent name (e.g., paper-writer)")
    parser.add_argument("--task", required=True, help="Task prompt (or - to read from stdin)")
    default_model = os.environ.get("RALPH_MODEL") or os.environ.get("CLAUDE_MODEL", "claude-opus-4-6")
    parser.add_argument("--model", default=default_model,
                        help="Model to use (auto-detects provider from name)")
    parser.add_argument("--max-tokens", type=int, default=None, help="Max output tokens (default: from context-budgets.json or 8096)")
    parser.add_argument("--output-json", help="Write usage JSON to this path (compatible with ralph-loop.sh)")
    parser.add_argument("--system-prompt-file", help="Use this file as system prompt instead of .claude/agents/{agent}.md")
    args = parser.parse_args()

    # Resolve RALPH_HOME: env var > script directory
    ralph_home = Path(os.environ.get("RALPH_HOME", str(Path(__file__).parent)))

    # Resolve max_tokens: CLI flag > context-budgets.json > 8096
    if args.max_tokens is None:
        budgets_path = ralph_home / "context-budgets.json"
        if budgets_path.exists():
            try:
                budgets = json.loads(budgets_path.read_text())
                args.max_tokens = budgets.get(args.agent, {}).get("max_tokens", 8096)
            except (json.JSONDecodeError, KeyError):
                args.max_tokens = 8096
        else:
            args.max_tokens = 8096

    # Load agent prompt (workspace-first resolution)
    if args.system_prompt_file:
        prompt_path = args.system_prompt_file
    else:
        workspace_path = Path.cwd() / ".claude" / "agents" / f"{args.agent}.md"
        framework_path = ralph_home / ".claude" / "agents" / f"{args.agent}.md"
        if workspace_path.exists():
            prompt_path = str(workspace_path)
        elif framework_path.exists():
            prompt_path = str(framework_path)
        else:
            print(f"Error: agent '{args.agent}' not found in:", file=sys.stderr)
            print(f"  workspace: {workspace_path}", file=sys.stderr)
            print(f"  framework: {framework_path}", file=sys.stderr)
            sys.exit(1)
    with open(prompt_path) as f:
        system_prompt = f.read()

    # Prepend path context so agents resolve framework vs project files correctly
    path_preamble = build_path_preamble(ralph_home)
    if path_preamble:
        system_prompt = path_preamble + system_prompt

    # Read task from stdin if -
    task = sys.stdin.read() if args.task == "-" else args.task

    run_agent(args.agent, system_prompt, task, args.model, args.max_tokens, args.output_json)


if __name__ == "__main__":
    main()
