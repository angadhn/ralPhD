#!/usr/bin/env python3
"""
ralph_agent.py — Thin agent runner with per-agent tool registries.

Replaces `claude -p` inside ralph-loop.sh. Loads an agent .md file as the
system prompt, registers only the tools that agent needs, and loops until
the model stops requesting tools.

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

# ── Tool definitions ────────────────────────────────────────────

TOOL_DEFS = {
    "check_language": {
        "name": "check_language",
        "description": (
            "Check a LaTeX file for citation density, sentence length variance, "
            "stock framings, balanced clauses, and citation-free generalizations. "
            "Returns PASS/FAIL with specific violations."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "file_path": {"type": "string", "description": "Path to the LaTeX file to check"},
                "strict": {"type": "boolean", "description": "Fail on warnings too (default false)"},
            },
            "required": ["file_path"],
        },
    },
    "read_file": {
        "name": "read_file",
        "description": "Read the contents of a file. Use this to inspect any file.",
        "input_schema": {
            "type": "object",
            "properties": {
                "file_path": {"type": "string", "description": "Path to the file to read"},
            },
            "required": ["file_path"],
        },
    },
    "write_file": {
        "name": "write_file",
        "description": "Write content to a file. Creates the file if it doesn't exist, overwrites if it does.",
        "input_schema": {
            "type": "object",
            "properties": {
                "file_path": {"type": "string", "description": "Path to the file to write"},
                "content": {"type": "string", "description": "Content to write"},
            },
            "required": ["file_path", "content"],
        },
    },
    "bash": {
        "name": "bash",
        "description": "Execute a bash command and return its output. Use for git, pdflatex, and other shell operations.",
        "input_schema": {
            "type": "object",
            "properties": {
                "command": {"type": "string", "description": "The bash command to execute"},
            },
            "required": ["command"],
        },
    },
}

# ── Per-agent tool registries ──────────────────────────────────

AGENT_TOOLS = {
    "paper-writer": ["read_file", "write_file", "bash", "check_language"],
    "critic": ["read_file", "write_file", "bash", "check_language"],
    "scout": ["read_file", "write_file", "bash"],
    "deep-reader": ["read_file", "write_file", "bash"],
    "research-coder": ["read_file", "write_file", "bash"],
    "figure-stylist": ["read_file", "write_file", "bash"],
}

DEFAULT_TOOLS = ["read_file", "write_file", "bash"]


# ── Tool execution ─────────────────────────────────────────────

def execute_tool(name: str, tool_input: dict) -> str:
    if name == "check_language":
        cmd = ["python3", "scripts/check_language.py"]
        if tool_input.get("strict"):
            cmd.append("--strict")
        cmd.append(tool_input["file_path"])
        result = subprocess.run(cmd, capture_output=True, text=True)
        output = result.stdout + result.stderr
        return output if output.strip() else f"(exit code {result.returncode}, no output)"

    elif name == "read_file":
        try:
            with open(tool_input["file_path"], "r") as f:
                return f.read()
        except Exception as e:
            return f"Error reading file: {e}"

    elif name == "write_file":
        try:
            os.makedirs(os.path.dirname(tool_input["file_path"]) or ".", exist_ok=True)
            with open(tool_input["file_path"], "w") as f:
                f.write(tool_input["content"])
            return f"Wrote {len(tool_input['content'])} chars to {tool_input['file_path']}"
        except Exception as e:
            return f"Error writing file: {e}"

    elif name == "bash":
        result = subprocess.run(
            ["bash", "-c", tool_input["command"]],
            capture_output=True, text=True, timeout=120,
        )
        output = result.stdout + result.stderr
        if result.returncode != 0:
            return f"(exit code {result.returncode})\n{output}"
        return output if output.strip() else "(no output)"

    return f"Unknown tool: {name}"


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


def run_agent(agent_name: str, system_prompt: str, task: str, model: str, max_tokens: int):
    client = get_client()

    # Build tool list for this agent
    tool_names = AGENT_TOOLS.get(agent_name, DEFAULT_TOOLS)
    tools = [TOOL_DEFS[t] for t in tool_names]

    print(f"Agent: {agent_name}", file=sys.stderr)
    print(f"Tools: {', '.join(tool_names)}", file=sys.stderr)
    print(f"Model: {model}", file=sys.stderr)
    print("", file=sys.stderr)

    messages = [{"role": "user", "content": task}]

    while True:
        response = client.messages.create(
            model=model,
            max_tokens=max_tokens,
            system=system_prompt,
            tools=tools,
            messages=messages,
        )

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
                # Truncate very long results to avoid flooding context
                if len(result) > 50000:
                    result = result[:50000] + f"\n\n... (truncated, {len(result)} total chars)"
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

    # Output usage stats as JSON for ralph-loop.sh to parse
    usage = {
        "input_tokens": response.usage.input_tokens,
        "output_tokens": response.usage.output_tokens,
        "stop_reason": response.stop_reason,
        "model": model,
    }
    print(json.dumps(usage), file=sys.stderr)


# ── CLI ────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description="Ralph agent runner")
    parser.add_argument("--agent", required=True, help="Agent name (e.g., paper-writer)")
    parser.add_argument("--task", required=True, help="Task prompt (or - to read from stdin)")
    parser.add_argument("--model", default=os.environ.get("CLAUDE_MODEL", "claude-sonnet-4-6"),
                        help="Model to use")
    parser.add_argument("--max-tokens", type=int, default=8096, help="Max output tokens")
    args = parser.parse_args()

    # Load agent prompt
    agent_path = f".claude/agents/{args.agent}.md"
    if not os.path.exists(agent_path):
        print(f"Error: {agent_path} not found", file=sys.stderr)
        sys.exit(1)
    with open(agent_path) as f:
        system_prompt = f.read()

    # Read task from stdin if -
    task = sys.stdin.read() if args.task == "-" else args.task

    run_agent(args.agent, system_prompt, task, args.model, args.max_tokens)


if __name__ == "__main__":
    main()
