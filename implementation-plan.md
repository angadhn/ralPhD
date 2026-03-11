# Implementation Plan — howler-port

**Thread:** howler-port
**Created:** 2026-03-11
**Autonomy:** stage-gates

Source design doc: `archive/plan-tool-call-prototype.md` task 11.
Interview decisions and full rationale are in this session's transcript.

## Phase 1: New Tools
<!-- gate -->

- [x] 1. Create `specs/evidence-format.md` — evidence-ledger JSONL schema (claim, source_key, extraction_type, confidence). Schema from `archive/plan-benchmarking-eval.md` section 3a. — **research-coder**
- [x] 2. Create `tools/claims.py` — `check_claims` tool. Reads a .tex file + `evidence-ledger.jsonl`, flags: claims with no ledger entry, low-confidence inferences, stale entries (source not in current bibliography). Register in `tools/__init__.py`: import `_claims_tools`, add to TOOLS, add to AGENT_TOOLS for editor, critic, coherence-reviewer. Follow pattern in `tools/checks.py`. — **research-coder**
- [x] 3. Add `citation_verify_all` tool to `tools/checks.py` — batch-verifies every entry in a .bib file via CrossRef/DOI (wraps `scripts/citation_tools.py verify` in a loop). Register in `tools/__init__.py` AGENT_TOOLS for scout, editor, critic, triage, synthesizer. — **research-coder**

## Phase 2: Editor Cycle
<!-- gate -->

- [x] 4. Create `.claude/agents/editor.md` — lean prompt. Role: academic editor making substantiated improvements. Workflow: read section → read venue context (`specs/publication-requirements.md`, `inputs/` if present) → make direct edits to .tex → leave git-diffable changes. Every edit substantiated (cite evidence, venue requirements, or reasoning). Tools: `_ESSENTIALS` + `check_claims`, `check_language`, `citation_lint`, `citation_verify_all`. Follow existing agent format (see `critic.md`, `paper-writer.md`). — **research-coder**
- [x] 5. Create `specs/editor-output-format.md` — what editor's checkpoint output looks like (sections edited, changes summary, unresolved concerns). Follow pattern from existing output format specs. — **research-coder**
- [x] 6. Create `.claude/agents/coherence-reviewer.md` — runs after all editing passes. Checks: promise-delivery alignment (intro vs results), terminology consistency, internal contradictions, novelty claims vs related work. Tools: `_ESSENTIALS` + `check_claims`, `check_language`. — **research-coder**
- [x] 7. Create `specs/coherence-reviewer-output-format.md` — output format for coherence reviews. — **research-coder**
- [x] 8. Update `.claude/agents/paper-writer.md` — add REVIEW-EDITS mode: after editor makes changes, paper-writer receives a git diff and accepts/reverts changes with reasoning. Add to existing mode detection in the prompt. — **research-coder**

## Phase 3: Analysis Agents
<!-- gate -->

- [x] 9. Create `.claude/agents/provocateur.md` — finds gaps no other agent covers. Cross-domain bridges, inverted assumptions, negative space. Reads deep-reader reports + critic output. Outputs `provocations.md`. Tools: `_ESSENTIALS` only. — **research-coder**
- [x] 10. Create `specs/provocateur-output-format.md` — provocations output format. — **research-coder**
- [x] 11. Create `.claude/agents/synthesizer.md` — merges critic review + deep-reader reports into section outline, merged master.bib, synthesis narrative. Tools: `_ESSENTIALS` + `citation_lint`, `citation_verify_all`. — **research-coder**
- [x] 12. Create `specs/synthesizer-output-format.md` — synthesizer output format. — **research-coder**
- [x] 13. Create `.claude/agents/triage.md` — sits between scout and deep-reader. Corpus deduplication, grade conflict resolution, reading plan generation. Tools: `_ESSENTIALS` + `pdf_metadata`, `citation_verify_all`. — **research-coder**
- [ ] 14. Create `specs/triage-output-format.md` — triage output format. — **research-coder**

## Phase 4: Critic Update
<!-- gate -->

- [ ] 15. Update `.claude/agents/critic.md` — add FIGURE-PROPOSAL mode. After reviewing deep-reader reports, identify claims needing visual support. Output `figure_proposals.md`: what figure, what data, why effective. research-coder implements, figure-stylist reviews. — **research-coder**
- [ ] 16. Update `specs/critic-output-format.md` — add figure proposal format section. — **research-coder**

## Phase 5: Venue Convention + Housekeeping
<!-- gate -->

- [ ] 17. Update `scripts/init-project.sh` — create `inputs/` directory during project init. Add comment documenting the convention (feedback, prior submissions, venue-specific docs). — **research-coder**
- [ ] 18. Update `.claude/agents/README.md` — add new agents (editor, coherence-reviewer, provocateur, synthesizer, triage) with tool summaries. Document `inputs/` convention. — **research-coder**

## Phase 6: Prompt Audit
<!-- gate -->

- [ ] 19. Audit all agent prompts against prompt quality checklist. For each `.claude/agents/*.md` file: (1) remove role-playing language — no "You are an expert X", just state the task; (2) convert negative prompts — change "Don't do X" to positive instructions; (3) compress — if a section can be shorter without losing meaning, shorten it; (4) check that mechanical procedures live in tools/specs, not baked into the prompt; (5) measure token cost of each prompt and report. Reference: Anthropic context engineering guide (https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents), Claude 4 best practices (https://docs.anthropic.com/en/docs/build-with-claude/prompt-engineering/claude-4-best-practices), ghuntley principle: agents reason, tools do mechanical work. — **research-coder**

## Phase 7: Verification
<!-- gate -->

- [ ] 20. Verify tool registration — run `python ralph_agent.py --agent editor --task "List your available tools"` and confirm check_claims + citation_verify_all appear. Run for all new agents. — **research-coder**
- [ ] 21. Verify agent file loading — run `python ralph_agent.py --agent <name> --task "Confirm you loaded successfully"` for each new agent (editor, coherence-reviewer, provocateur, synthesizer, triage). — **research-coder**
