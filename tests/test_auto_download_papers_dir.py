"""RED test: verify auto_download passes the correct key to citation_download.

Bug: verify.py:170 passes {"doi": ..., "output_dir": papers_dir} but
_handle_citation_download expects the key "papers_dir". The download
therefore ignores the caller's papers_dir and defaults to "papers/".
"""

from unittest.mock import patch, MagicMock
from tools.verify import _resolve_from_pdf


def test_auto_download_passes_papers_dir_key():
    """_resolve_from_pdf must pass papers_dir (not output_dir) to citation_download."""
    captured = {}

    def fake_download(inp):
        captured.update(inp)
        return '{"status": "not_found"}'

    with patch("tools.verify._find_pdf", return_value=None), \
         patch("tools.download._handle_citation_download", fake_download), \
         patch.dict("sys.modules", {}):
        # Use a non-default dir to detect if the key is wrong
        _resolve_from_pdf(
            source_key="Smith2024",
            doi="10.1234/test",
            claim="test claim",
            papers_dir="/custom/papers/dir",
            auto_download=True,
        )

    assert "papers_dir" in captured, (
        f"Expected 'papers_dir' key in download call, got keys: {list(captured.keys())}"
    )
    assert captured["papers_dir"] == "/custom/papers/dir"
    assert "output_dir" not in captured, (
        "Should not pass 'output_dir' — download.py ignores it"
    )
