#!/usr/bin/env python3
"""
citation_tools.py — Retrieval-first citation verification.

Queries Semantic Scholar -> CrossRef -> OpenAlex -> NASA TRS to get VERIFIED metadata.
Never generates citation metadata from memory — always from structured API data.

Usage:
  python scripts/citation_tools.py lookup --title "Paper Title" [--authors "Last1, Last2"]
  python scripts/citation_tools.py verify --doi "10.xxxx/xxxxx"
  python scripts/citation_tools.py batch-lookup --input papers.txt --output corpus_index.jsonl
  python scripts/citation_tools.py lint --bib-dir references/ --output verification_report.md
  python scripts/citation_tools.py manifest-check --doi "10.xxxx" --papers-dir papers/
  python scripts/citation_tools.py manifest-add --doi "10.xxxx" --file "Author2024_Title.pdf" --scout "02-scout" --papers-dir papers/

Dependencies: bibtexparser <2 (pip install 'bibtexparser<2')
All APIs used are free and require no authentication.
"""

import argparse
import json
import sys
import time
import urllib.request
import urllib.parse
import urllib.error
from difflib import SequenceMatcher
from pathlib import Path

# ── Matching ─────────────────────────────────────────────────────

def _score_candidate(query_title: str, candidate_title: str,
                     query_authors: str = "", candidate_authors: str = "") -> dict:
    """Score a candidate match. Returns separate title and author scores."""
    title_sim = SequenceMatcher(None, query_title.lower(), candidate_title.lower()).ratio()
    author_sim = 0.0
    if query_authors and candidate_authors:
        author_sim = SequenceMatcher(None, query_authors.lower(), candidate_authors.lower()).ratio()
    blend = title_sim if not query_authors else 0.7 * title_sim + 0.3 * author_sim
    return {"title_similarity": round(title_sim, 3),
            "author_similarity": round(author_sim, 3),
            "blended": round(blend, 3)}


def _classify(title_sim: float, author_sim: float, has_authors: bool, doi_verified: bool) -> tuple:
    """Classify a match based on independent title AND author thresholds.
    Returns (status, warnings)."""
    warnings = []

    if doi_verified:
        if title_sim < 0.8:
            warnings.append(f"DOI verified but title similarity low ({title_sim:.2f}) — possible metadata variant")
        if has_authors and author_sim < 0.5:
            warnings.append(f"DOI verified but author mismatch ({author_sim:.2f}) — check author list")
        return ("VERIFIED", warnings)

    if title_sim >= 0.9 and (author_sim >= 0.7 or not has_authors):
        return ("VERIFIED", warnings)
    if title_sim >= 0.9 and has_authors and author_sim < 0.7:
        warnings.append(f"Title matches but authors differ ({author_sim:.2f}) — may be wrong paper or wrong author list")
        return ("SUSPICIOUS", warnings)
    if title_sim >= 0.8 and (author_sim >= 0.5 or not has_authors):
        return ("LIKELY", warnings)
    if title_sim >= 0.8 and has_authors and author_sim < 0.5:
        warnings.append(f"Title close but authors do not match ({author_sim:.2f})")
        return ("SUSPICIOUS", warnings)
    if title_sim >= 0.65:
        if has_authors and author_sim < 0.5:
            warnings.append(f"Weak title match ({title_sim:.2f}) AND author mismatch ({author_sim:.2f})")
        return ("SUSPICIOUS", warnings)

    return ("UNVERIFIED", warnings)


# ── API Clients ──────────────────────────────────────────────────

def _get_json(url: str, headers: dict = None, retries: int = 3):
    """Fetch JSON from a URL with exponential backoff. Returns None on failure."""
    req = urllib.request.Request(url, headers=headers or {})
    req.add_header("User-Agent", "citation-tools/1.0 (survey-paper)")
    for attempt in range(retries):
        try:
            with urllib.request.urlopen(req, timeout=15) as resp:
                return json.loads(resp.read().decode("utf-8"))
        except urllib.error.HTTPError as e:
            if e.code == 429 and attempt < retries - 1:
                wait = 2 ** (attempt + 1)
                print(f"  Rate limited ({e.code}), retrying in {wait}s...", file=sys.stderr)
                time.sleep(wait)
                continue
            return None
        except (urllib.error.URLError, json.JSONDecodeError, TimeoutError):
            return None
    return None


def query_semantic_scholar(title: str, authors: str = ""):
    """Search Semantic Scholar for a paper by title."""
    query = urllib.parse.quote(title)
    url = f"https://api.semanticscholar.org/graph/v1/paper/search?query={query}&limit=5&fields=title,authors,year,externalIds,venue,citationCount"
    data = _get_json(url)
    if not data or not data.get("data"):
        return None
    best = None
    best_scores = None
    best_blend = 0.0
    for paper in data["data"]:
        paper_authors = ", ".join(a.get("name", "") for a in (paper.get("authors") or []))
        scores = _score_candidate(title, paper.get("title") or "", authors, paper_authors)
        if scores["blended"] > best_blend:
            best_blend = scores["blended"]
            best_scores = scores
            best = paper
    if best and best_scores and best_scores["title_similarity"] >= 0.65:
        doi = (best.get("externalIds") or {}).get("DOI")
        return {
            "source": "semantic_scholar",
            "title": best.get("title"),
            "authors": [a.get("name", "") for a in (best.get("authors") or [])],
            "year": best.get("year"),
            "doi": doi,
            "venue": best.get("venue"),
            "citation_count": best.get("citationCount"),
            "title_similarity": best_scores["title_similarity"],
            "author_similarity": best_scores["author_similarity"],
        }
    return None


def query_crossref(title: str, authors: str = ""):
    """Search CrossRef for a paper by title."""
    query = urllib.parse.quote(title)
    url = f"https://api.crossref.org/works?query.title={query}&rows=5&select=DOI,title,author,published-print,container-title,type,volume,page,issue"
    data = _get_json(url)
    if not data or not data.get("message", {}).get("items"):
        return None
    best = None
    best_scores = None
    best_blend = 0.0
    for item in data["message"]["items"]:
        item_title = (item.get("title") or [""])[0]
        item_authors = ", ".join(
            f"{a.get('family', '')} {a.get('given', '')}".strip()
            for a in (item.get("author") or [])
        )
        scores = _score_candidate(title, item_title, authors, item_authors)
        if scores["blended"] > best_blend:
            best_blend = scores["blended"]
            best_scores = scores
            best = item
    if best and best_scores and best_scores["title_similarity"] >= 0.65:
        pub_date = best.get("published-print", {}).get("date-parts", [[None]])[0]
        year = pub_date[0] if pub_date else None
        return {
            "source": "crossref",
            "title": (best.get("title") or [""])[0],
            "authors": [
                f"{a.get('given', '')} {a.get('family', '')}".strip()
                for a in (best.get("author") or [])
            ],
            "year": year,
            "doi": best.get("DOI"),
            "venue": (best.get("container-title") or [""])[0],
            "volume": best.get("volume"),
            "pages": best.get("page"),
            "issue": best.get("issue"),
            "title_similarity": best_scores["title_similarity"],
            "author_similarity": best_scores["author_similarity"],
        }
    return None


def query_openalex(title: str, authors: str = ""):
    """Search OpenAlex for a paper by title."""
    query = urllib.parse.quote(title)
    url = f"https://api.openalex.org/works?search={query}&per_page=5&select=id,doi,title,authorships,publication_year,primary_location,cited_by_count"
    data = _get_json(url)
    if not data or not data.get("results"):
        return None
    best = None
    best_scores = None
    best_blend = 0.0
    for work in data["results"]:
        work_title = work.get("title") or ""
        work_authors = ", ".join(
            (a.get("author", {}).get("display_name", ""))
            for a in (work.get("authorships") or [])
        )
        scores = _score_candidate(title, work_title, authors, work_authors)
        if scores["blended"] > best_blend:
            best_blend = scores["blended"]
            best_scores = scores
            best = work
    if best and best_scores and best_scores["title_similarity"] >= 0.65:
        doi_url = best.get("doi") or ""
        doi = doi_url.replace("https://doi.org/", "") if doi_url else None
        venue = ""
        loc = best.get("primary_location") or {}
        if loc.get("source"):
            venue = loc["source"].get("display_name", "")
        return {
            "source": "openalex",
            "title": best.get("title"),
            "authors": [
                a.get("author", {}).get("display_name", "")
                for a in (best.get("authorships") or [])
            ],
            "year": best.get("publication_year"),
            "doi": doi,
            "venue": venue,
            "citation_count": best.get("cited_by_count"),
            "title_similarity": best_scores["title_similarity"],
            "author_similarity": best_scores["author_similarity"],
        }
    return None


def query_ntrs(title: str, authors: str = ""):
    """Search NASA Technical Reports Server for a paper by title."""
    query = urllib.parse.quote(title)
    url = f"https://ntrs.nasa.gov/api/citations?title={query}"
    data = _get_json(url)
    if not data or not data.get("results"):
        return None
    best = None
    best_scores = None
    best_blend = 0.0
    for item in data["results"]:
        item_title = item.get("title", "")
        item_authors = ", ".join(
            f"{a.get('name', '')}".strip()
            for a in (item.get("authorAffiliations") or [])
        )
        scores = _score_candidate(title, item_title, authors, item_authors)
        if scores["blended"] > best_blend:
            best_blend = scores["blended"]
            best_scores = scores
            best = item
    if best and best_scores and best_scores["title_similarity"] >= 0.65:
        return {
            "source": "ntrs",
            "title": best.get("title", ""),
            "authors": [
                a.get("name", "")
                for a in (best.get("authorAffiliations") or [])
            ],
            "year": (
                best.get("publicationDate", "")[:4]
                if best.get("publicationDate")
                else None
            ),
            "doi": best.get("doi"),
            "venue": (
                best.get("subjectCategories", [None])[0]
                if best.get("subjectCategories")
                else None
            ),
            "ntrs_id": best.get("id"),
            "title_similarity": best_scores["title_similarity"],
            "author_similarity": best_scores["author_similarity"],
        }
    return None


def verify_doi(doi: str):
    """Verify a DOI resolves via CrossRef and return metadata."""
    url = f"https://api.crossref.org/works/{urllib.parse.quote(doi, safe='')}"
    data = _get_json(url)
    if not data or not data.get("message"):
        return None
    item = data["message"]
    pub_date = item.get("published-print", item.get("published-online", {}))
    date_parts = pub_date.get("date-parts", [[None]]) if pub_date else [[None]]
    year = date_parts[0][0] if date_parts and date_parts[0] else None
    return {
        "source": "crossref_doi",
        "doi": item.get("DOI"),
        "title": (item.get("title") or [""])[0],
        "authors": [
            f"{a.get('given', '')} {a.get('family', '')}".strip()
            for a in (item.get("author") or [])
        ],
        "year": year,
        "venue": (item.get("container-title") or [""])[0],
        "volume": item.get("volume"),
        "pages": item.get("page"),
        "issue": item.get("issue"),
        "type": item.get("type"),
        "verified": True,
    }


# ── Lookup (cascading API search) ───────────────────────────────

def lookup_paper(title: str, authors: str = "") -> dict:
    """Try Semantic Scholar -> CrossRef -> OpenAlex -> NTRS. Return best result."""
    for fn, name in [
        (query_semantic_scholar, "semantic_scholar"),
        (query_crossref, "crossref"),
        (query_openalex, "openalex"),
        (query_ntrs, "ntrs"),
    ]:
        result = fn(title, authors)
        if result:
            doi_verified = False
            if result.get("doi"):
                doi_meta = verify_doi(result["doi"])
                if doi_meta and doi_meta.get("verified"):
                    doi_verified = True
                    result["title"] = doi_meta["title"] or result["title"]
                    result["authors"] = doi_meta["authors"] or result["authors"]
                    result["year"] = doi_meta.get("year") or result.get("year")
                    result["venue"] = doi_meta.get("venue") or result.get("venue")
                    result["doi_verified"] = True
                    doi_title = doi_meta["title"] or ""
                    doi_authors_str = ", ".join(doi_meta.get("authors") or [])
                    rescored = _score_candidate(title, doi_title, authors, doi_authors_str)
                    result["title_similarity"] = rescored["title_similarity"]
                    result["author_similarity"] = rescored["author_similarity"]

            has_authors = bool(authors)
            status, warnings = _classify(
                result.get("title_similarity", 0),
                result.get("author_similarity", 0),
                has_authors,
                doi_verified,
            )
            result["status"] = status
            result["verified"] = status == "VERIFIED"
            if warnings:
                result["warnings"] = warnings
            return result
        time.sleep(0.5)
    return {
        "source": "none",
        "title": title,
        "authors": authors.split(", ") if authors else [],
        "verified": False,
        "status": "UNVERIFIED",
        "title_similarity": 0.0,
        "author_similarity": 0.0,
        "note": "Not found in Semantic Scholar, CrossRef, OpenAlex, or NTRS",
    }


# ── Lint (BibTeX verification) ──────────────────────────────────

def _score_entry(bib_entry: dict, api_result: dict) -> dict:
    """Score a bib entry against API result."""
    bib_title = bib_entry.get("title", "").strip("{}").lower()
    api_title = (api_result.get("title") or "").lower()
    title_sim = SequenceMatcher(None, bib_title, api_title).ratio() if bib_title and api_title else 0.0

    bib_authors = bib_entry.get("author", "").lower()
    api_authors = ", ".join(api_result.get("authors") or []).lower()
    author_sim = SequenceMatcher(None, bib_authors, api_authors).ratio() if bib_authors and api_authors else 0.0
    has_authors = bool(bib_authors and api_authors)

    bib_year = bib_entry.get("year", "")
    api_year = str(api_result.get("year") or "")
    year_match = bool(bib_year and api_year and bib_year == api_year)

    bib_doi = bib_entry.get("doi", "").lower().strip()
    api_doi = (api_result.get("doi") or "").lower().strip()
    doi_match = bool(bib_doi and api_doi and bib_doi == api_doi)

    bib_volume = bib_entry.get("volume", "").strip()
    api_volume = str(api_result.get("volume") or "").strip()
    volume_match = bool(bib_volume and api_volume and bib_volume == api_volume)

    bib_pages = bib_entry.get("pages", "").strip().replace("--", "-")
    api_pages = (api_result.get("pages") or "").strip().replace("--", "-")
    pages_match = bool(bib_pages and api_pages and bib_pages == api_pages)

    status, warnings = _classify(title_sim, author_sim, has_authors, doi_match)

    if not year_match and bib_year and api_year:
        warnings.append(f"Year mismatch: bib={bib_year} vs API={api_year}")
        if status == "VERIFIED" and not doi_match:
            status = "LIKELY"

    if not volume_match and bib_volume and api_volume:
        warnings.append(f"Volume mismatch: bib={bib_volume} vs API={api_volume}")
        if status == "VERIFIED" and not doi_match:
            status = "LIKELY"

    if not pages_match and bib_pages and api_pages:
        warnings.append(f"Pages mismatch: bib={bib_pages} vs API={api_pages}")
        if status == "VERIFIED" and not doi_match:
            status = "LIKELY"

    return {
        "title_similarity": round(title_sim, 3),
        "author_similarity": round(author_sim, 3),
        "year_match": year_match,
        "volume_match": volume_match,
        "pages_match": pages_match,
        "doi_match": doi_match,
        "status": status,
        "warnings": warnings,
    }


def lint_bib_files(bib_dir: str, output_path: str) -> dict:
    """Parse .bib files, verify each entry, produce verification_report.md."""
    try:
        import bibtexparser
    except ImportError:
        return {"error": "bibtexparser not installed. Run: pip install 'bibtexparser<2'"}

    bib_path = Path(bib_dir)
    if not bib_path.exists():
        return {"error": f"Directory not found: {bib_dir}"}

    bib_files = list(bib_path.glob("*.bib"))
    if not bib_files:
        # Also check if bib_dir itself is a file
        if bib_path.is_file() and bib_path.suffix == ".bib":
            bib_files = [bib_path]
        else:
            return {"error": f"No .bib files found in {bib_dir}"}

    entries = []
    for bf in bib_files:
        with open(bf, "r", encoding="utf-8") as f:
            db = bibtexparser.load(f)
            for e in db.entries:
                e["_source_file"] = str(bf)
                entries.append(e)

    results = []
    counts = {"VERIFIED": 0, "LIKELY": 0, "SUSPICIOUS": 0, "UNVERIFIED": 0}

    for i, entry in enumerate(entries):
        title = entry.get("title", "").strip("{}")
        authors = entry.get("author", "")
        doi = entry.get("doi", "")
        key = entry.get("ID", f"entry_{i}")

        api_result = None
        if doi:
            api_result = verify_doi(doi)
            time.sleep(1.0)

        if not api_result or not api_result.get("verified"):
            api_result = lookup_paper(title, authors)
            time.sleep(1.0)

        if api_result and api_result.get("source") != "none":
            entry_score = _score_entry(entry, api_result)
        else:
            entry_score = {"title_similarity": 0.0, "author_similarity": 0.0,
                           "year_match": False, "doi_match": False,
                           "status": "UNVERIFIED", "warnings": ["No API match found"]}

        status = entry_score["status"]
        counts[status] = counts.get(status, 0) + 1

        results.append({
            "key": key,
            "title": title,
            "status": status,
            "title_similarity": entry_score["title_similarity"],
            "author_similarity": entry_score["author_similarity"],
            "year_match": entry_score["year_match"],
            "doi_match": entry_score["doi_match"],
            "warnings": entry_score.get("warnings", []),
            "api_source": api_result.get("source", "none") if api_result else "none",
            "api_title": api_result.get("title") if api_result else None,
            "api_authors": ", ".join(api_result.get("authors") or []) if api_result else None,
            "api_doi": api_result.get("doi") if api_result else None,
            "source_file": entry.get("_source_file"),
        })

        if (i + 1) % 10 == 0:
            print(f"  Verified {i + 1}/{len(entries)} entries...", file=sys.stderr)

    # Generate report
    total = len(entries)
    report_lines = [
        "# Citation Verification Report",
        "",
        f"**Total entries:** {total}",
        f"**Verified:** {counts['VERIFIED']} ({100*counts['VERIFIED']//max(total,1)}%)",
        f"**Likely:** {counts['LIKELY']} ({100*counts['LIKELY']//max(total,1)}%)",
        f"**Suspicious:** {counts['SUSPICIOUS']} ({100*counts['SUSPICIOUS']//max(total,1)}%)",
        f"**Unverified:** {counts['UNVERIFIED']} ({100*counts['UNVERIFIED']//max(total,1)}%)",
        "",
    ]

    flagged = [r for r in results if r["status"] in ("SUSPICIOUS", "UNVERIFIED")]
    if flagged:
        report_lines.append("## Flagged Entries")
        report_lines.append("")
        for r in flagged:
            report_lines.append(f"### [{r['status']}] {r['key']}")
            report_lines.append(f"- **Bib title:** {r['title']}")
            report_lines.append(f"- **API match:** {r['api_title'] or 'No match found'}")
            report_lines.append(f"- **API authors:** {r['api_authors'] or 'N/A'}")
            report_lines.append(f"- **API DOI:** {r['api_doi'] or 'N/A'}")
            report_lines.append(f"- **Title similarity:** {r['title_similarity']}")
            report_lines.append(f"- **Author similarity:** {r['author_similarity']}")
            if r["warnings"]:
                for w in r["warnings"]:
                    report_lines.append(f"- **Warning: {w}**")
            report_lines.append(f"- **Source file:** {r['source_file']}")
            report_lines.append("")

    report_lines.append("## All Entries")
    report_lines.append("")
    report_lines.append("| Key | Status | Title Sim | Author Sim | DOI Match | API Source |")
    report_lines.append("|-----|--------|-----------|------------|-----------|------------|")
    for r in results:
        doi_mark = "Y" if r["doi_match"] else "N"
        report_lines.append(
            f"| {r['key']} | {r['status']} | {r['title_similarity']} | {r['author_similarity']} | {doi_mark} | {r['api_source']} |"
        )

    report = "\n".join(report_lines)
    Path(output_path).parent.mkdir(parents=True, exist_ok=True)
    with open(output_path, "w", encoding="utf-8") as f:
        f.write(report)

    # Print summary
    print(f"\nCitation Lint Results:", file=sys.stderr)
    print(f"  VERIFIED:   {counts['VERIFIED']}/{total}", file=sys.stderr)
    print(f"  LIKELY:     {counts['LIKELY']}/{total}", file=sys.stderr)
    print(f"  SUSPICIOUS: {counts['SUSPICIOUS']}/{total}", file=sys.stderr)
    print(f"  UNVERIFIED: {counts['UNVERIFIED']}/{total}", file=sys.stderr)

    # Exit with error if any UNVERIFIED
    if counts["UNVERIFIED"] > 0:
        print(f"\nFAIL: {counts['UNVERIFIED']} unverified entries. See {output_path}", file=sys.stderr)

    return {
        "total": total,
        "verified": counts["VERIFIED"],
        "likely": counts["LIKELY"],
        "suspicious": counts["SUSPICIOUS"],
        "unverified": counts["UNVERIFIED"],
        "report_path": output_path,
        "pass": counts["UNVERIFIED"] == 0,
    }


# ── PDF Manifest ─────────────────────────────────────────────────

def _manifest_path(papers_dir: str) -> Path:
    return Path(papers_dir) / "manifest.jsonl"


def manifest_check(doi: str, papers_dir: str, title: str = "") -> dict:
    """Check if a paper (by DOI or title) is already in the manifest."""
    mpath = _manifest_path(papers_dir)
    if not mpath.exists():
        return {"status": "OK", "message": "Not yet downloaded (no manifest)"}
    doi_lower = doi.lower().strip() if doi else ""
    title_lower = title.lower().strip() if title else ""
    with open(mpath, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            entry = json.loads(line)
            entry_doi = (entry.get("doi") or "").lower().strip()
            entry_title = (entry.get("title") or "").lower().strip()
            if doi_lower and entry_doi and doi_lower == entry_doi:
                return {"status": "SKIP", "message": f"Already downloaded as {entry.get('file')}", "file": entry.get("file")}
            if title_lower and entry_title and SequenceMatcher(None, title_lower, entry_title).ratio() >= 0.9:
                return {"status": "SKIP", "message": f"Already downloaded as {entry.get('file')} (title match)", "file": entry.get("file")}
    return {"status": "OK", "message": "Not yet downloaded"}


def manifest_add(doi: str, file: str, scout: str, title: str, papers_dir: str, ntrs_id: str = None) -> dict:
    """Append a new entry to the PDF manifest."""
    mpath = _manifest_path(papers_dir)
    mpath.parent.mkdir(parents=True, exist_ok=True)
    entry = {
        "doi": doi,
        "file": file,
        "scout": scout,
        "title": title,
    }
    if ntrs_id:
        entry["ntrs_id"] = ntrs_id
    with open(mpath, "a", encoding="utf-8") as f:
        f.write(json.dumps(entry) + "\n")
    return {"status": "OK", "message": f"Added {file} to manifest"}


# ── Cited tracker ────────────────────────────────────────────────

def cited_check(doi: str, tracker_path: str = "references/cited_tracker.jsonl") -> dict:
    """Check if a DOI already appears in cited_tracker.jsonl."""
    path = Path(tracker_path)
    if not path.exists():
        return {"status": "NOT_CITED", "note": f"Tracker file not found: {tracker_path}"}
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            entry = json.loads(line)
        except json.JSONDecodeError:
            continue
        if entry.get("doi", "").lower() == doi.lower():
            result = {"status": "CITED"}
            if "section" in entry:
                result["section"] = entry["section"]
            if "role" in entry:
                result["role"] = entry["role"]
            return result
    return {"status": "NOT_CITED"}


# ── CLI ──────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description="Citation verification tools")
    sub = parser.add_subparsers(dest="command")

    p_lookup = sub.add_parser("lookup", help="Look up a paper by title")
    p_lookup.add_argument("--title", required=True, help="Paper title")
    p_lookup.add_argument("--authors", default="", help="Author names (comma-separated)")

    p_verify = sub.add_parser("verify", help="Verify a DOI")
    p_verify.add_argument("--doi", required=True, help="DOI to verify")

    p_batch = sub.add_parser("batch-lookup", help="Batch lookup from file")
    p_batch.add_argument("--input", required=True, help="Input file (one title per line)")
    p_batch.add_argument("--output", required=True, help="Output JSONL file")

    p_lint = sub.add_parser("lint", help="Lint .bib files against APIs")
    p_lint.add_argument("--bib-dir", required=True, help="Directory containing .bib files")
    p_lint.add_argument("--output", required=True, help="Output verification report path")

    p_mcheck = sub.add_parser("manifest-check", help="Check if a paper is already downloaded")
    p_mcheck.add_argument("--doi", default="", help="DOI to check")
    p_mcheck.add_argument("--title", default="", help="Title to check (fuzzy match)")
    p_mcheck.add_argument("--papers-dir", default="papers/", help="Papers directory")

    p_madd = sub.add_parser("manifest-add", help="Add a downloaded PDF to the manifest")
    p_madd.add_argument("--doi", default="", help="DOI of the paper")
    p_madd.add_argument("--file", required=True, help="PDF filename (not full path)")
    p_madd.add_argument("--scout", default="", help="Which scout/agent downloaded it")
    p_madd.add_argument("--title", default="", help="Paper title")
    p_madd.add_argument("--papers-dir", default="papers/", help="Papers directory")
    p_madd.add_argument("--ntrs-id", default=None, help="NTRS ID if applicable")

    p_cited = sub.add_parser("cited-check", help="Check if a DOI is already in cited_tracker.jsonl")
    p_cited.add_argument("--doi", required=True, help="DOI to check")
    p_cited.add_argument("--tracker", default="references/cited_tracker.jsonl", help="Path to cited_tracker.jsonl")

    args = parser.parse_args()

    if args.command == "lookup":
        result = lookup_paper(args.title, args.authors)
        print(json.dumps(result, indent=2))

    elif args.command == "verify":
        result = verify_doi(args.doi)
        if result:
            print(json.dumps(result, indent=2))
        else:
            print(json.dumps({"doi": args.doi, "verified": False, "error": "DOI not found"}))

    elif args.command == "batch-lookup":
        input_path = Path(args.input)
        if not input_path.exists():
            print(f"Error: {args.input} not found", file=sys.stderr)
            sys.exit(1)
        titles = [line.strip() for line in input_path.read_text().splitlines() if line.strip()]
        output_path = Path(args.output)
        output_path.parent.mkdir(parents=True, exist_ok=True)
        with open(output_path, "w", encoding="utf-8") as out:
            for i, title in enumerate(titles):
                result = lookup_paper(title)
                out.write(json.dumps(result) + "\n")
                if (i + 1) % 5 == 0:
                    print(f"  Processed {i + 1}/{len(titles)}...", file=sys.stderr)
                time.sleep(0.5)
        print(f"Wrote {len(titles)} entries to {args.output}")

    elif args.command == "lint":
        result = lint_bib_files(args.bib_dir, args.output)
        if isinstance(result, dict) and result.get("error"):
            print(f"Error: {result['error']}", file=sys.stderr)
            sys.exit(1)
        print(json.dumps(result, indent=2))
        if not result.get("pass", True):
            sys.exit(1)

    elif args.command == "manifest-check":
        if not args.doi and not args.title:
            print("Error: provide --doi and/or --title", file=sys.stderr)
            sys.exit(1)
        result = manifest_check(args.doi, args.papers_dir, args.title)
        print(json.dumps(result, indent=2))

    elif args.command == "manifest-add":
        result = manifest_add(args.doi, args.file, args.scout, args.title, args.papers_dir, args.ntrs_id)
        print(json.dumps(result, indent=2))

    elif args.command == "cited-check":
        result = cited_check(args.doi, args.tracker)
        print(json.dumps(result, indent=2))

    else:
        parser.print_help()
        sys.exit(1)


if __name__ == "__main__":
    main()
