# scripts/

Deterministic scripts so agents don't waste context on linter work.

## Why not LLMs?

LLMs are slow, expensive, and unreliable at enforcing rules a regex or API call handles perfectly. Every prose instruction an agent has to remember competes for the ~150-200 instruction budget frontier models can follow. Deterministic tools are faster, cheaper, and never forget.

## Scripts

| Script | What it enforces | Used by |
|--------|-----------------|---------|
| `check_language.py` | Citation density, sentence variance, stock framings, balanced clauses | paper-writer (commit gate), critic (style check) |
| `citation_tools.py` | Citation verification (4 APIs), bib linting, manifest dedup, cited-check | scout, paper-writer |
| `pdf_metadata.py` | Page count, ToC, figure/table counts, section headings | deep-reader (reading plans) |
| `extract_figure.py` | Figure extraction from PDFs | deep-reader (reference figures) |
| `check_figure.py` | DPI, dimensions, color mode, file size | figure-stylist, critic (figure compliance) |
| `check_journal.py` | Word count, page estimate, required bib fields | critic (journal compliance) |
| `usage_report.py` | Token usage and cost reporting from `logs/usage.jsonl` | operator (manual) |
