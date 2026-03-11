"""Shared path resolution for tool modules.

Single source of truth for resolving framework paths (scripts/, etc.)
when RALPH_HOME may differ from CWD.
"""

import os
from pathlib import Path


def scripts_dir() -> Path:
    """Resolve scripts/ directory via RALPH_HOME, falling back to repo-relative."""
    ralph_home = os.environ.get("RALPH_HOME", "")
    if ralph_home:
        return Path(ralph_home) / "scripts"
    return Path(__file__).resolve().parent.parent / "scripts"
