# AI-Generated Outputs

All agent outputs land here, organized by thread and agent.

A **thread** is a named research effort (e.g., `SDC-survey`, `thermal-analysis`). Set it in `checkpoint.md` and agents use it as the top-level directory.

```
ai-generated-outputs/
├── <thread>/
│   ├── scout-corpus/          # scout: scored papers, search reports, .bib files
│   ├── triage/                # triage: deduped corpus index, reading plan, triage report
│   ├── deep-analysis/         # deep-reader: notes, section map, report, reference figures
│   │   └── reference-figures/ # Figures extracted from source PDFs
│   ├── critic-review/         # critic: review reports, figure proposals
│   ├── provocations/          # provocateur: stress-test findings, gap analysis
│   ├── synthesis/             # synthesizer: synthesis narrative, master.bib, section outline
│   ├── writing/               # paper-writer: outline, sections (.tex), cited tracker
│   ├── editor/                # editor: change logs, substantiated edits
│   ├── coherence-review/      # coherence-reviewer: coherence reports
│   └── research-code/         # research-coder: scripts, figures, data outputs
└── reflections/               # Loop reflections (every 5th iteration)
    └── reflection-iter-N.md
```

Each agent reads from upstream directories and writes to its own. The flow is roughly:

```
scout-corpus → triage → deep-analysis → critic-review → provocations → synthesis
  → writing → editor → coherence-review → research-code
                                              ↓
                                        figure-stylist (reviews in-place)
```

Figure-stylist reviews figures in-place and writes feedback to `research-code/`.

Reflections are not tied to a thread — they assess the loop's overall trajectory.
