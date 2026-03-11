"""Core tools: read_file, write_file, bash.

These are ghuntley's essential primitives — every agent gets them.
"""

import os
import subprocess
import tempfile


def _handle_read_file(inp):
    try:
        with open(inp["file_path"], "r") as f:
            return f.read()
    except Exception as e:
        return f"Error reading file: {e}"


def _handle_write_file(inp):
    # Validate inputs before touching the filesystem
    if "content" not in inp or "file_path" not in inp:
        return "Error: write_file requires 'file_path' and 'content' parameters"

    file_path = inp["file_path"]
    content = inp["content"]

    # Check for size regression before writing
    old_size = 0
    if os.path.exists(file_path):
        old_size = os.path.getsize(file_path)

    dir_name = os.path.dirname(file_path) or "."
    os.makedirs(dir_name, exist_ok=True)

    # Atomic write: temp file in same directory, then os.replace()
    try:
        fd, tmp_path = tempfile.mkstemp(dir=dir_name, suffix=".tmp")
        try:
            with os.fdopen(fd, "w") as f:
                f.write(content)
            os.replace(tmp_path, file_path)
        except Exception:
            os.unlink(tmp_path)
            raise
    except Exception as e:
        return f"Error writing file: {e}"

    msg = f"Wrote {len(content)} chars to {file_path}"
    if old_size > 100 and len(content) < old_size * 0.2:
        reduction = 100 - len(content) * 100 // old_size
        msg += f" ⚠ WARNING: file shrank from {old_size} to {len(content)} chars ({reduction}% reduction)"
    return msg


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
