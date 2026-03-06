# Agents

Six specialized agents that form the Ralph loop. Each reads `checkpoint.md` to determine its task, produces outputs, updates the checkpoint, and yields.

| Agent | Role | Lines |
|---|---|---|
| scout | Searches literature, scores papers, builds a reading list | 71 |
| deep-reader | Reads papers in depth, extracts claims/data, maps sections | 86 |
| critic | Assesses structure, checks style/journal/figure compliance | 94 |
| paper-writer | Writes or revises paper sections from outline | 110 |
| research-coder | Generates analysis scripts and figures from data | 93 |
| figure-stylist | Reviews figures for visual clarity and print readiness | 56 |

## Adding a new agent

1. Copy `agent-template.md` and fill in each section
2. Target **60 lines or fewer** — keep workflows tight, offload verbose templates to `specs/`
3. Place the new `.md` file in this directory (`.claude/agents/`)
4. If the agent produces structured output, add a `specs/<agent>-output-format.md` file

## Key conventions

- Agents read `checkpoint.md` for state and write it back with the next task
- Output format templates live in `specs/*-output-format.md`, not inline
- Deterministic checks use scripts in `scripts/` — agents call them, not replicate them
