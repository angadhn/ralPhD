# specs/

Quality standards and output format templates that agents reference during their workflows. Keeps agent prompts short by offloading verbose templates and rules here.

## Files

| File | Used by | Purpose |
|------|---------|---------|
| `writing-style.md` | paper-writer, critic | Anti-LLM-speak rules based on Mensh & Kording and PNAS editorial policy |
| `banned-phrases.txt` | check_language.py | Exact-match list of prohibited phrases |
| `grading-rubric.md` | scout | Scoring formula, anchor tables, grade thresholds for paper evaluation |
| `publication-requirements.md` | critic, check_journal.py, check_figure.py | Target journal constraints (word limits, DPI, dimensions) |
| `reflection-template.md` | ralph-loop.sh (every 5th iteration) | Structure for periodic loop self-assessment |
| `*-output-format.md` | Each agent | Output templates (one per agent) loaded at the writing step |

## Convention

Agents read their output format spec at the step where they write output, not at the start. This saves context for the reasoning-heavy early steps.
