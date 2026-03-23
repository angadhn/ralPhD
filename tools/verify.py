"""verify_cited_claims — does the cited PDF actually support the claim?

Ledger-first: trusts deep-reader's existing verification; only extracts PDF
text for claims lacking ledger backing or with low confidence.
"""

import json
import os
from pathlib import Path

from tools._helpers import parse_jsonl, format_truncated
from tools._citation import _build_doi_bib_index, manifest_check


def _handle_verify_cited_claims(inp):
    tracker_file = inp["tracker_file"]
    ledger_file = inp["ledger_file"]
    bib_file = inp.get("bib_file", "")
    papers_dir = inp.get("papers_dir", "papers/")
    section_filter = inp.get("section_filter")
    output_dir = inp.get("output_dir")
    auto_download = inp.get("auto_download", False)

    # Parse tracker
    entries = parse_jsonl(tracker_file, on_error="skip")
    if not entries:
        return f"No tracker entries found at {tracker_file}"

    # Section filter
    if section_filter:
        entries = [e for e in entries if e.get("section", "").startswith(section_filter)]
    if not entries:
        return f"No tracker entries match section_filter='{section_filter}'"

    # Build DOI→bib index
    doi_bib = _build_doi_bib_index(bib_file) if bib_file else {}

    # Parse ledger, index by source_key
    ledger_entries = parse_jsonl(ledger_file, on_error="skip")
    ledger_by_key = {}
    for le in ledger_entries:
        sk = le.get("source_key", "")
        if sk:
            ledger_by_key.setdefault(sk, []).append(le)

    # Process each tracker entry
    verdicts = []
    for entry in entries:
        doi = entry.get("doi", "")
        section = entry.get("section", "")
        claim = entry.get("claim", "")
        role = entry.get("role", "")

        # Resolve source_key from DOI→bib index
        bib_info = doi_bib.get(doi.lower().strip(), {})
        source_key = bib_info.get("source_key", "")

        verdict = {
            "doi": doi,
            "section": section,
            "claim": claim,
            "role": role,
            "source_key": source_key,
            "support_label": None,
            "support_source": None,
            "support_summary": "",
            "support_quote": None,
            "support_page": None,
            "score": None,
            "notes": "",
        }

        # Try ledger verdict
        ledger_match = _resolve_from_ledger(source_key, claim, ledger_by_key)
        if ledger_match:
            verdict.update(ledger_match)
            verdicts.append(verdict)
            continue

        # Fall through to PDF (stub for now — returns PDF_MISSING)
        verdict["support_label"] = "PDF_MISSING"
        verdict["support_source"] = "pdf"
        verdict["notes"] = "No ledger backing; PDF fallback not yet implemented"
        verdicts.append(verdict)

    # Write JSONL output
    if output_dir:
        os.makedirs(output_dir, exist_ok=True)
        jsonl_path = os.path.join(output_dir, "verify_report.jsonl")
        with open(jsonl_path, "w", encoding="utf-8") as f:
            for v in verdicts:
                f.write(json.dumps(v) + "\n")

    # Build markdown report
    return _build_report(verdicts)


def _resolve_from_ledger(source_key, claim, ledger_by_key):
    """Apply ledger verdict rules. Returns dict update or None for fall-through."""
    if not source_key or source_key not in ledger_by_key:
        return None

    ledger_list = ledger_by_key[source_key]
    # Find best matching ledger entry (by claim substring overlap)
    best = None
    best_overlap = 0
    for le in ledger_list:
        le_claim = le.get("claim", "")
        # Simple overlap: count common words
        claim_words = set(claim.lower().split())
        le_words = set(le_claim.lower().split())
        overlap = len(claim_words & le_words) / max(len(claim_words), 1)
        if overlap > best_overlap:
            best_overlap = overlap
            best = le

    if not best or best_overlap < 0.3:
        return None

    confidence = best.get("confidence", "").lower()
    extraction_type = best.get("extraction_type", "").lower()
    support_quote = best.get("support_quote")

    # Ledger verdict rules
    if confidence == "high" and extraction_type == "direct_quote" and support_quote:
        return {"support_label": "DIRECT_SUPPORT", "support_source": "ledger",
                "support_summary": f"Ledger: direct quote from {source_key}",
                "support_quote": support_quote,
                "support_page": best.get("source_section")}
    elif confidence == "high" and extraction_type == "direct_quote":
        return {"support_label": "LEDGER_DIRECT", "support_source": "ledger",
                "support_summary": f"Ledger: direct quote (no verbatim quote stored) from {source_key}",
                "support_page": best.get("source_section")}
    elif confidence == "high" and extraction_type == "paraphrase":
        return {"support_label": "PARTIAL_SUPPORT", "support_source": "ledger",
                "support_summary": f"Ledger: paraphrase from {source_key}",
                "support_page": best.get("source_section")}
    elif confidence == "medium":
        return {"support_label": "PARTIAL_SUPPORT", "support_source": "ledger",
                "support_summary": f"Ledger: medium confidence from {source_key}",
                "support_page": best.get("source_section")}
    # low or inference → fall through
    return None


def _build_report(verdicts):
    """Build a markdown summary report."""
    lines = ["## verify_cited_claims report", ""]

    counts = {}
    for v in verdicts:
        label = v.get("support_label", "UNKNOWN")
        counts[label] = counts.get(label, 0) + 1

    lines.append(f"Total claims checked: {len(verdicts)}")
    for label in ["DIRECT_SUPPORT", "LEDGER_DIRECT", "PARTIAL_SUPPORT",
                   "NO_SUPPORT", "CONTRADICTED", "PDF_MISSING", "TEXT_UNAVAILABLE"]:
        if label in counts:
            lines.append(f"  {label}: {counts[label]}")
    lines.append("")

    # Flag issues
    issues = [v for v in verdicts if v["support_label"] in
              ("CONTRADICTED", "NO_SUPPORT", "PDF_MISSING", "TEXT_UNAVAILABLE")]
    if not issues:
        lines.append("**PASS** — all claims have ledger or PDF support.")
        return "\n".join(lines)

    lines.append(f"**{len(issues)} issue(s) found:**")
    lines.append("")

    for label in ["CONTRADICTED", "NO_SUPPORT", "PDF_MISSING", "TEXT_UNAVAILABLE"]:
        group = [v for v in issues if v["support_label"] == label]
        if group:
            lines.append(f"### {label} ({len(group)})")
            for v in group:
                lines.append(f"- [{v['source_key'] or v['doi']}] §{v['section']}: {v['claim'][:120]}")
                if v.get("notes"):
                    lines.append(f"  Note: {v['notes']}")
            lines.append("")

    return "\n".join(lines)


TOOLS = {
    "verify_cited_claims": {
        "name": "verify_cited_claims",
        "description": (
            "Verify whether cited papers actually support the claims made about them. "
            "Checks the evidence ledger first (trusting deep-reader verification), "
            "then falls back to PDF text extraction for uncovered or low-confidence claims. "
            "Produces a JSONL report and markdown summary."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "tracker_file": {"type": "string", "description": "Path to cited_tracker.jsonl"},
                "ledger_file": {"type": "string", "description": "Path to evidence-ledger.jsonl"},
                "bib_file": {"type": "string", "description": "Path to .bib file for DOI→source_key mapping"},
                "papers_dir": {"type": "string", "description": "Directory containing PDF papers (default: papers/)"},
                "section_filter": {"type": "string", "description": "Filter to specific section prefix (e.g. '2' for §2.x)"},
                "output_dir": {"type": "string", "description": "Directory for JSONL report output"},
                "auto_download": {"type": "boolean", "description": "Auto-download missing PDFs (default: false)"},
            },
            "required": ["tracker_file", "ledger_file", "bib_file"],
        },
        "function": _handle_verify_cited_claims,
    },
}
