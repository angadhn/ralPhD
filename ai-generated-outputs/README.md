# AI-Generated Outputs

All agent outputs land here, organized by thread and agent.

A **thread** is a named research effort (e.g., `SDC-survey`, `thermal-analysis`). Set it in `checkpoint.md` and agents use it as the top-level directory.

```
ai-generated-outputs/
├── <thread>/
│   ├── scout-corpus/          # scout: scored papers, search reports, .bib files
│   ├── deep-analysis/         # deep-reader: notes, section map, report, reference figures
│   │   └── reference-figures/ # Figures extracted from source PDFs
│   ├── critic-review/         # critic: review reports, figure proposals
│   ├── writing/               # paper-writer: outline, sections (.tex), cited tracker
│   └── research-code/         # research-coder: scripts, figures, data outputs
└── reflections/               # Loop reflections (every 5th iteration)
    └── reflection-iter-N.md
```

Each agent reads from upstream directories and writes to its own. The flow is roughly:

```
scout-corpus → deep-analysis → critic-review → writing
                    ↓                              ↑
              research-code ───────────────────────┘
```

Figure-stylist reviews figures in-place and writes feedback to `research-code/`.

Reflections are not tied to a thread — they assess the loop's overall trajectory.
