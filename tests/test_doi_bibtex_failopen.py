"""RED tests: _build_doi_bib_index fails open when bibtexparser is missing or .bib is absent.

Bug: _citation.py _build_doi_bib_index returns {} silently when:
  1. bibtexparser is not installed (ImportError swallowed)
  2. .bib file path doesn't exist (FileNotFoundError swallowed)

This means verify.py gets an empty DOI→source_key index, silently
skipping all ledger lookups — degraded verification with no warning.
"""

import sys
import types
from unittest.mock import patch

import pytest

from tools._citation import _build_doi_bib_index


def test_missing_bibtexparser_raises():
    """_build_doi_bib_index must raise ImportError when bibtexparser is absent."""
    # Remove bibtexparser from sys.modules to simulate it not being installed
    saved = sys.modules.pop("bibtexparser", None)
    try:
        with patch.dict("sys.modules", {"bibtexparser": None}):
            # Setting a module to None in sys.modules makes import raise ImportError
            with pytest.raises(ImportError):
                _build_doi_bib_index("references/refs.bib")
    finally:
        if saved is not None:
            sys.modules["bibtexparser"] = saved


def test_missing_bib_file_raises(tmp_path):
    """_build_doi_bib_index must raise FileNotFoundError for nonexistent .bib."""
    nonexistent = str(tmp_path / "does_not_exist.bib")
    with pytest.raises(FileNotFoundError):
        _build_doi_bib_index(nonexistent)


def test_verify_surfaces_missing_bibtexparser_error():
    """verify_cited_claims must surface the error, not silently continue."""
    from tools.verify import _handle_verify_cited_claims

    # Create minimal tracker and ledger
    import tempfile, json, os
    with tempfile.TemporaryDirectory() as td:
        tracker = os.path.join(td, "tracker.jsonl")
        ledger = os.path.join(td, "ledger.jsonl")
        bib = os.path.join(td, "refs.bib")

        with open(tracker, "w") as f:
            f.write(json.dumps({"doi": "10.1234/test", "section": "1",
                                "claim": "test claim", "role": "support"}) + "\n")
        with open(ledger, "w") as f:
            f.write(json.dumps({"source_key": "Smith2024", "claim": "test claim",
                                "confidence": "high", "extraction_type": "direct_quote",
                                "support_quote": "exact quote"}) + "\n")
        # bib file exists but bibtexparser is missing
        with open(bib, "w") as f:
            f.write("@article{Smith2024, doi={10.1234/test}, title={Test}}\n")

        saved = sys.modules.pop("bibtexparser", None)
        try:
            with patch.dict("sys.modules", {"bibtexparser": None}):
                result = _handle_verify_cited_claims({
                    "tracker_file": tracker,
                    "ledger_file": ledger,
                    "bib_file": bib,
                    "papers_dir": td,
                })
                # Result must mention the error — not silently succeed with empty index
                assert "bibtexparser" in result.lower() or "error" in result.lower(), \
                    f"Expected error about missing bibtexparser, got:\n{result}"
        finally:
            if saved is not None:
                sys.modules["bibtexparser"] = saved
