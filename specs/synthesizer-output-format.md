# Synthesizer Output Format

Three files produced every iteration: synthesis narrative, merged bibliography, and section outline. All outputs go to `AI-generated-outputs/<thread>/synthesis/`.

## synthesis.md structure

```markdown
# Synthesis

**Date:** YYYY-MM-DD
**Thread:** <thread>
**Inputs consumed:**
- Deep reader: [list of files read — notes.md, report.tex, report.bib, section_map.md]
- Critic: [list — report.tex, figure_proposals.md, or "not available"]
- Provocateur: [list — provocations.md, or "not available"]
**Source count:** N sources synthesized
**Conflict count:** N conflicts identified

## Research Question

[1–3 sentences framing the core research problem. Derived from deep-reader reports and critic framing.]

## Synthesis Narrative

### Theme 1: [Descriptive theme title]

[Prose paragraph(s) weaving findings from multiple sources. Every factual claim includes an inline source key (Author2024 format). Distinguish consensus from contested findings.]

**Consensus:** [what most/all sources agree on — with citation keys]

**Contested:** [where sources disagree — with citation keys on both sides]

[CONFLICT] [Description of conflict between SourceA2024 and SourceB2023. SourceA2024 claims X based on [evidence]. SourceB2023 claims Y based on [evidence]. Resolution status: unresolved / favoring X / favoring Y — with reasoning.]

**Gaps:** [what remains unknown or untested — flagged for future work]

### Theme 2: [Descriptive theme title]
*(same structure)*

### Theme N: [Descriptive theme title]
*(3–7 themes typical. More than 7 suggests themes should be merged.)*

## Provocateur Integration

Responses to high-priority provocations from `provocations.md`.

| Rank | Provocation | Lens | Response | Disposition |
|------|-------------|------|----------|-------------|
| 1 | [title from priority ranking] | [lens] | [how the synthesis addresses it] | Addressed / Acknowledged / Out-of-scope |
| 2 | [title] | [lens] | [response] | Addressed / Acknowledged / Out-of-scope |
| ... | ... | ... | ... | ... |

*(Top 5 provocations minimum. "Acknowledged" means the gap is noted but not resolved. "Out-of-scope" requires a 1-sentence justification.)*

## Open Questions

Unresolved issues that the manuscript should address or explicitly scope out.

1. [Open question] — *Source:* [which input flagged it] — *Implication:* [what happens if unresolved]
2. [Open question] — *Source:* [input] — *Implication:* [consequence]
*(3–10 open questions typical)*

## Story Arc

[2–4 paragraph summary of the narrative the manuscript should tell. Structure: (1) What the evidence supports — the core argument. (2) What remains uncertain — hedging needed. (3) What the manuscript should argue — the contribution claim, calibrated to evidence strength.]
```

## master.bib structure

A single BibTeX file combining all `.bib` inputs (deep-reader, critic, other sources).

Requirements:
- **Deduplicated:** No duplicate entries. Deduplication order: (1) match by DOI, (2) match by author+year+title similarity.
- **Lint-clean:** `citation_lint` must pass with zero errors.
- **DOI-verified:** `citation_verify_all` run; unverifiable entries annotated with a comment.
- **Annotated:** Each entry includes a comment noting its origin file(s).

```bibtex
% Source: AI-generated-outputs/<thread>/deep-analysis/report.bib
@article{Author2024,
  author  = {Author, A. and Writer, B.},
  title   = {Title of the Paper},
  journal = {Journal Name},
  year    = {2024},
  doi     = {10.xxxx/xxxxx},
}

% Source: AI-generated-outputs/<thread>/deep-analysis/report.bib, AI-generated-outputs/<thread>/critic-review/report.bib
% Note: appeared in both deep-reader and critic bibliographies (deduplicated)
@inproceedings{Smith2023,
  author    = {Smith, C.},
  title     = {Another Paper},
  booktitle = {Conference},
  year      = {2023},
  doi       = {10.xxxx/xxxxx},
}

% DOI UNVERIFIED — CrossRef returned no match. Manual verification recommended.
@article{Rare2022,
  author  = {Rare, D.},
  title   = {Hard to Find Paper},
  journal = {Obscure Journal},
  year    = {2022},
}
```

## section_outline.md structure

```markdown
# Section Outline

**Date:** YYYY-MM-DD
**Thread:** <thread>
**Venue:** [venue name from publication-requirements.md, or "not specified"]
**Word budget:** [total word limit, or "not specified"]
**Sections:** N sections proposed

## 1. Introduction
**Word budget:** [N words, or "—"]
**Purpose:** [1-sentence description of what this section accomplishes]

### Claims
1. [Claim to be made] — **Evidence:** [source_key(s)] — **Strength:** Strong / Moderate / Weak
2. [Claim] — **Evidence:** [source_key(s)] — **Strength:** [level]

### Figure opportunities
- [Description of potential figure] — **Data source:** [where the data comes from] — **From critic:** [yes/no]

### Notes
- [Any special considerations — addresses provocateur challenge X, needs careful hedging, etc.]

## 2. Related Work / Background
**Word budget:** [N words, or "—"]
**Purpose:** [1-sentence description]

### Claims
1. [Claim] — **Evidence:** [source_key(s)] — **Strength:** [level]

### Structural notes
- [How related work should be organized — by theme, chronologically, by method, etc.]

## 3. [Method / Approach / Framework]
**Word budget:** [N words, or "—"]
**Purpose:** [1-sentence description]

### Claims
1. [Claim] — **Evidence:** [source_key(s)] — **Strength:** [level]

### Figure opportunities
- [Description] — **Data source:** [source] — **From critic:** [yes/no]

## 4. [Results / Evaluation / Analysis]
**Word budget:** [N words, or "—"]
**Purpose:** [1-sentence description]

### Claims
1. [Claim] — **Evidence:** [source_key(s)] — **Strength:** [level]

### Figure opportunities
- [Description] — **Data source:** [source] — **From critic:** [yes/no]

### Tables
- [Description of proposed table] — **Data source:** [source]

## 5. Discussion
**Word budget:** [N words, or "—"]
**Purpose:** [1-sentence description]

### Claims
1. [Claim] — **Evidence:** [source_key(s)] — **Strength:** [level]

### Provocateur responses
- [Which provocateur challenges are addressed in this section]

## 6. Conclusion
**Word budget:** [N words, or "—"]
**Purpose:** [1-sentence description]

### Claims
1. [Claim] — **Evidence:** [source_key(s)] — **Strength:** [level]

## Appendices (if needed)
- [Appendix A: title] — [purpose] — [word budget or "—"]

## Claim–Evidence Summary

| # | Section | Claim | Evidence Keys | Strength | Conflict? |
|---|---------|-------|---------------|----------|-----------|
| 1 | Introduction | [claim] | [keys] | Strong | No |
| 2 | Introduction | [claim] | [keys] | Moderate | Yes — see synthesis.md Theme 2 |
| ... | ... | ... | ... | ... | ... |

*(Every claim from all sections in one table for cross-referencing.)*
```

## Evidence strength levels

Used in the section outline's Claim–Evidence mapping:

| Strength | Meaning | Manuscript language |
|----------|---------|-------------------|
| **Strong** | Multiple independent sources, converging evidence, robust methodology | "demonstrates," "shows," "establishes" |
| **Moderate** | Single high-quality source, or multiple sources with caveats | "suggests," "indicates," "provides evidence that" |
| **Weak** | Single source with limitations, or extrapolation from indirect evidence | "may," "could," "preliminary evidence suggests" |

These map directly to the claim-calibration rules in `specs/writing-style.md`.

## Conflict tags

Every conflict in `synthesis.md` uses the `[CONFLICT]` tag with this structure:

```
[CONFLICT] [1-sentence description]. SourceA (Author2024) claims [X] based on [evidence type]. SourceB (Author2023) claims [Y] based on [evidence type]. Resolution: [unresolved / favoring X because ... / favoring Y because ...].
```

Conflicts must appear:
1. Inline in the relevant theme section of the synthesis narrative
2. Flagged in the section_outline.md Claim–Evidence Summary table (Conflict? column)

## Provocateur disposition codes

| Disposition | Meaning | Required content |
|-------------|---------|-----------------|
| **Addressed** | The synthesis or outline directly resolves the provocation | Describe how it's resolved — new claim, new section, new evidence |
| **Acknowledged** | The gap is real but cannot be resolved with current evidence | Note what would be needed to resolve it; manuscript should mention as limitation or future work |
| **Out-of-scope** | The provocation is valid but outside manuscript scope | 1-sentence justification required — why is it out of scope? |

## File locations

```
AI-generated-outputs/<thread>/synthesis/
├── synthesis.md          # Overwrites each iteration
├── master.bib            # Overwrites each iteration (deduplicated, lint-clean)
└── section_outline.md    # Overwrites each iteration
```

The full synthesis history is preserved in git commits.

## Commit gates (checked before final commit)

- [ ] `synthesis.md` exists with at least one theme section
- [ ] Every factual claim in `synthesis.md` has an inline source key (Author2024 format)
- [ ] All `[CONFLICT]` tags include both positions with source keys and a resolution status
- [ ] Provocateur integration table is present (even if "No provocations available" — note why)
- [ ] Open questions section is present with 3+ items (or explicit "No open questions identified" with reasoning)
- [ ] Story arc section is present
- [ ] `master.bib` exists
- [ ] `citation_lint` passes on `master.bib`
- [ ] `citation_verify_all` has been run on `master.bib` (unverified entries annotated)
- [ ] No duplicate entries in `master.bib`
- [ ] `section_outline.md` exists with at least one claim per section
- [ ] Every section in `section_outline.md` has a word budget (or explicit "—" if no venue constraints)
- [ ] Claim–Evidence Summary table is present and covers all claims
- [ ] Evidence strength labels match the three defined levels (Strong / Moderate / Weak)
- [ ] No input files were modified (deep-reader, critic, provocateur outputs untouched)
- [ ] `checkpoint.md` Next Task is set appropriately

## Partial report (yield scenario)

If the synthesizer must yield before completing all three outputs, produce what's available in priority order:

1. **master.bib** — most mechanical, least context-dependent. Can always be completed first.
2. **section_outline.md** — structural; can be derived from deep-reader section_map.md with claim mapping.
3. **synthesis.md** — most context-dependent; produce partial if needed.

Partial output format:

```markdown
# Synthesis (PARTIAL)

**Outputs completed:** [list — e.g., master.bib, section_outline.md]
**Outputs remaining:** [list — e.g., synthesis.md]
**Reason for partial:** [yield signal / context limit]

[completed sections as above]
```

The checkpoint should note which outputs were completed so the next iteration can resume.
