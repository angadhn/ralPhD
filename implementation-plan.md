# Implementation Plan — harden-planner-and-fix-runtime (remaining gaps)

**Thread:** harden-planner-remaining-gaps
**Created:** 2026-03-23
**Architecture:** serial
**Autonomy:** stage-gates

## Tasks

- [x] 1. Enforce planner placeholder ban in `validate_plan_tdd_structure` (red/green TDD) — **coder**
    RED: `tests/test_plan_tdd_validation.sh` tests F/G/H: reject `RED: ...`, `GREEN: TBD`, `RED: write a test showing ...`; confirm test C still passes
    GREEN: `lib/post-run.sh:validate_plan_tdd_structure` — after line 75, grep RED:/GREEN: lines for `\.\.\.|TBD|TODO|write a test showing`, set rc=1 if matched
    VERIFY: `bash tests/test_plan_tdd_validation.sh`
    Commits: `test(red): add placeholder rejection tests F/G/H` and `fix(green): reject placeholder content in RED:/GREEN: TDD lines`

- [x] 2. Add non-numeric section scoping end-to-end regression test (red/green TDD) — **coder**
    RED: `tests/test_section_filter_scoping.py` `test_filter_nonnumeric_introduction`: sections `"introduction"`, `"methods"`, `"intro"` → filter `"introduction"` → assert `{"introduction"}`
    GREEN: No production change expected — `tools/verify.py:_section_matches` already handles non-numeric ids. If test fails, fix `_section_matches`.
    VERIFY: `python -m pytest tests/test_section_filter_scoping.py::test_filter_nonnumeric_introduction -v`
    Commits: `test(red): add non-numeric section filter regression test` and `fix(green): confirm non-numeric filtering works`

- [x] 3. Document build-start validation timing in `ralph-loop.sh` — **coder**
    Replace comment at line 70 with explanation: planner commit gates are primary, build-start is safety net, fail fast before wasting an iteration.
    VERIFY: `grep -A3 'safety net' ralph-loop.sh`
    Commits: `docs: explain build-start TDD validation as safety net`
