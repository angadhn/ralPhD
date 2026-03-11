# Agents

Eleven specialized agents that form the Ralph loop. Each reads `checkpoint.md` to determine its task, produces outputs, updates the checkpoint, and yields.

## Core Pipeline

| Agent | Role | Tools (beyond essentials) | Lines |
|---|---|---|---|
| scout | Searches literature, scores papers, builds a reading list | pdf_metadata, citation_lookup/verify/verify_all, citation_manifest/download | 71 |
| triage | Deduplicates corpus, resolves grade conflicts, generates reading plan | pdf_metadata, citation_verify_all | 115 |
| deep-reader | Reads papers in depth, extracts claims/data, maps sections | pdf_metadata, extract_figure | 86 |
| critic | Assesses structure, checks style/journal/figure compliance; proposes figures | check_language, check_journal, check_figure, check_claims, citation_verify_all | 94 |
| provocateur | Finds gaps via negative space, inverted assumptions, cross-domain bridges | — | 95 |
| synthesizer | Merges deep-reader + critic + provocateur into synthesis narrative and outline | citation_lint, citation_verify_all | 106 |
| paper-writer | Writes or revises paper sections from outline; reviews editor changes | check_language, citation_lint | 110 |
| editor | Makes substantiated edits to .tex with evidence backing | check_claims, check_language, citation_lint, citation_verify_all | 104 |
| coherence-reviewer | Post-editing review: promise-delivery, terminology, contradictions, novelty | check_claims, check_language | 96 |
| research-coder | Generates analysis scripts, simulations, and figures from data | — | 93 |
| figure-stylist | Reviews figures for visual clarity and print readiness | — | 56 |

## Typical flow

```
scout → triage → deep-reader → critic → provocateur → synthesizer
  → paper-writer → editor → coherence-reviewer → paper-writer (REVIEW-EDITS)
  → research-coder (figures) → figure-stylist
```

## Adding a new agent

1. Copy `agent-template.md` and fill in each section
2. Target **60 lines or fewer** — keep workflows tight, offload verbose templates to `specs/`
3. Place the new `.md` file in this directory (`.claude/agents/`)
4. If the agent produces structured output, add a `specs/<agent>-output-format.md` file
5. Register the agent's tool set in `tools/__init__.py` `AGENT_TOOLS`

## Key conventions

- Agents read `checkpoint.md` for state and write it back with the next task
- Output format templates live in `specs/*-output-format.md`, not inline
- Deterministic checks use scripts in `scripts/` — agents call them, not replicate them
- Each agent gets a curated tool set via `tools/__init__.py` `AGENT_TOOLS` — see `tools/README.md`

## The `inputs/` directory

User-provided context that agents read but never write:

| File type | Example | Used by |
|-----------|---------|---------|
| Reviewer feedback | `reviews-round1.pdf` | editor, paper-writer |
| Prior submissions | `v1-submitted.pdf` | editor, coherence-reviewer |
| Venue guidelines | `icml2025-style-guide.pdf` | editor, paper-writer |
| Style files | `neurips_2025.sty` | paper-writer |
| Supplementary notes | `advisor-notes.md` | all agents |

Only humans populate `inputs/`. Created by `scripts/init-project.sh`.
