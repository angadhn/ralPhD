#!/usr/bin/env python3
"""Redact secret-like content from stdin or one or more files."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

from tools.redact import redact_text


def _read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="replace")


def main() -> int:
    parser = argparse.ArgumentParser(description="Redact secret-like content")
    parser.add_argument("paths", nargs="*", help="Optional files to redact; stdin is used when omitted")
    args = parser.parse_args()

    if args.paths:
        for idx, path_str in enumerate(args.paths):
            if idx:
                sys.stdout.write("\n")
            sys.stdout.write(redact_text(_read_text(Path(path_str))))
        return 0

    sys.stdout.write(redact_text(sys.stdin.read()))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
