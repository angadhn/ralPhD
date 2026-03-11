"""Core tools: read_file, write_file, bash.

These are ghuntley's essential primitives — every agent gets them.
"""

import os
import subprocess


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


TOOLS = {
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
}
