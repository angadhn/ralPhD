#!/usr/bin/env python3
"""
ralph_agent.py — Thin agent runner with per-agent tool registries.

Replaces `claude -p` inside ralph-loop.sh. Loads an agent .md file as the
system prompt, registers only the tools that agent needs, and loops until
the model stops requesting tools.

Each tool is a single unit: schema + handler colocated (à la ghuntley's
coding-agent pattern). Adding a tool means adding one dict entry.

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


# ── Tool handlers ──────────────────────────────────────────────

def _run_cmd(cmd):
    """Run a subprocess, return combined stdout+stderr."""
    result = subprocess.run(cmd, capture_output=True, text=True)
    output = result.stdout + result.stderr
    return output if output.strip() else f"(exit code {result.returncode}, no output)"


def _handle_check_language(inp):
    cmd = ["python3", "scripts/check_language.py"]
    if inp.get("strict"):
        cmd.append("--strict")
    cmd.append(inp["file_path"])
    return _run_cmd(cmd)


def _handle_read_file(inp):
    try:
        with open(inp["file_path"], "r") as f:
            return f.read()
    except Exception as e:
        return f"Error reading file: {e}"


def _handle_write_file(inp):
    try:
        os.makedirs(os.path.dirname(inp["file_path"]) or ".", exist_ok=True)
        with open(inp["file_path"], "w") as f:
            f.write(inp["content"])
        return f"Wrote {len(inp['content'])} chars to {inp['file_path']}"
    except Exception as e:
        return f"Error writing file: {e}"


def _handle_bash(inp):
    result = subprocess.run(
        ["bash", "-c", inp["command"]],
        capture_output=True, text=True, timeout=120,
    )
    output = result.stdout + result.stderr
    if result.returncode != 0:
        return f"(exit code {result.returncode})\n{output}"
    return output if output.strip() else "(no output)"


def _handle_check_journal(inp):
    cmd = ["python3", "scripts/check_journal.py"]
    if inp.get("pub_reqs"):
        cmd.extend(["--pub-reqs", inp["pub_reqs"]])
    cmd.append(inp["sections_dir"])
    return _run_cmd(cmd)


def _handle_check_figure(inp):
    cmd = ["python3", "scripts/check_figure.py", "--json"]
    if inp.get("pub_reqs"):
        cmd.extend(["--pub-reqs", inp["pub_reqs"]])
    cmd.append(inp["figures_dir"])
    return _run_cmd(cmd)


def _handle_citation_lint(inp):
    cmd = ["python3", "scripts/citation_tools.py", "lint",
           "--bib-dir", inp["bib_dir"],
           "--output", "/dev/stdout"]
    return _run_cmd(cmd)


def _handle_pdf_metadata(inp):
    cmd = ["python3", "scripts/pdf_metadata.py", "--json", inp["pdf_path"]]
    return _run_cmd(cmd)


def _handle_extract_figure(inp):
    if inp.get("list_only"):
        cmd = ["python3", "scripts/extract_figure.py", "--list", inp["pdf_path"]]
    elif inp.get("render_page"):
        cmd = ["python3", "scripts/extract_figure.py", inp["pdf_path"],
               "--render-page", str(inp["render_page"]),
               "--output", inp.get("output_dir", "figures/")]
        if inp.get("dpi"):
            cmd.extend(["--dpi", str(inp["dpi"])])
    else:
        cmd = ["python3", "scripts/extract_figure.py", inp["pdf_path"],
               "--output", inp.get("output_dir", "figures/")]
        if inp.get("pages"):
            cmd.extend(["--pages", inp["pages"]])
    return _run_cmd(cmd)


# ── Tool definitions (schema + handler colocated) ──────────────

TOOLS = {
    "check_language": {
        "name": "check_language",
        "description": (
            "Check a LaTeX or Markdown file for citation density, sentence length variance, "
            "stock framings, balanced clauses, and citation-free generalizations. "
            "Returns PASS/FAIL with specific violations."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "file_path": {"type": "string", "description": "Path to the LaTeX or Markdown file to check"},
                "strict": {"type": "boolean", "description": "Fail on warnings too (default false)"},
            },
            "required": ["file_path"],
        },
        "function": _handle_check_language,
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
        "function": _handle_read_file,
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
        "function": _handle_write_file,
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
        "function": _handle_bash,
    },
    "check_journal": {
        "name": "check_journal",
        "description": (
            "Check manuscript sections against publication requirements: "
            "word count per section, total word count vs limit, page estimate, "
            "required .bib fields. Returns PASS/FAIL with details."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "sections_dir": {"type": "string", "description": "Path to sections directory (e.g. 'sections/')"},
                "pub_reqs": {"type": "string", "description": "Path to publication-requirements.md (optional)"},
            },
            "required": ["sections_dir"],
        },
        "function": _handle_check_journal,
    },
    "check_figure": {
        "name": "check_figure",
        "description": (
            "Check figure files for publication readiness: DPI, pixel dimensions, "
            "color mode, file size, format. Returns PASS/FAIL per figure."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "figures_dir": {"type": "string", "description": "Path to figures directory (e.g. 'figures/')"},
                "pub_reqs": {"type": "string", "description": "Path to publication-requirements.md (optional)"},
            },
            "required": ["figures_dir"],
        },
        "function": _handle_check_figure,
    },
    "citation_lint": {
        "name": "citation_lint",
        "description": (
            "Lint .bib files against Semantic Scholar/CrossRef/OpenAlex to verify "
            "citation metadata. Returns verification report with unverified entries."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "bib_dir": {"type": "string", "description": "Path to bib directory (e.g. 'references/')"},
            },
            "required": ["bib_dir"],
        },
        "function": _handle_citation_lint,
    },
    "pdf_metadata": {
        "name": "pdf_metadata",
        "description": (
            "Extract metadata from a PDF: page count, table of contents, figure/table counts, "
            "section headings, image density, scanned-PDF detection, and estimated reading chunks. "
            "Returns JSON. Use before reading a paper to plan reading budget."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "pdf_path": {"type": "string", "description": "Path to the PDF file"},
            },
            "required": ["pdf_path"],
        },
        "function": _handle_pdf_metadata,
    },
    "extract_figure": {
        "name": "extract_figure",
        "description": (
            "Extract figures from a PDF file. Can list images without extracting, "
            "extract embedded images from specific pages, or render a full page as a high-res PNG."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "pdf_path": {"type": "string", "description": "Path to the PDF file"},
                "output_dir": {"type": "string", "description": "Output directory for extracted images (default: 'figures/')"},
                "pages": {"type": "string", "description": "Page range to extract from (e.g. '1-5', '3', '1,3,5')"},
                "list_only": {"type": "boolean", "description": "List images without extracting (default false)"},
                "render_page": {"type": "integer", "description": "Render a specific page number as a full PNG image"},
                "dpi": {"type": "integer", "description": "DPI for page rendering (default: 200)"},
            },
            "required": ["pdf_path"],
        },
        "function": _handle_extract_figure,
    },
}

# ── Per-agent tool registries ──────────────────────────────────

AGENT_TOOLS = {
    "paper-writer": ["read_file", "write_file", "bash", "check_language", "citation_lint"],
    "critic": ["read_file", "write_file", "bash", "check_language", "check_journal", "check_figure"],
    "scout": ["read_file", "write_file", "bash", "pdf_metadata"],
    "deep-reader": ["read_file", "write_file", "bash", "pdf_metadata", "extract_figure"],
    "research-coder": ["read_file", "write_file", "bash"],
    "figure-stylist": ["read_file", "write_file", "bash", "check_figure"],
}

DEFAULT_TOOLS = ["read_file", "write_file", "bash"]


# ── Tool dispatch ──────────────────────────────────────────────

def _api_schema(tool: dict) -> dict:
    """Strip function from tool def for the API payload."""
    return {k: v for k, v in tool.items() if k != "function"}


def execute_tool(name: str, tool_input: dict) -> str:
    """Dispatch a tool call to its colocated handler."""
    tool = TOOLS.get(name)
    if not tool:
        return f"Unknown tool: {name}"
    return tool["function"](tool_input)


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
    tool_names = AGENT_TOOLS.get(agent_name, DEFAULT_TOOLS)
    tools = [_api_schema(TOOLS[t]) for t in tool_names]

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
        response = client.messages.create(
            model=model,
            max_tokens=max_tokens,
            system=system_prompt,
            tools=tools,
            messages=messages,
        )
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
    parser.add_argument("--max-tokens", type=int, default=8096, help="Max output tokens")
    parser.add_argument("--output-json", help="Write usage JSON to this path (compatible with ralph-loop.sh)")
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

    run_agent(args.agent, system_prompt, task, args.model, args.max_tokens, args.output_json)


if __name__ == "__main__":
    main()
