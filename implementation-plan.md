# Implementation Plan — harden-planner-and-fix-runtime

**Thread:** harden-planner-and-fix-runtime
**Created:** 2026-03-23
**Architecture:** serial
**Autonomy:** autopilot

## Phase A: Planner Hardening

- [x] 1. Add TDD task-format spec to planner prompts — **coder**
  Changes:
  - `prompt-plan.md` after line 68: append TDD format spec
  - `.claude/agents/plan.md` line 84: add commit gate for TDD sub-fields
  VERIFY: grep -q 'RED:.*test file' prompt-plan.md && grep -q 'RED:.*GREEN:.*VERIFY:' .claude/agents/plan.md
  Commits: chore: add TDD task-format spec to planner layer

- [ ] 2. Add validate_plan_tdd_structure and wire into build start (red/green TDD, depends: 1) — **coder**
  RED: create `tests/test_plan_tdd_validation.sh`
    Setup: source `lib/post-run.sh`; use `mktemp -d` with cleanup trap; use `pass()`/`fail()` helpers (same pattern as `test_single_task_enforcement.sh`)
    Test A: plan with coder TDD task missing `RED:` line
      Plan content: `- [ ] 1. Add feature (red/green TDD) — **coder**\n  GREEN: lib/foo.sh\n  VERIFY: bash tests/test_foo.sh\n  Commits: test(red): x and fix(green): y`
      Assert: `validate_plan_tdd_structure` returns 1 (reject)
      Fails because: function does not exist yet
    Test B: plan with coder TDD task missing `GREEN:` line
      Plan content: `- [ ] 1. Add feature (red/green TDD) — **coder**\n  RED: tests/test_foo.sh test_a\n  VERIFY: bash tests/test_foo.sh\n  Commits: test(red): x and fix(green): y`
      Assert: `validate_plan_tdd_structure` returns 1 (reject)
    Test C: complete coder TDD task (all 4 fields present)
      Plan content: `- [ ] 1. Add feature (red/green TDD) — **coder**\n  RED: tests/test_foo.sh\n  GREEN: lib/foo.sh\n  VERIFY: bash tests/test_foo.sh\n  Commits: test(red): x and fix(green): y`
      Assert: `validate_plan_tdd_structure` returns 0 (accept)
    Test D: non-coder task (`— **critic**`, no TDD annotation)
      Assert: `validate_plan_tdd_structure` returns 0 (accept)
    Test E: coder task WITHOUT "red/green TDD" annotation
      Plan content: `- [ ] 1. Update prompt text — **coder**`
      Assert: `validate_plan_tdd_structure` returns 0 (accept, not a TDD task)
  GREEN:
    `lib/post-run.sh`: add `validate_plan_tdd_structure(plan_path)` after line 39
      Algorithm:
      1. grep for unchecked task lines containing both `red/green TDD` and `\*\*coder\*\*` (order-independent)
      2. for each match, read subsequent indented lines until next `^\- \[` or EOF
      3. check that at least one line matches each of: `RED:`, `GREEN:`, `VERIFY:`, `Commits:`
      4. if any field missing, echo which task and field, return 1
      5. if all tasks pass, return 0
    `ralph-loop.sh`: insert validation call after argument parsing, before main while loop (around line 200). If `validate_plan_tdd_structure "implementation-plan.md"` returns nonzero, echo error and `exit 1`
  VERIFY: bash tests/test_plan_tdd_validation.sh
  Commits: test(red): add plan TDD structure validation tests (A-E) and fix(green): implement validate_plan_tdd_structure in post-run.sh

## Phase B: Remaining Fixes

- [ ] 3. Exit nonzero on multi-task violation (red/green TDD) — **coder**
  RED: append test F to `tests/test_single_task_enforcement.sh`
    Test F: `halt_loop_with_error` sets LOOP_EXIT_CODE
      Setup: `LOOP_EXIT_CODE=0`
      Call: `halt_loop_with_error`
      Assert: `$LOOP_EXIT_CODE -ne 0`
      Guard: `type halt_loop_with_error &>/dev/null` (same guard pattern as tests A-E)
      Fails because: `halt_loop_with_error` function does not exist yet
  GREEN:
    `lib/post-run.sh`: add `halt_loop_with_error()` function (after `validate_single_task_completion`):
      ```bash
      halt_loop_with_error() {
        LOOP_EXIT_CODE=1
      }
      ```
    `ralph-loop.sh` line 349 (before main while loop): add `LOOP_EXIT_CODE=0`
    `ralph-loop.sh` line 578: change `break` to `halt_loop_with_error; break`
    `ralph-loop.sh` after line 618 (`done`): add `exit ${LOOP_EXIT_CODE:-0}`
  VERIFY: bash tests/test_single_task_enforcement.sh
  Commits: test(red): add halt_loop_with_error test F and fix(green): propagate nonzero exit on multi-task violation

- [ ] 4. Detect actual newly-checked tasks via set diff (red/green TDD, depends: 3) — **coder**
  RED: append test G to `tests/test_single_task_enforcement.sh`
    Test G: check+uncheck swap with 2 newly checked tasks
      before.md via `make_plan`: `"x First task — **coder**" "  Second task — **scout**" "  Third task — **critic**"`
      after.md via `make_plan`: `"  First task — **coder**" "x Second task — **scout**" "x Third task — **critic**"`
      Count-based delta: after(2) - before(1) = 1 → current validator says OK (bug)
      Set-based: newly_checked = {2, 3} → 2 → violation
      Assert: `! validate_single_task_completion` (returns 1, violation detected)
      Fails because: count-based implementation computes delta=1 and allows it
  GREEN:
    `lib/post-run.sh`: rewrite `validate_single_task_completion` (lines 24-39):
      ```bash
      validate_single_task_completion() {
        local before=$1
        local after=$2
        local before_set after_set newly_checked count

        before_set=$(grep '^\- \[x\]' "$before" 2>/dev/null \
          | sed 's/^- \[x\] \([0-9][0-9]*\)\..*/\1/' | sort -n) || true
        after_set=$(grep '^\- \[x\]' "$after" 2>/dev/null \
          | sed 's/^- \[x\] \([0-9][0-9]*\)\..*/\1/' | sort -n) || true

        newly_checked=$(comm -13 <(printf '%s\n' $before_set | grep -v '^$') \
                                 <(printf '%s\n' $after_set | grep -v '^$')) || true
        count=$(echo "$newly_checked" | grep -c '[0-9]') || count=0

        if [ "$count" -gt 1 ]; then
          echo "  ✗ Multi-task violation: tasks $(echo $newly_checked | tr '\n' ',' | sed 's/,$//') completed in one iteration (max 1)"
          return 1
        fi
        return 0
      }
      ```
    Verify existing tests A-E still pass (they do — set-based produces same results for those cases)
  VERIFY: bash tests/test_single_task_enforcement.sh
  Commits: test(red): add set-based detection test G and fix(green): detect actual newly-checked tasks via set diff

- [ ] 5. Section filter dot-boundary matching (red/green TDD) — **coder**
  RED: create `tests/test_section_filter_scoping.py`
    ```python
    """RED test: section_filter='1' must not match section '10'."""
    import json, os
    from pathlib import Path
    from tools.verify import _handle_verify_cited_claims

    def test_filter_1_excludes_10(tmp_path):
        """section_filter='1' matches '1' and '1.1' but not '10' or '2.1'."""
        tracker = tmp_path / "tracker.jsonl"
        tracker.write_text(
            '{"doi":"10.1/a","section":"1","claim":"claim a","role":"support"}\n'
            '{"doi":"10.1/b","section":"1.1","claim":"claim b","role":"support"}\n'
            '{"doi":"10.1/c","section":"10","claim":"claim c","role":"support"}\n'
            '{"doi":"10.1/d","section":"2.1","claim":"claim d","role":"support"}\n'
        )
        ledger = tmp_path / "ledger.jsonl"
        ledger.write_text("")
        papers = tmp_path / "papers"
        papers.mkdir()
        output = tmp_path / "output"
        _handle_verify_cited_claims({
            "tracker_file": str(tracker),
            "ledger_file": str(ledger),
            "bib_file": "",
            "papers_dir": str(papers),
            "section_filter": "1",
            "output_dir": str(output),
        })
        verdicts = [json.loads(l) for l in (output / "verify_report.jsonl").read_text().strip().split("\n")]
        sections = {v["section"] for v in verdicts}
        assert sections == {"1", "1.1"}, f"Expected {{'1', '1.1'}}, got {sections}"

    def test_filter_exact_match(tmp_path):
        """section_filter='2.1' matches only '2.1'."""
        tracker = tmp_path / "tracker.jsonl"
        tracker.write_text(
            '{"doi":"10.1/a","section":"2","claim":"x","role":"support"}\n'
            '{"doi":"10.1/b","section":"2.1","claim":"y","role":"support"}\n'
            '{"doi":"10.1/c","section":"2.10","claim":"z","role":"support"}\n'
        )
        ledger = tmp_path / "ledger.jsonl"
        ledger.write_text("")
        papers = tmp_path / "papers"
        papers.mkdir()
        output = tmp_path / "output"
        _handle_verify_cited_claims({
            "tracker_file": str(tracker),
            "ledger_file": str(ledger),
            "bib_file": "",
            "papers_dir": str(papers),
            "section_filter": "2.1",
            "output_dir": str(output),
        })
        verdicts = [json.loads(l) for l in (output / "verify_report.jsonl").read_text().strip().split("\n")]
        sections = {v["section"] for v in verdicts}
        assert sections == {"2.1"}, f"Expected {{'2.1'}}, got {sections}"
    ```
    test_filter_1_excludes_10 fails because startswith("1") matches "10" → 3 verdicts not 2
    test_filter_exact_match fails because startswith("2.1") matches "2.10" → 2 verdicts not 1
  GREEN:
    `tools/verify.py`: add helper at module level (after `_pdf_text_cache = {}` at line 31):
      ```python
      def _section_matches(section, filter_val):
          """Match section exactly or as dot-separated prefix."""
          return section == filter_val or section.startswith(filter_val + ".")
      ```
    `tools/verify.py` line 50: replace
      `entries = [e for e in entries if e.get("section", "").startswith(section_filter)]`
    with
      `entries = [e for e in entries if _section_matches(e.get("section", ""), section_filter)]`
  VERIFY: pytest tests/test_section_filter_scoping.py
  Commits: test(red): add section filter boundary tests and fix(green): use dot-boundary prefix matching

- [ ] 6. Final review — verify all tests pass, no regressions, acceptance criteria met (depends: 1,2,3,4,5) — **critic**
