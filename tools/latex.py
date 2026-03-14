"""LaTeX compilation tool: compile_latex.

Wraps the standard pdflatex + bibtex build cycle with error capture.
"""

import os
import re
import subprocess


def _handle_compile_latex(inp: dict) -> dict:
    """Run pdflatex + bibtex + pdflatex x2, return success/errors."""
    tex_file = inp.get("file", "main.tex")

    if not os.path.isfile(tex_file):
        return {"success": False, "pdf_path": None, "errors": [f"File not found: {tex_file}"], "warnings": []}

    if not tex_file.endswith(".tex"):
        return {"success": False, "pdf_path": None, "errors": [f"Not a .tex file: {tex_file}"], "warnings": []}

    basename = os.path.splitext(tex_file)[0]
    pdf_path = f"{basename}.pdf"
    timeout = 60

    errors = []
    warnings = []

    steps = [
        ["pdflatex", "-interaction=nonstopmode", tex_file],
        ["bibtex", basename],
        ["pdflatex", "-interaction=nonstopmode", tex_file],
        ["pdflatex", "-interaction=nonstopmode", tex_file],
    ]

    for cmd in steps:
        try:
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=timeout,
            )
            output = result.stdout + result.stderr

            # Parse LaTeX error lines (start with "! ")
            for line in output.splitlines():
                stripped = line.strip()
                if stripped.startswith("! "):
                    errors.append(stripped)
                elif "Warning:" in stripped:
                    warnings.append(stripped)

            # bibtex returns non-zero for warnings too; only treat as fatal
            # if pdflatex fails (bibtex warnings are captured above)
            if result.returncode != 0 and cmd[0] == "pdflatex":
                break

        except subprocess.TimeoutExpired:
            errors.append(f"Timeout ({timeout}s) running: {' '.join(cmd)}")
            break
        except FileNotFoundError:
            errors.append(f"Command not found: {cmd[0]}. Is TeX Live / MiKTeX installed?")
            break

    # Deduplicate
    errors = list(dict.fromkeys(errors))
    warnings = list(dict.fromkeys(warnings))

    success = os.path.isfile(pdf_path) and len(errors) == 0
    return {
        "success": success,
        "pdf_path": pdf_path if os.path.isfile(pdf_path) else None,
        "errors": errors,
        "warnings": warnings[:20],  # cap warnings to avoid flooding
    }


TOOLS = {
    "compile_latex": {
        "name": "compile_latex",
        "description": "Compile a LaTeX document (pdflatex + bibtex + pdflatex x2). Returns success status, PDF path, errors, and warnings.",
        "input_schema": {
            "type": "object",
            "properties": {
                "file": {
                    "type": "string",
                    "description": "Path to the .tex file to compile (default: main.tex)",
                },
            },
        },
        "function": _handle_compile_latex,
    },
}
