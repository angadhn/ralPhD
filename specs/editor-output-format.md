# Editor Output Format

## change_log.md structure (per section)

One change log per editor iteration. Each iteration edits one section.

```markdown
# Editor Change Log — [Section Name]

**Section:** sections/XX-section-name.tex
**Date:** YYYY-MM-DD
**Pre-edit check_language issues:** N
**Post-edit check_language issues:** M
**Pre-edit check_claims flags:** K unsupported claims

## Changes

1. **[Line ~NN]** <what changed> — *Reason:* <justification citing evidence/venue/style rule>
2. **[Line ~NN]** <what changed> — *Reason:* <justification>
3. **[Line ~NN]** <what changed> — *Reason:* <justification>
...

## Unresolved Concerns

- <issue found but not fixed> — *Deferred because:* <reasoning>
- <issue found but not fixed> — *Deferred because:* <reasoning>

## Tool Diagnostics

### check_claims (pre-edit)
- [Summary of flagged claims: unsupported, low-confidence, stale]

### check_language (pre-edit → post-edit)
- Issue count: N → M ([increased/decreased/unchanged])
- [Notable issues resolved or introduced]

### citation_lint (if citations modified)
- [Pass/fail, issues found]

### citation_verify_all (if new citations added)
- [Pass/fail, unverified DOIs]
```

## Justification categories

Every change in the Changes list must cite exactly one justification type:

| Category | Format | Example |
|----------|--------|---------|
| Evidence ledger | `Evidence: [source_key] — [claim]` | `Evidence: Chen2024 — "dropout rates plateau above 0.3"` |
| Venue requirement | `Venue: [requirement]` | `Venue: word limit 8000, section was 15% over target` |
| Style rule | `Style: [rule from writing-style.md]` | `Style: avoid hedging stacks ("may potentially suggest")` |
| Claim calibration | `Calibration: [evidence level] → [language adjustment]` | `Calibration: single-study finding → changed "demonstrates" to "suggests"` |
| Critic feedback | `Critic: [item from report.tex]` | `Critic: "Section 3.2 transition is abrupt"` |
| Structural clarity | `Clarity: [reasoning]` | `Clarity: split 6-line sentence into two for readability` |

Edits without a justification from one of these categories are not permitted.

## File locations

```
sections/XX-section-name.tex                    # Edited in-place (git-diffable)
AI-generated-outputs/<thread>/editor/
└── change_log.md                               # Overwrites each iteration
```

### Multi-section editing sequence

When editing multiple sections across iterations, the change log is overwritten each iteration (one section per iteration). The full editing history is preserved in git commits. The checkpoint Knowledge State table tracks which sections have been edited.

## Commit gates (checked before final commit)

- [ ] `check_language` issue count did not increase (post ≤ pre)
- [ ] Every entry in the Changes list has a `*Reason:*` field
- [ ] Each `*Reason:*` uses one of the six justification categories
- [ ] No untracked style violations introduced
- [ ] If citations modified: `citation_lint` passes
- [ ] If new citations added: `citation_verify_all` passes
- [ ] Unresolved Concerns section is present (even if empty — write "None")

## Minimal edit principle

The editor does not restructure or rewrite. The diff between pre-edit and post-edit .tex files should be minimal:
- No reformatting of untouched paragraphs
- No reordering of content unless a clear structural defect is documented
- No changes to the author's voice or register
- Insertions/deletions should be line-level, not paragraph-level, wherever possible
