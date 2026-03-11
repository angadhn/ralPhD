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
import subprocess
import sys

from pathlib import Path

import anthropic

from tools import execute_tool, get_tools_for_agent


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


# ── Agent loop ─────────────────────────────────────────────────

def get_client() -> anthropic.Anthropic:
    """Create Anthropic client. Tries: 1) ANTHROPIC_API_KEY, 2) keychain.

    OAuth tokens (sk-ant-oat01-...) must be sent via X-Api-Key header, not
    Authorization: Bearer. The API rejects Bearer-based OAuth with
    "OAuth authentication is currently not supported." Passing the token
    as api_key routes it through X-Api-Key, which works.

    Keychain is preferred because OAuth tokens expire and get refreshed —
    the keychain always has the current token from `claude login`.
    """
    # 1. Explicit API key takes priority (e.g. CI, or user preference)
    if os.environ.get("ANTHROPIC_API_KEY"):
        print("Auth: using ANTHROPIC_API_KEY", file=sys.stderr)
        return anthropic.Anthropic()

    # 2. Otherwise, read OAuth token from macOS keychain (always fresh)
    try:
        result = subprocess.run(
            ["security", "find-generic-password", "-s", "Claude Code-credentials", "-w"],
            capture_output=True, text=True,
        )
        if result.returncode == 0:
            creds = json.loads(result.stdout.strip())
            token = creds.get("claudeAiOauth", {}).get("accessToken")
            if token:
                print("Auth: using Claude Code OAuth token from keychain", file=sys.stderr)
                return anthropic.Anthropic(api_key=token)
    except Exception:
        pass

    raise RuntimeError(
        "No auth found. Set ANTHROPIC_API_KEY or run `claude login`."
    )


def run_agent(agent_name: str, system_prompt: str, task: str, model: str,
              max_tokens: int, output_json: str = None):
    import time as _time
    start_ms = int(_time.time() * 1000)
    client = get_client()

    # Build tool list for this agent
    tool_names, tools = get_tools_for_agent(agent_name)

    print(f"Agent: {agent_name}", file=sys.stderr)
    print(f"Tools: {', '.join(tool_names)}", file=sys.stderr)
    print(f"Model: {model}", file=sys.stderr)
    print("", file=sys.stderr)

    messages = [{"role": "user", "content": task}]
    num_turns = 0
    total_input = 0
    total_output = 0
    total_cache_create = 0
    total_cache_read = 0

    while True:
        # Retry transient API errors (rate limit, overload, network).
        # Non-transient errors (auth, bad request) propagate immediately.
        _TRANSIENT = (
            anthropic.RateLimitError,
            anthropic.APIConnectionError,
        )
        _MAX_RETRIES = 3
        _RETRY_DELAYS = [5, 15, 45]

        response = None
        for _attempt in range(_MAX_RETRIES + 1):
            try:
                response = client.messages.create(
                    model=model,
                    max_tokens=max_tokens,
                    system=system_prompt,
                    tools=tools,
                    messages=messages,
                )
                break
            except anthropic.APIStatusError as e:
                # 529 = overloaded, treat as transient
                if e.status_code == 529 and _attempt < _MAX_RETRIES:
                    delay = _RETRY_DELAYS[_attempt]
                    print(f"  [retry] API overloaded (529), attempt {_attempt + 1}/{_MAX_RETRIES}, waiting {delay}s", file=sys.stderr)
                    _time.sleep(delay)
                    continue
                raise
            except _TRANSIENT as e:
                if _attempt < _MAX_RETRIES:
                    delay = _RETRY_DELAYS[_attempt]
                    print(f"  [retry] {type(e).__name__}, attempt {_attempt + 1}/{_MAX_RETRIES}, waiting {delay}s", file=sys.stderr)
                    _time.sleep(delay)
                    continue
                raise

        if response is None:
            raise RuntimeError("API call failed after all retries")
        num_turns += 1
        total_input += response.usage.input_tokens
        total_output += response.usage.output_tokens
        total_cache_create += getattr(response.usage, 'cache_creation_input_tokens', 0) or 0
        total_cache_read += getattr(response.usage, 'cache_read_input_tokens', 0) or 0

        # Add assistant response to conversation
        messages.append({"role": "assistant", "content": response.content})

        # Process response blocks
        tool_results = []
        for block in response.content:
            if block.type == "text":
                print(block.text)
            elif block.type == "tool_use":
                print(f"  [tool] {block.name}({json.dumps(block.input, indent=None)})", file=sys.stderr)
                result = execute_tool(block.name, block.input)
                result = truncate_result(result)
                print(f"  [result] {result[:200]}{'...' if len(result) > 200 else ''}", file=sys.stderr)
                tool_results.append({
                    "type": "tool_result",
                    "tool_use_id": block.id,
                    "content": result,
                })

        # If no tools were called, agent is done
        if not tool_results:
            break

        # Feed results back, loop again
        messages.append({"role": "user", "content": tool_results})

    duration_ms = int(_time.time() * 1000) - start_ms

    # Write usage JSON compatible with ralph-loop.sh's jq parsing
    usage = {
        "is_error": False,
        "num_turns": num_turns,
        "duration_ms": duration_ms,
        "result": response.content[0].text if response.content and response.content[0].type == "text" else "",
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
    if output_json:
        with open(output_json, "w") as f:
            json.dump(usage, f)
    print(json.dumps(usage), file=sys.stderr)


# ── CLI ────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description="Ralph agent runner")
    parser.add_argument("--agent", required=True, help="Agent name (e.g., paper-writer)")
    parser.add_argument("--task", required=True, help="Task prompt (or - to read from stdin)")
    parser.add_argument("--model", default=os.environ.get("CLAUDE_MODEL", "claude-sonnet-4-6"),
                        help="Model to use")
    parser.add_argument("--max-tokens", type=int, default=None, help="Max output tokens (default: from context-budgets.json or 8096)")
    parser.add_argument("--output-json", help="Write usage JSON to this path (compatible with ralph-loop.sh)")
    args = parser.parse_args()

    # Resolve max_tokens: CLI flag > context-budgets.json > 8096
    if args.max_tokens is None:
        budgets_path = Path(__file__).parent / "context-budgets.json"
        if budgets_path.exists():
            try:
                budgets = json.loads(budgets_path.read_text())
                args.max_tokens = budgets.get(args.agent, {}).get("max_tokens", 8096)
            except (json.JSONDecodeError, KeyError):
                args.max_tokens = 8096
        else:
            args.max_tokens = 8096

    # Load agent prompt
    agent_path = f".claude/agents/{args.agent}.md"
    if not os.path.exists(agent_path):
        print(f"Error: {agent_path} not found", file=sys.stderr)
        sys.exit(1)
    with open(agent_path) as f:
        system_prompt = f.read()

    # Read task from stdin if -
    task = sys.stdin.read() if args.task == "-" else args.task

    run_agent(args.agent, system_prompt, task, args.model, args.max_tokens, args.output_json)


if __name__ == "__main__":
    main()
