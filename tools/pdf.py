"""PDF tools: pdf_metadata, extract_figure.

Wrappers around scripts/ for PDF analysis and figure extraction.
"""

import subprocess


def _run_cmd(cmd):
    """Run a subprocess, return combined stdout+stderr."""
    result = subprocess.run(cmd, capture_output=True, text=True)
    output = result.stdout + result.stderr
    return output if output.strip() else f"(exit code {result.returncode}, no output)"


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


TOOLS = {
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
