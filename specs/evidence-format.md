# Evidence Ledger Format

The evidence ledger tracks claim-evidence pairs extracted during the research process. It provides mechanical provenance checking: every claim in the manuscript can be traced back to a source.

## File Location

```
ai-generated-outputs/<thread>/evidence-ledger.jsonl
```

One JSON object per line. Append-only during a thread — agents add entries, never delete.

## Schema

Each line is a JSON object with these fields:

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `claim` | string | yes | The claim or assertion being tracked. Should be specific enough to match against manuscript text. |
| `source_key` | string | yes | BibTeX citation key (e.g. `"Author2024"`) linking to the `.bib` file. |
| `source_section` | string | no | Section or page reference within the source (e.g. `"S3.2"`, `"Table 4"`, `"p.12"`). |
| `extraction_type` | enum | yes | One of: `"direct_quote"`, `"paraphrase"`, `"inference"`. |
| `confidence` | enum | yes | One of: `"high"`, `"medium"`, `"low"`. |
| `reviewer` | string | yes | Agent that created this entry (e.g. `"deep-reader"`, `"scout"`). |

### Extraction Types

- **`direct_quote`** — verbatim or near-verbatim from the source. Highest fidelity.
- **`paraphrase`** — restated in different words, same meaning. Must preserve quantitative details exactly.
- **`inference`** — conclusion drawn from the source but not explicitly stated. Requires `confidence` justification.

### Confidence Levels

- **`high`** — directly supported by the source with no ambiguity.
- **`medium`** — supported but requires interpretation or combines multiple statements.
- **`low`** — plausible inference but the source does not directly address this claim. Should be flagged for review.

## Example Entry

```json
{"claim": "Hybrid RANS-LES methods reduce computational cost by 40-60% compared to wall-resolved LES for attached boundary layers", "source_key": "Spalart2009", "source_section": "S4.1", "extraction_type": "paraphrase", "confidence": "high", "reviewer": "deep-reader"}
```

## Multi-Entry Example

```jsonl
{"claim": "DES97 suffers from modeled-stress depletion in thick boundary layers", "source_key": "Spalart2006", "source_section": "S2.3", "extraction_type": "direct_quote", "confidence": "high", "reviewer": "deep-reader"}
{"claim": "IDDES eliminates the grid-induced separation problem of DDES", "source_key": "Shur2008", "source_section": "S5", "extraction_type": "paraphrase", "confidence": "high", "reviewer": "deep-reader"}
{"claim": "Wall-modeled LES may overtake hybrid methods for industrial flows by 2030", "source_key": "Larsson2016", "source_section": "S7", "extraction_type": "inference", "confidence": "low", "reviewer": "deep-reader"}
```

## Validation Rules

The `check_claims` tool uses this ledger to flag:

1. **Unsupported claims** — claims in the manuscript with no matching ledger entry.
2. **Low-confidence inferences** — entries with `extraction_type: "inference"` and `confidence: "low"`. These need either stronger sourcing or explicit hedging language in the manuscript.
3. **Stale entries** — entries whose `source_key` does not appear in the current `.bib` file (source was removed but claim remains).

## Agent Responsibilities

- **deep-reader**: Primary producer. Appends entries as claims are extracted from papers.
- **scout**: May append entries for high-level claims found during literature survey.
- **editor**: Consumes the ledger via `check_claims`. Does not modify it.
- **critic**: Consumes the ledger via `check_claims`. May flag entries for review but does not modify them.
- **coherence-reviewer**: Consumes the ledger via `check_claims`. Checks for contradictions between ledger entries.
