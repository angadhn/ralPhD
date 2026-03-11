# Triage Output Format

Two reports and one data file produced per triage iteration. Reports go to `AI-generated-outputs/<thread>/triage/`. Deduplicated corpus goes to `corpus/`.

## triage_report.md structure

```markdown
# Triage Report

**Date:** YYYY-MM-DD
**Thread:** <thread>
**Inputs consumed:**
- corpus_index.jsonl: [N entries]
- scored_papers.md: [N papers scored across M scout iterations]
- deep-reader notes.md: [N papers already read, or "not available"]
- grading-rubric.md: [loaded / not found]

## Corpus Statistics

| Metric | Count |
|--------|-------|
| Total entries (pre-dedup) | N |
| Unique papers (post-dedup) | N |
| Duplicates identified | N |
| Grade conflicts resolved | N |
| Papers already read | N |
| Papers in reading plan | N |
| Papers deferred | N |
| Papers unavailable (no PDF) | N |

## Deduplication Log

### Duplicate Cluster 1: [Representative title]

| Entry | Source Iteration | Grade | Match Type |
|-------|-----------------|-------|------------|
| [citation_key_1] | scout iteration N | [grade] | — (kept) |
| [citation_key_2] | scout iteration M | [grade] | DOI match |

**Action:** Merged into `[kept_key]`. Rationale: [citation_key_1 had more complete metadata / higher-quality abstract / etc.]
**Tags merged:** [combined tag list]

### Duplicate Cluster 2: [Representative title]
*(same structure)*

### Duplicate Cluster N: [Representative title]
*(one section per duplicate cluster found. If no duplicates: "No duplicates identified.")*

## Grade Conflict Resolutions

### Conflict 1: [citation_key] — "[Paper title]"

| Scout Iteration | Grade | Score | Reasoning |
|----------------|-------|-------|-----------|
| [iteration N] | [grade] | [score] | [scout's original reasoning] |
| [iteration M] | [grade] | [score] | [scout's original reasoning] |

**Final grade:** [grade] — **Final score:** [score]
**Resolution reasoning:** [Why this grade was chosen. Reference grading-rubric.md criteria. Note which scout assessment was more thorough, whether the paper's relevance changed in light of later scout themes, etc.]

### Conflict 2: [citation_key] — "[Paper title]"
*(same structure)*

*(One section per conflict. If no conflicts: "No grade conflicts found.")*

## Deferred Papers

Papers excluded from the reading plan (grade too low, tangential topic, superseded by a more recent paper).

| # | Citation Key | Grade | Reason Deferred |
|---|-------------|-------|-----------------|
| 1 | [key] | C | Below reading threshold |
| 2 | [key] | B- | Superseded by [other_key] |

*(If no papers deferred: "No papers deferred — all unique papers assigned to reading plan.")*
```

## reading_plan.md structure

```markdown
# Reading Plan

**Date:** YYYY-MM-DD
**Thread:** <thread>
**Total papers:** N
**Total estimated chunks:** N (~N% of deep-reader context per paper)
**Reading batches:** N

## Already Read

Papers processed by deep-reader in prior iterations (excluded from plan):

| # | Citation Key | Title | Read In |
|---|-------------|-------|---------|
| 1 | [key] | [title] | [iteration/date reference] |

*(If none read yet: "No papers read yet.")*

## Reading Batches

### Batch 1: [Theme name]

**Theme:** [description from scout summary]
**Papers:** N
**Estimated context:** ~N% of deep-reader budget
**Priority:** [why this batch is first — foundational papers, highest grades, most relevant to research question]

| # | Citation Key | Title | Grade | Pages | Est. Chunks | PDF Status |
|---|-------------|-------|-------|-------|-------------|------------|
| 1 | [key] | [title] | A | [N] | [N] | ✓ Available |
| 2 | [key] | [title] | A- | [N] | [N] | ✓ Available |
| 3 | [key] | [title] | B+ | [N] | [N] | ⚠ Missing |

**Reading notes:** [Any special instructions — e.g., "Read [key1] before [key2] because it introduces the framework [key2] critiques." Or "Focus on Methods section of [key3] — the theoretical contribution is already covered by [key1]."]

### Batch 2: [Theme name]
*(same structure)*

### Batch N: [Theme name]
*(3–7 batches typical. More than 7 suggests themes should be merged or low-priority papers should be deferred.)*

## Unavailable Papers

Papers where PDF could not be located or verified:

| # | Citation Key | Title | Grade | Issue |
|---|-------------|-------|-------|-------|
| 1 | [key] | [title] | [grade] | [No PDF in corpus / DOI unresolvable / access restricted] |

**Recommendation:** [Attempt manual download / skip — these are low priority / critical — reading plan has gaps without them]

*(If all PDFs available: "All papers have verified PDFs.")*

## Context Budget Summary

| Batch | Papers | Est. Chunks | Cumulative % |
|-------|--------|-------------|-------------|
| 1 | N | N | ~N% |
| 2 | N | N | ~N% |
| ... | ... | ... | ... |
| Total | N | N | ~N% |

*(Deep-reader safe zone is ~30% per iteration. Batches should be sized to fit within this limit.)*
```

## corpus_index_deduped.jsonl structure

One JSON object per line. Same schema as `corpus/corpus_index.jsonl` with additional fields:

```json
{
  "citation_key": "Author2024",
  "title": "Paper Title",
  "authors": ["Author, A.", "Writer, B."],
  "year": 2024,
  "doi": "10.xxxx/xxxxx",
  "source": "scout-iteration-2",
  "grade": "A",
  "score": 92,
  "tags": ["tag1", "tag2"],
  "pdf_path": "corpus/pdfs/Author2024.pdf",
  "triage_status": "assigned",
  "triage_notes": "Deduplicated from 2 entries (DOI match). Grade conflict resolved: A (was B+ in iteration 1).",
  "reading_batch": 1,
  "theme": "Theme name"
}
```

### triage_status values

| Status | Meaning |
|--------|---------|
| `assigned` | In the reading plan — waiting for deep-reader |
| `read` | Already processed by deep-reader |
| `deferred` | Low priority — excluded from reading plan |
| `unavailable` | No PDF available — cannot be read |

### Additional fields (added by triage)

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `triage_status` | string | yes | One of: assigned, read, deferred, unavailable |
| `triage_notes` | string | no | Free-text notes on deduplication, grade changes, etc. |
| `reading_batch` | integer | if assigned | Batch number in the reading plan |
| `theme` | string | if assigned | Theme assignment from scout summary |

All original fields from `corpus_index.jsonl` are preserved. If deduplication merged entries, the `grade` and `score` fields reflect the resolved values (original values are documented in `triage_report.md`).

## Match types for deduplication

| Match Type | Confidence | Criteria |
|------------|-----------|----------|
| **DOI match** | Highest | Exact DOI string match (case-insensitive, stripped of URL prefix) |
| **Title match** | High | Normalized titles (lowercase, strip punctuation) have >90% character overlap |
| **Author+year match** | Medium | Same first author surname + same year, used to disambiguate when title match is borderline |

When entries are merged:
- Keep the entry with the most complete metadata (more fields populated)
- Merge tags (union of all tags from duplicate entries)
- If grades differ, trigger conflict resolution (documented in triage_report.md)
- Preserve the citation key from the kept entry

## File locations

```
AI-generated-outputs/<thread>/triage/
├── triage_report.md     # Overwrites each iteration
└── reading_plan.md      # Overwrites each iteration

corpus/
└── corpus_index_deduped.jsonl   # Overwrites each iteration (original corpus_index.jsonl preserved)
```

The full triage history is preserved in git commits.

## Commit gates (checked before final commit)

- [ ] `triage_report.md` exists with corpus statistics table (all 8 metrics populated)
- [ ] Every duplicate cluster in the deduplication log includes: entries involved, match type, action taken, rationale
- [ ] Every grade conflict resolution includes: original grades from each iteration, final grade, reasoning referencing grading-rubric.md
- [ ] `reading_plan.md` exists with at least one reading batch
- [ ] Reading plan excludes papers listed in "Already Read" section
- [ ] Each paper in reading plan has: citation key, title, grade, page count estimate, PDF status
- [ ] Reading batches include context budget estimates (chunks and percentage)
- [ ] Context budget summary table is present
- [ ] `corpus/corpus_index_deduped.jsonl` exists and has ≤ entries compared to `corpus_index.jsonl`
- [ ] Every entry in `corpus_index_deduped.jsonl` has a `triage_status` field
- [ ] Entries with `triage_status: assigned` have `reading_batch` and `theme` fields
- [ ] Original `corpus/corpus_index.jsonl` is unmodified
- [ ] No scout output files were modified
- [ ] `checkpoint.md` Next Task is set appropriately

## Partial report (yield scenario)

If triage must yield before completing all outputs, produce what's available in priority order:

1. **corpus_index_deduped.jsonl** — most mechanical, enables downstream tools
2. **triage_report.md** — documentation of decisions made
3. **reading_plan.md** — planning output, most context-dependent

Partial output format:

```markdown
# Triage Report (PARTIAL)

**Outputs completed:** [list — e.g., corpus_index_deduped.jsonl, triage_report.md]
**Outputs remaining:** [list — e.g., reading_plan.md]
**Reason for partial:** [yield signal / context limit]

[completed sections as above]
```

```markdown
# Reading Plan (PARTIAL)

**Batches completed:** [N of M]
**Reason for partial:** [yield signal / context limit]

[completed batches as above]
```

The checkpoint should note which outputs were completed so the next iteration can resume.
