# Implementation Plan — fix-verify-and-loop-semantics

**Thread:** fix-verify-and-loop-semantics
**Created:** 2026-03-23
**Architecture:** serial
**Autonomy:** autopilot

## Tasks

- [x] 1. Test and fix auto_download papers_dir mismatch (red/green TDD: write failing test proving `output_dir` key causes download to wrong dir, then fix `verify.py:170` to pass `papers_dir` key) — **coder**
- [x] 2. Test and fix terminal checkpoint dispatch (red/green TDD: write failing test showing prose like "Thread ready for review" extracts bogus agent; then fix `detect.sh` to use `<all tasks complete>` as canonical done marker, expand the case guard at line 25) — **coder**
- [x] 3. Test and fix DOI-to-BibTeX fail-open (red/green TDD: write tests for missing bibtexparser and missing .bib; then fix `_citation.py` to raise explicit errors, update `verify.py` to surface them) — **coder**
- [ ] 4. Test and fix one-task-per-iteration enforcement (red/green TDD: write test showing multi-task completion goes undetected; then add post-iteration validator in `ralph-loop.sh` comparing plan before/after, fail closed on violation) — **coder**
- [ ] 5. Final review of all 4 fixes — verify tests pass, check for regressions, confirm acceptance criteria (depends: 1,2,3,4) — **critic**
