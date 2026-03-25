"""RED test: section_filter='1' must not match section '10'.

Bug: verify.py uses startswith(section_filter) which means
section_filter="1" matches "10", "11", "100", etc.
Fix: dot-boundary prefix matching — section must equal filter
or start with filter + ".".
"""

import json

from tools.verify import _handle_verify_cited_claims


def test_filter_1_excludes_10(tmp_path):
    """section_filter='1' matches '1' and '1.1' but not '10' or '2.1'."""
    tracker = tmp_path / "tracker.jsonl"
    tracker.write_text(
        '{"doi":"10.1/a","section":"1","claim":"claim a","role":"support"}\n'
        '{"doi":"10.1/b","section":"1.1","claim":"claim b","role":"support"}\n'
        '{"doi":"10.1/c","section":"10","claim":"claim c","role":"support"}\n'
        '{"doi":"10.1/d","section":"2.1","claim":"claim d","role":"support"}\n'
    )
    ledger = tmp_path / "ledger.jsonl"
    ledger.write_text("")
    papers = tmp_path / "papers"
    papers.mkdir()
    output = tmp_path / "output"
    _handle_verify_cited_claims({
        "tracker_file": str(tracker),
        "ledger_file": str(ledger),
        "bib_file": "",
        "papers_dir": str(papers),
        "section_filter": "1",
        "output_dir": str(output),
    })
    verdicts = [json.loads(l) for l in (output / "verify_report.jsonl").read_text().strip().split("\n")]
    sections = {v["section"] for v in verdicts}
    assert sections == {"1", "1.1"}, f"Expected {{'1', '1.1'}}, got {sections}"


def test_filter_exact_match(tmp_path):
    """section_filter='2.1' matches only '2.1'."""
    tracker = tmp_path / "tracker.jsonl"
    tracker.write_text(
        '{"doi":"10.1/a","section":"2","claim":"x","role":"support"}\n'
        '{"doi":"10.1/b","section":"2.1","claim":"y","role":"support"}\n'
        '{"doi":"10.1/c","section":"2.10","claim":"z","role":"support"}\n'
    )
    ledger = tmp_path / "ledger.jsonl"
    ledger.write_text("")
    papers = tmp_path / "papers"
    papers.mkdir()
    output = tmp_path / "output"
    _handle_verify_cited_claims({
        "tracker_file": str(tracker),
        "ledger_file": str(ledger),
        "bib_file": "",
        "papers_dir": str(papers),
        "section_filter": "2.1",
        "output_dir": str(output),
    })
    verdicts = [json.loads(l) for l in (output / "verify_report.jsonl").read_text().strip().split("\n")]
    sections = {v["section"] for v in verdicts}
    assert sections == {"2.1"}, f"Expected {{'2.1'}}, got {sections}"


def test_filter_nonnumeric_introduction(tmp_path):
    """section_filter='introduction' matches 'introduction' but not 'methods' or 'intro'."""
    tracker = tmp_path / "tracker.jsonl"
    tracker.write_text(
        '{"doi":"10.1/a","section":"introduction","claim":"claim a","role":"support"}\n'
        '{"doi":"10.1/b","section":"methods","claim":"claim b","role":"support"}\n'
        '{"doi":"10.1/c","section":"intro","claim":"claim c","role":"support"}\n'
    )
    ledger = tmp_path / "ledger.jsonl"
    ledger.write_text("")
    papers = tmp_path / "papers"
    papers.mkdir()
    output = tmp_path / "output"
    _handle_verify_cited_claims({
        "tracker_file": str(tracker),
        "ledger_file": str(ledger),
        "bib_file": "",
        "papers_dir": str(papers),
        "section_filter": "introduction",
        "output_dir": str(output),
    })
    verdicts = [json.loads(l) for l in (output / "verify_report.jsonl").read_text().strip().split("\n")]
    sections = {v["section"] for v in verdicts}
    assert sections == {"introduction"}, f"Expected {{'introduction'}}, got {sections}"
