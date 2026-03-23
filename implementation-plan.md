# Implementation Plan — verify-cited-claims

**Thread:** verify-cited-claims
**Created:** 2026-03-23
**Architecture:** serial
**Autonomy:** autopilot

## Tasks

- [x] 1. Fixtures: create `tests/fixtures/verify/` with .bib, tracker, ledger, and PDF — **coder**
- [x] 2. `_build_doi_bib_index` — red/green TDD — **coder** (depends: 1)
- [x] 3. `extract_page_texts` — red/green TDD — **coder** (depends: 1)
- [x] 4. `verify_cited_claims` ledger-first verdicts — red/green TDD — **coder** (depends: 2,3)
- [x] 5. `verify_cited_claims` PDF fallback verdicts — red/green TDD — **coder** (depends: 4)
- [x] 6. `section_filter` — red/green TDD — **coder** (depends: 5)
- [x] 7. Tool registration + agent prompts — red/green TDD — **coder** (depends: 6)
- [x] 8. Regression guard + spec update — red/green TDD — **coder** (depends: 4)

<!-- Each task below specifies RED, GREEN, VERIFY, Commits, and Depends per coder.md:29-33.
     Design context is at the bottom of this file under "Design Reference". -->

---

### Task 1: Fixtures — coder

Create all test fixtures used by tasks 2-8.

**Files to create:**

`tests/fixtures/verify/test.bib`:
```bibtex
@article{Spalart2009,
  author  = {Spalart, P.R.},
  title   = {Hybrid RANS-LES cost analysis},
  year    = {2009},
  journal = {Journal of Computational Physics},
  doi     = {10.1016/j.jcp.2009.01.001}
}
@article{Shur2008,
  author  = {Shur, M.L.},
  title   = {IDDES grid separation elimination},
  year    = {2008},
  journal = {International Journal of Heat and Fluid Flow},
  doi     = {10.1016/j.ijhff.2008.02.001}
}
@article{Larsson2016,
  author  = {Larsson, J.},
  title   = {Wall-modeled LES future outlook},
  year    = {2016},
  journal = {Annual Review of Fluid Mechanics},
  doi     = {10.1146/annurev-fluid-2016}
}
@article{Missing2024,
  author = {Nobody, X.},
  title  = {This paper has no PDF},
  year   = {2024},
  doi    = {10.9999/missing}
}
```

`tests/fixtures/verify/cited_tracker.jsonl`:
```jsonl
{"doi": "10.1016/j.jcp.2009.01.001", "section": "2.1", "role": "primary_evidence", "claim": "Hybrid RANS-LES methods reduce computational cost by 40-60% compared to wall-resolved LES"}
{"doi": "10.1016/j.ijhff.2008.02.001", "section": "2.2", "role": "supporting", "claim": "IDDES eliminates the grid-induced separation problem of DDES"}
{"doi": "10.1146/annurev-fluid-2016", "section": "3.1", "role": "context", "claim": "Wall-modeled LES may overtake hybrid methods for industrial flows by 2030"}
{"doi": "10.9999/missing", "section": "3.2", "role": "primary_evidence", "claim": "Novel coupling reduces error by 25%"}
```

`tests/fixtures/verify/evidence-ledger.jsonl` (3 entries — Missing2024 intentionally absent):
```jsonl
{"claim": "Hybrid RANS-LES methods reduce computational cost by 40-60%", "source_key": "Spalart2009", "source_section": "S4.1", "extraction_type": "direct_quote", "confidence": "high", "reviewer": "deep-reader"}
{"claim": "IDDES eliminates the grid-induced separation problem", "source_key": "Shur2008", "source_section": "S5", "extraction_type": "paraphrase", "confidence": "high", "reviewer": "deep-reader"}
{"claim": "Wall-modeled LES may overtake hybrid methods by 2030", "source_key": "Larsson2016", "source_section": "S7", "extraction_type": "inference", "confidence": "low", "reviewer": "deep-reader"}
```

`tests/fixtures/verify/test_paper.pdf` — generate via inline Python using PyMuPDF (`fitz`), which is already a project dependency. 2 pages:
- Page 1 text: `"Hybrid RANS-LES methods reduce computational cost by 40-60% compared to wall-resolved LES for attached boundary layers. See Section 4.1."`
- Page 2 text: `"Wall-modeled LES is expected to become competitive for industrial flows. Current estimates suggest 15% error reduction, not 25%."`

Generate script for `test_paper.pdf` (run once, commit the PDF):
```python
import fitz
doc = fitz.open()
p1 = doc.new_page()
p1.insert_text((72, 72), "Hybrid RANS-LES methods reduce computational cost by 40-60% compared to wall-resolved LES for attached boundary layers. See Section 4.1.", fontsize=11)
p2 = doc.new_page()
p2.insert_text((72, 72), "Wall-modeled LES is expected to become competitive for industrial flows. Current estimates suggest 15% error reduction, not 25%.", fontsize=11)
doc.save("tests/fixtures/verify/test_paper.pdf")
doc.close()
```

`tests/fixtures/verify/scanned_paper.pdf` — image-only PDF (no extractable text). Used by test 33h for TEXT_UNAVAILABLE.

Generate script (run once, commit the PDF):
```python
import fitz
doc = fitz.open()
page = doc.new_page(width=612, height=792)
# Insert a filled rectangle instead of text — simulates a scanned page (image, no text layer)
page.draw_rect(fitz.Rect(50, 50, 562, 742), color=(0, 0, 0), fill=(0.95, 0.95, 0.95))
# Insert the rect as an image so is_scanned heuristic triggers (images > 0, text < 100 chars/page)
img = page.get_pixmap()
page2 = doc.new_page(width=612, height=792)
page2.insert_image(fitz.Rect(0, 0, 612, 792), pixmap=img)
doc.save("tests/fixtures/verify/scanned_paper.pdf")
doc.close()
```

**VERIFY:**
```bash
test -f tests/fixtures/verify/test.bib && \
  test -f tests/fixtures/verify/cited_tracker.jsonl && \
  test -f tests/fixtures/verify/evidence-ledger.jsonl && \
  test -f tests/fixtures/verify/test_paper.pdf && \
  test -f tests/fixtures/verify/scanned_paper.pdf && \
  python3 -c "import fitz; doc=fitz.open('tests/fixtures/verify/test_paper.pdf'); assert len(doc)==2; doc.close()" && \
  python3 -c "import fitz; doc=fitz.open('tests/fixtures/verify/scanned_paper.pdf'); assert len(doc)>=1; doc.close()"
```

**Commits:** `chore: add verify_cited_claims test fixtures`

---

### Task 2: `_build_doi_bib_index` — coder — red/green TDD

**Depends:** 1

**RED:**

Add to `tests/test-runtime-local.sh` (before the `# ── Summary` block):

```bash
# ── 30. verify_cited_claims: DOI-to-bib bridge ────────────────

check "30a: _build_doi_bib_index parses fixture bib" \
  python3 -c "
from tools._citation import _build_doi_bib_index
idx = _build_doi_bib_index('tests/fixtures/verify/test.bib')
assert len(idx) == 4, f'Expected 4, got {len(idx)}'
assert all('source_key' in v for v in idx.values())
"

check "30b: doi_bib_index is case-insensitive on DOI" \
  python3 -c "
from tools._citation import _build_doi_bib_index
idx = _build_doi_bib_index('tests/fixtures/verify/test.bib')
assert '10.1016/j.jcp.2009.01.001' in idx
assert idx['10.1016/j.jcp.2009.01.001']['source_key'] == 'Spalart2009'
"

check "30c: doi_bib_index returns title" \
  python3 -c "
from tools._citation import _build_doi_bib_index
idx = _build_doi_bib_index('tests/fixtures/verify/test.bib')
assert 'Hybrid' in idx['10.1016/j.jcp.2009.01.001']['title']
"
```

Expected failure: `ImportError: cannot import name '_build_doi_bib_index' from 'tools._citation'` — function does not exist yet.

**GREEN:**

Add `_build_doi_bib_index(bib_path: str) -> dict[str, dict]` to `tools/_citation.py` near line 570 (beside `cited_check`).

- Use `bibtexparser` (same pattern as `batch_verify_bib` at line 588: `import bibtexparser; db = bibtexparser.load(f)`)
- For each entry with a `doi` field: `result[doi.lower().strip()] = {"source_key": entry["ID"], "title": entry.get("title", "")}`
- Skip entries without `doi`
- Return the dict

**VERIFY:**
```bash
bash tests/test-runtime-local.sh 2>&1 | grep "30[abc]:"
```
All three should show ✅.

**Commits:**
- `test(red): add _build_doi_bib_index failing tests (30a-30c)`
- `fix(green): implement _build_doi_bib_index in tools/_citation.py`

---

### Task 3: `extract_page_texts` — coder — red/green TDD

**Depends:** 1

**RED:**

Add to `tests/test-runtime-local.sh`:

```bash
# ── 31. verify_cited_claims: PDF text extraction ───────────────

check "31a: extract_page_texts returns 2 pages of text" \
  python3 -c "
from tools.pdf import extract_page_texts
result = extract_page_texts('tests/fixtures/verify/test_paper.pdf')
assert len(result['pages']) == 2, f'Expected 2, got {len(result[\"pages\"])}'
assert not result['is_scanned']
"

check "31b: extract_page_texts page 1 contains expected text" \
  python3 -c "
from tools.pdf import extract_page_texts
result = extract_page_texts('tests/fixtures/verify/test_paper.pdf')
text = result['pages'][0]['text']
assert '40-60%' in text or '40–60%' in text, f'Expected 40-60%% in page 1 text'
"

check "31c: extract_page_texts respects pages param" \
  python3 -c "
from tools.pdf import extract_page_texts
result = extract_page_texts('tests/fixtures/verify/test_paper.pdf', pages=[1])
assert len(result['pages']) == 1
assert result['pages'][0]['page'] == 2
"
```

Expected failure: `ImportError: cannot import name 'extract_page_texts' from 'tools.pdf'`.

**GREEN:**

Add `extract_page_texts(pdf_path: str, pages: list[int] | None = None) -> dict` to `tools/pdf.py` after `get_fast_metadata` (~line 108).

- Lazy `import fitz` (same pattern as line 40)
- Open doc, compute `is_scanned` using same heuristic as `get_fast_metadata` line 84: `total_images > 0 and avg_text_per_page < 100`
- If scanned: return `{"pages": [], "is_scanned": True}`
- If `pages` is None: iterate all pages (0-indexed)
- For each page: `{"page": page_num + 1, "text": doc[page_num].get_text("text")}`
- Return `{"pages": [...], "is_scanned": False}`
- This is an internal function (no TOOLS entry, no tool schema)

**VERIFY:**
```bash
bash tests/test-runtime-local.sh 2>&1 | grep "31[abc]:"
```

**Commits:**
- `test(red): add extract_page_texts failing tests (31a-31c)`
- `fix(green): implement extract_page_texts in tools/pdf.py`

---

### Task 4: `verify_cited_claims` ledger-first verdicts — coder — red/green TDD

**Depends:** 2, 3

Tests assert against structured JSONL output (not markdown report text) to avoid brittle report-format coupling.

**RED:**

Add to `tests/test-runtime-local.sh`:

```bash
# ── 32. verify_cited_claims: ledger-first verdicts ─────────────

VERIFY_OUT=$(mktemp -d)

check "32a: Spalart2009 (direct_quote, high, no support_quote) → LEDGER_DIRECT" \
  python3 -c "
import json, os
from tools.verify import _handle_verify_cited_claims
_handle_verify_cited_claims({
    'tracker_file': 'tests/fixtures/verify/cited_tracker.jsonl',
    'ledger_file': 'tests/fixtures/verify/evidence-ledger.jsonl',
    'bib_file': 'tests/fixtures/verify/test.bib',
    'papers_dir': 'tests/fixtures/verify/',
    'output_dir': '$VERIFY_OUT',
    'auto_download': False,
})
records = [json.loads(l) for l in open('$VERIFY_OUT/verify_report.jsonl')]
spalart = [r for r in records if r['doi'] == '10.1016/j.jcp.2009.01.001']
assert len(spalart) == 1, f'Expected 1 Spalart record, got {len(spalart)}'
assert spalart[0]['support_label'] == 'LEDGER_DIRECT', f'Expected LEDGER_DIRECT, got {spalart[0][\"support_label\"]}'
assert spalart[0]['support_source'] == 'ledger'
"

check "32b: Shur2008 (paraphrase, high) → PARTIAL_SUPPORT not DIRECT_SUPPORT" \
  python3 -c "
import json
records = [json.loads(l) for l in open('$VERIFY_OUT/verify_report.jsonl')]
shur = [r for r in records if r['doi'] == '10.1016/j.ijhff.2008.02.001']
assert len(shur) == 1
assert shur[0]['support_label'] == 'PARTIAL_SUPPORT', f'Expected PARTIAL_SUPPORT, got {shur[0][\"support_label\"]}'
assert shur[0]['support_source'] == 'ledger'
"

check "32c: Missing2024 (no ledger entry) → not resolved from ledger" \
  python3 -c "
import json
records = [json.loads(l) for l in open('$VERIFY_OUT/verify_report.jsonl')]
missing = [r for r in records if r['doi'] == '10.9999/missing']
assert len(missing) == 1
assert missing[0]['support_source'] != 'ledger', f'Missing2024 must not get ledger verdict'
"

rm -rf "$VERIFY_OUT"
```

Expected failure: `ModuleNotFoundError: No module named 'tools.verify'` — file does not exist yet.

**GREEN:**

Create `tools/verify.py`. Implement `_handle_verify_cited_claims(inp)` with:

1. Parse `tracker_file` with `parse_jsonl` from `tools._helpers`
2. Build DOI→bib index with `_build_doi_bib_index` from `tools._citation`
3. Parse `ledger_file` with `parse_jsonl`; index by source_key
4. For each tracker entry, build a verdict record dict: `{"doi": ..., "section": ..., "claim": ..., "source_key": ..., "support_label": ..., "support_source": ..., "support_summary": ..., "support_quote": None, "support_page": ..., "score": ..., "notes": ...}`
5. Apply ledger verdict rules:
   - high + direct_quote + support_quote populated → DIRECT_SUPPORT, source="ledger"
   - high + direct_quote + no support_quote → LEDGER_DIRECT, source="ledger"
   - high + paraphrase → PARTIAL_SUPPORT, source="ledger"
   - medium → PARTIAL_SUPPORT, source="ledger"
   - low or inference → fall through
   - no ledger entry → fall through
   - For fall-through: emit PDF_MISSING, source="pdf" (PDF fallback not implemented yet)
6. If `output_dir` is set: write `verify_report.jsonl` with one JSON line per verdict record
7. Build and return markdown summary report following `check_claims` pattern
8. Add TOOLS dict with tool schema (name, description, input_schema, function)

Input schema properties: `tracker_file`, `ledger_file` (required), `bib_file` (required), `papers_dir`, `section_filter`, `output_dir`, `auto_download`.

**VERIFY:**
```bash
bash tests/test-runtime-local.sh 2>&1 | grep "32[abc]:"
```

**Commits:**
- `test(red): add ledger-first verdict tests against JSONL output (32a-32c)`
- `fix(green): create tools/verify.py with ledger-first verify_cited_claims`

---

### Task 5: PDF fallback verdicts — coder — red/green TDD

**Depends:** 4

Tests assert against JSONL output. This task adds tests that **cannot pass** with the task 4 stub (which returns PDF_MISSING for all fall-throughs). Tests 33d-33f require real PDF resolution, text extraction, and scoring.

**RED:**

Add to `tests/test-runtime-local.sh`:

```bash
# ── 33. verify_cited_claims: PDF fallback verdicts ─────────────

VERIFY_OUT=$(mktemp -d)
# Create a single-entry tracker + empty ledger to isolate PDF scoring.
# The claim matches test_paper.pdf page 1 text exactly.
# Copy test_paper.pdf to a name the tool can find by source_key.
SCORING_DIR=$(mktemp -d)
echo '{"doi": "10.1016/j.jcp.2009.01.001", "section": "2.1", "role": "primary_evidence", "claim": "Hybrid RANS-LES methods reduce computational cost by 40-60% compared to wall-resolved LES"}' > "$SCORING_DIR/tracker.jsonl"
echo '' > "$SCORING_DIR/empty-ledger.jsonl"
cp tests/fixtures/verify/test_paper.pdf "$SCORING_DIR/Spalart2009_Hybrid_RANS-LES_cost.pdf"

check "33a: Missing2024 (no PDF, auto_download=False) → PDF_MISSING" \
  python3 -c "
import json
from tools.verify import _handle_verify_cited_claims
_handle_verify_cited_claims({
    'tracker_file': 'tests/fixtures/verify/cited_tracker.jsonl',
    'ledger_file': 'tests/fixtures/verify/evidence-ledger.jsonl',
    'bib_file': 'tests/fixtures/verify/test.bib',
    'papers_dir': 'tests/fixtures/verify/',
    'output_dir': '$VERIFY_OUT',
    'auto_download': False,
})
records = [json.loads(l) for l in open('$VERIFY_OUT/verify_report.jsonl')]
missing = [r for r in records if r['doi'] == '10.9999/missing']
assert len(missing) == 1
assert missing[0]['support_label'] == 'PDF_MISSING', f'Expected PDF_MISSING, got {missing[0][\"support_label\"]}'
assert missing[0]['support_source'] == 'pdf'
"

check "33b: Larsson2016 (low-confidence inference) falls through to PDF, not ledger" \
  python3 -c "
import json
records = [json.loads(l) for l in open('$VERIFY_OUT/verify_report.jsonl')]
larsson = [r for r in records if r['doi'] == '10.1146/annurev-fluid-2016']
assert len(larsson) == 1
assert larsson[0]['support_source'] == 'pdf', f'Larsson2016 should fall through to PDF, got source={larsson[0][\"support_source\"]}'
"

check "33c: JSONL report has one record per tracker entry" \
  python3 -c "
import json
records = [json.loads(l) for l in open('$VERIFY_OUT/verify_report.jsonl')]
assert len(records) == 4, f'Expected 4 records (one per tracker entry), got {len(records)}'
assert all('support_label' in r for r in records)
assert all('doi' in r for r in records)
"

rm -rf "$VERIFY_OUT"

# ── 33d-f: tests that REQUIRE real PDF scoring (cannot pass with stub) ──

VERIFY_OUT2=$(mktemp -d)

check "33d: PDF with matching claim text → DIRECT_SUPPORT or PARTIAL_SUPPORT (not PDF_MISSING)" \
  python3 -c "
import json
from tools.verify import _handle_verify_cited_claims
_handle_verify_cited_claims({
    'tracker_file': '$SCORING_DIR/tracker.jsonl',
    'ledger_file': '$SCORING_DIR/empty-ledger.jsonl',
    'bib_file': 'tests/fixtures/verify/test.bib',
    'papers_dir': '$SCORING_DIR/',
    'output_dir': '$VERIFY_OUT2',
    'auto_download': False,
})
records = [json.loads(l) for l in open('$VERIFY_OUT2/verify_report.jsonl')]
assert len(records) == 1
r = records[0]
assert r['support_label'] in ('DIRECT_SUPPORT', 'PARTIAL_SUPPORT'), f'PDF with matching text should score support, got {r[\"support_label\"]}'
assert r['support_source'] == 'pdf'
assert r.get('support_page') is not None, 'Must report the page where support was found'
"

check "33e: PDF scoring returns a non-null support_quote snippet" \
  python3 -c "
import json
records = [json.loads(l) for l in open('$VERIFY_OUT2/verify_report.jsonl')]
r = records[0]
assert r.get('support_quote') is not None and len(r['support_quote']) > 0, f'Must return a support_quote text snippet from the PDF'
"

check "33f: PDF scoring sets a numeric score > 0" \
  python3 -c "
import json
records = [json.loads(l) for l in open('$VERIFY_OUT2/verify_report.jsonl')]
r = records[0]
assert isinstance(r.get('score'), (int, float)) and r['score'] > 0, f'Score must be numeric and > 0 for a match, got {r.get(\"score\")}'
"

rm -rf "$VERIFY_OUT2"

# ── 33g-h: CONTRADICTED and TEXT_UNAVAILABLE ────────────────────

# 33g: contradiction test — claim shares topic terms with PDF page 2 but number conflicts.
# PDF page 2: "Wall-modeled LES is expected to become competitive for industrial flows.
#              Current estimates suggest 15% error reduction, not 25%."
# Claim uses same topic terms but states 25%, which the PDF explicitly contradicts.
CONTRA_DIR=$(mktemp -d)
echo '{"doi": "10.1146/annurev-fluid-2016", "section": "3.1", "role": "primary_evidence", "claim": "Wall-modeled LES is expected to become competitive for industrial flows with 25% error reduction"}' > "$CONTRA_DIR/tracker.jsonl"
echo '' > "$CONTRA_DIR/empty-ledger.jsonl"
cp tests/fixtures/verify/test_paper.pdf "$CONTRA_DIR/Larsson2016_Wall-modeled_LES_future.pdf"
VERIFY_OUT3=$(mktemp -d)

check "33g: claim says 25% but PDF page 2 says 15% with same topic terms → CONTRADICTED" \
  python3 -c "
import json
from tools.verify import _handle_verify_cited_claims
_handle_verify_cited_claims({
    'tracker_file': '$CONTRA_DIR/tracker.jsonl',
    'ledger_file': '$CONTRA_DIR/empty-ledger.jsonl',
    'bib_file': 'tests/fixtures/verify/test.bib',
    'papers_dir': '$CONTRA_DIR/',
    'output_dir': '$VERIFY_OUT3',
    'auto_download': False,
})
records = [json.loads(l) for l in open('$VERIFY_OUT3/verify_report.jsonl')]
assert len(records) == 1
r = records[0]
assert r['support_label'] == 'CONTRADICTED', f'Topic terms match but 25%% vs 15%% — expected CONTRADICTED, got {r[\"support_label\"]}'
"

rm -rf "$CONTRA_DIR" "$VERIFY_OUT3"

# 33h: scanned PDF → TEXT_UNAVAILABLE
# Uses scanned_paper.pdf fixture (image-only, no extractable text)
SCAN_DIR=$(mktemp -d)
echo '{"doi": "10.1016/j.jcp.2009.01.001", "section": "2.1", "role": "primary_evidence", "claim": "Hybrid RANS-LES methods reduce computational cost by 40-60%"}' > "$SCAN_DIR/tracker.jsonl"
echo '' > "$SCAN_DIR/empty-ledger.jsonl"
cp tests/fixtures/verify/scanned_paper.pdf "$SCAN_DIR/Spalart2009_Hybrid_RANS-LES_cost.pdf"
VERIFY_OUT4=$(mktemp -d)

check "33h: scanned PDF (no extractable text) → TEXT_UNAVAILABLE" \
  python3 -c "
import json
from tools.verify import _handle_verify_cited_claims
_handle_verify_cited_claims({
    'tracker_file': '$SCAN_DIR/tracker.jsonl',
    'ledger_file': '$SCAN_DIR/empty-ledger.jsonl',
    'bib_file': 'tests/fixtures/verify/test.bib',
    'papers_dir': '$SCAN_DIR/',
    'output_dir': '$VERIFY_OUT4',
    'auto_download': False,
})
records = [json.loads(l) for l in open('$VERIFY_OUT4/verify_report.jsonl')]
assert len(records) == 1
r = records[0]
assert r['support_label'] == 'TEXT_UNAVAILABLE', f'Scanned PDF should produce TEXT_UNAVAILABLE, got {r[\"support_label\"]}'
"

rm -rf "$SCAN_DIR" "$VERIFY_OUT4" "$SCORING_DIR"
```

Expected failure: 33a-33c may pass from task 4's stub. **33d-33h will fail** because the stub returns PDF_MISSING for all fall-throughs — it never calls `extract_page_texts`, scores text, detects contradictions, or handles scanned PDFs. These tests force the real implementation.

**GREEN:**

In `tools/verify.py`, implement the PDF fallback branch for fall-through cases:

1. Resolve PDF path: scan `papers_dir` for files whose name starts with source_key (e.g., `Spalart2009*.pdf`), then call `manifest_check(doi, papers_dir)` from `tools._citation` (line 533), then optionally `_handle_citation_download` from `tools/download.py` if `auto_download=True`
2. If no PDF found → PDF_MISSING, source="pdf"
3. Call `extract_page_texts(pdf_path)` from `tools.pdf`
4. If `is_scanned` → TEXT_UNAVAILABLE, source="pdf"
5. Score pages using term co-occurrence + number anchoring (see design reference at end of this file)
6. Set `support_quote` to the first ~200 chars of the best-scoring page's text
7. Set `support_page` to the best-scoring page number
8. Set `score` to the computed term_hits value (float, 0-1)
9. Maintain `_pdf_text_cache: dict` keyed by absolute path to avoid re-extracting same PDF

**VERIFY:**
```bash
bash tests/test-runtime-local.sh 2>&1 | grep "33[a-h]:"
```
All eight should show ✅.

**Commits:**
- `test(red): add PDF fallback verdict tests including scoring, contradiction, and scanned-PDF (33a-33h)`
- `fix(green): implement PDF resolution, scoring, contradiction detection, and scanned-PDF handling in tools/verify.py`

---

### Task 6: `section_filter` — coder — red/green TDD

**Depends:** 5

**RED:**

Add to `tests/test-runtime-local.sh`:

```bash
# ── 34. verify_cited_claims: section_filter ────────────────────

VERIFY_OUT=$(mktemp -d)

check "34a: section_filter='2' limits to section 2.x entries only" \
  python3 -c "
import json
from tools.verify import _handle_verify_cited_claims
_handle_verify_cited_claims({
    'tracker_file': 'tests/fixtures/verify/cited_tracker.jsonl',
    'ledger_file': 'tests/fixtures/verify/evidence-ledger.jsonl',
    'bib_file': 'tests/fixtures/verify/test.bib',
    'papers_dir': 'tests/fixtures/verify/',
    'output_dir': '$VERIFY_OUT',
    'section_filter': '2',
    'auto_download': False,
})
records = [json.loads(l) for l in open('$VERIFY_OUT/verify_report.jsonl')]
assert len(records) == 2, f'section_filter=2 should yield 2 records (2.1, 2.2), got {len(records)}'
sections = {r['section'] for r in records}
assert all(s.startswith('2') for s in sections), f'All sections should start with 2, got {sections}'
"

check "34b: section_filter='3.1' limits to exact section" \
  python3 -c "
import json, os
os.makedirs('$VERIFY_OUT/b', exist_ok=True)
from tools.verify import _handle_verify_cited_claims
_handle_verify_cited_claims({
    'tracker_file': 'tests/fixtures/verify/cited_tracker.jsonl',
    'ledger_file': 'tests/fixtures/verify/evidence-ledger.jsonl',
    'bib_file': 'tests/fixtures/verify/test.bib',
    'papers_dir': 'tests/fixtures/verify/',
    'output_dir': '$VERIFY_OUT/b',
    'section_filter': '3.1',
    'auto_download': False,
})
records = [json.loads(l) for l in open('$VERIFY_OUT/b/verify_report.jsonl')]
assert len(records) == 1, f'section_filter=3.1 should yield 1 record, got {len(records)}'
"

check "34c: no section_filter processes all 4 entries" \
  python3 -c "
import json, os
os.makedirs('$VERIFY_OUT/c', exist_ok=True)
from tools.verify import _handle_verify_cited_claims
_handle_verify_cited_claims({
    'tracker_file': 'tests/fixtures/verify/cited_tracker.jsonl',
    'ledger_file': 'tests/fixtures/verify/evidence-ledger.jsonl',
    'bib_file': 'tests/fixtures/verify/test.bib',
    'papers_dir': 'tests/fixtures/verify/',
    'output_dir': '$VERIFY_OUT/c',
    'auto_download': False,
})
records = [json.loads(l) for l in open('$VERIFY_OUT/c/verify_report.jsonl')]
assert len(records) == 4, f'No filter should yield 4 records, got {len(records)}'
"

rm -rf "$VERIFY_OUT"
```

Expected failure: `section_filter` param is accepted but not implemented — all entries processed regardless, so 34a gets 4 records instead of 2.

**GREEN:**

In `_handle_verify_cited_claims`, after parsing tracker entries, filter:
```python
if section_filter:
    entries = [e for e in entries if e.get("section", "").startswith(section_filter)]
```

**VERIFY:**
```bash
bash tests/test-runtime-local.sh 2>&1 | grep "34[abc]:"
```

**Commits:**
- `test(red): add section_filter tests against JSONL record counts (34a-34c)`
- `fix(green): implement section_filter prefix matching in verify_cited_claims`

---

### Task 7: Tool registration + agent prompts — coder — red/green TDD

**Depends:** 6

**RED:**

Add to `tests/test-runtime-local.sh`:

```bash
# ── 35. verify_cited_claims: registration + integration ────────

check "35a: verify_cited_claims in TOOLS registry" \
  python3 -c "from tools import TOOLS; assert 'verify_cited_claims' in TOOLS"

check "35b: verify_cited_claims in AGENT_TOOLS for editor" \
  python3 -c "from tools import AGENT_TOOLS; assert 'verify_cited_claims' in AGENT_TOOLS['editor']"

check "35c: verify_cited_claims in AGENT_TOOLS for critic" \
  python3 -c "from tools import AGENT_TOOLS; assert 'verify_cited_claims' in AGENT_TOOLS['critic']"

check "35d: editor.md mentions verify_cited_claims" \
  grep -q "verify_cited_claims" "$RALPH_HOME/.claude/agents/editor.md"

check "35e: critic.md mentions verify_cited_claims" \
  grep -q "verify_cited_claims" "$RALPH_HOME/.claude/agents/critic.md"

check "35f: critic.md still has deep-reader notes cross-check" \
  grep -q "notes.md" "$RALPH_HOME/.claude/agents/critic.md"
```

Expected failure: 35a-35c fail because `tools/__init__.py` does not import `tools.verify` yet. 35d-35e fail because agent prompts not updated.

**GREEN:**

1. `tools/__init__.py`: add `from tools.verify import TOOLS as _verify_tools` and `TOOLS.update(_verify_tools)`. Add `"verify_cited_claims"` to AGENT_TOOLS for `editor` and `critic`.

2. `.claude/agents/editor.md`: add `verify_cited_claims` to pre-edit diagnostics step. Include this exact section_filter rule:
   > **`section_filter` derivation:** Extract the leading digits from the .tex filename (e.g., `"2"` from `sections/2_methods.tex`, `"02"` from `sections/02-methods.tex`). Strip leading zeros (`"02"` → `"2"`). If the filename has no leading digits (e.g., `sections/introduction.tex`), omit `section_filter` entirely — the tool will verify all tracker entries.

3. `.claude/agents/critic.md`: add `verify_cited_claims` as primary mechanical check in style-check mode. Keep existing deep-reader notes cross-check (line 90) as secondary. Include the same section_filter derivation rule as editor. Add: CONTRADICTED → blocking in HUMAN_REVIEW_NEEDED.md; strong verb + PARTIAL_SUPPORT → blocking.

**VERIFY:**
```bash
bash tests/test-runtime-local.sh 2>&1 | grep "35[a-f]:"
```

**Commits:**
- `test(red): add registration and integration tests (35a-35f)`
- `fix(green): register verify_cited_claims, update editor.md and critic.md`

---

### Task 8: Regression guard + spec update — coder — red/green TDD

**Depends:** 4 (test 36b imports tools.verify)

**RED:**

Add to `tests/test-runtime-local.sh`:

```bash
# ── 36. verify_cited_claims: regression guards ─────────────────

check "36a: check_claims tool still exists and importable" \
  python3 -c "from tools.claims import TOOLS; assert 'check_claims' in TOOLS; assert callable(TOOLS['check_claims']['function'])"

check "36b: old tracker format (no source_key, no sentence_text) works" \
  python3 -c "
from tools.verify import _handle_verify_cited_claims
r = _handle_verify_cited_claims({
    'tracker_file': 'tests/fixtures/verify/cited_tracker.jsonl',
    'ledger_file': 'tests/fixtures/verify/evidence-ledger.jsonl',
    'bib_file': 'tests/fixtures/verify/test.bib',
    'papers_dir': 'tests/fixtures/verify/',
    'auto_download': False,
})
assert 'error' not in r.lower() and 'traceback' not in r.lower(), f'Old format should work cleanly'
"

check "36c: evidence-format.md documents support_quote field" \
  grep -q "support_quote" "$RALPH_HOME/specs/evidence-format.md"
```

Expected: 36a and 36b should pass immediately (baseline — these are regression guards). 36c fails because `specs/evidence-format.md` does not mention `support_quote` yet. If 36a or 36b pass immediately, document in checkpoint and skip GREEN for those.

**GREEN:**

Update `specs/evidence-format.md`: add three optional fields to the schema table:

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `support_quote` | string | no | Verbatim text span from the source that supports the claim |
| `support_page` | string | no | Page number in the source PDF |
| `support_section` | string | no | Section heading in the source (more specific than source_section) |

Add a note: "These fields are not yet populated by any agent. Reserved for future deep-reader enhancement."

**VERIFY:**
```bash
bash tests/test-runtime-local.sh 2>&1 | grep "36[abc]:"
```

**Commits:**
- `test(red): add regression guards and spec check (36a-36c)`
- `fix(green): add optional support-span fields to evidence-format.md`

---

## Design Reference

<!-- Read-only context for the coder. Tasks above are authoritative. -->

### Why this tool exists

`check_claims` answers "is this cite tracked in the ledger?" `verify_cited_claims` answers "does the cited PDF actually support the claim?" They run sequentially.

### Key design decisions

- **Ledger-first**: trust deep-reader's existing verification; only extract PDF text for claims lacking ledger backing or with low confidence
- **No tracker schema changes**: derive DOI→source_key at runtime via `_build_doi_bib_index`
- **Editor + critic only** for v1
- **`ledger_file` is explicit**: no globbing, agents pass the thread-scoped path
- **`section_filter`**: prefix match on tracker `section` field. Derived by agents from .tex filename: extract leading digits, strip leading zeros. If no digits (e.g., `introduction.tex`), omit filter entirely
- **Shell harness tests**: all tests in `tests/test-runtime-local.sh`

### Ledger verdict rules

```
IF   confidence=high AND extraction_type=direct_quote AND support_quote populated → DIRECT_SUPPORT
ELIF confidence=high AND extraction_type=direct_quote AND no support_quote         → LEDGER_DIRECT
ELIF confidence=high AND extraction_type=paraphrase                                → PARTIAL_SUPPORT
ELIF confidence=medium                                                             → PARTIAL_SUPPORT
ELIF confidence=low OR extraction_type=inference                                   → fall through to PDF
ELIF no ledger entry                                                               → fall through to PDF
```

### PDF scoring: term co-occurrence + number anchoring

- Tokenize claim, remove stopwords, keep 3+ char tokens
- Extract numbers: regex `\d+\.?\d*\s*%?`
- Per page: `term_hits` = fraction of claim terms found (case-insensitive), threshold 0.3
- Verdict: terms+numbers match → DIRECT_SUPPORT; terms only → PARTIAL_SUPPORT; number contradiction → CONTRADICTED; nothing → NO_SUPPORT

### Report format

Markdown summary (like `check_claims`): header with counts, then sections for CONTRADICTED, NO_SUPPORT, PDF_MISSING, TEXT_UNAVAILABLE. Optional JSONL detail if `output_dir` set.

### Existing code to reuse

| Function | Location | Use |
|----------|----------|-----|
| `parse_jsonl()` | `tools/_helpers.py:8` | Parse all JSONL files |
| `format_truncated()` | `tools/_helpers.py:32` | Truncate report sections |
| `get_fast_metadata()` | `tools/pdf.py:34` | is_scanned heuristic pattern |
| `manifest_check()` | `tools/_citation.py:533` | Resolve PDF from manifest |
| `_handle_citation_download()` | `tools/download.py:115` | Download missing PDFs (call directly in v1) |
| `batch_verify_bib()` | `tools/_citation.py:588` | bibtexparser usage pattern |

### Files to modify

| File | Change |
|------|--------|
| `tools/verify.py` | **New** — tool handler + TOOLS dict |
| `tools/_citation.py` | Add `_build_doi_bib_index()` near line 570 |
| `tools/pdf.py` | Add `extract_page_texts()` after line 108 |
| `tools/__init__.py` | Import + AGENT_TOOLS for editor/critic |
| `.claude/agents/editor.md` | Add to pre-edit diagnostics |
| `.claude/agents/critic.md` | Add alongside deep-reader notes cross-check |
| `specs/evidence-format.md` | Add optional support-span fields |
| `tests/fixtures/verify/` | **New** — 4 fixture files |
| `tests/test-runtime-local.sh` | Tests 30-36 |
