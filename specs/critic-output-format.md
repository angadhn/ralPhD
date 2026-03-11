# Critic Output Format

## HUMAN_REVIEW_NEEDED.md — Survey Assessment Section

```markdown
## Survey Assessment

### Weak Arguments (need bolstering)
- [Section]: [claim] — evidence is [issue]. Suggestion: [fix]

### Contradictions (human should weigh in)
- [Paper A] vs [Paper B] on [topic]: [nature of contradiction]

### Structural Suggestions
- [Sections to merge/split/reorder with reasoning]

### Figure Proposals (approve/reject each)
- [ ] **Fig 1: [Title]** — [Type], data from [sources]. Purpose: [1 sentence]
- [ ] **Fig 2: [Title]** — [Type], data from [sources]. Purpose: [1 sentence]

### Ready for Writing?
[Assessment of whether the corpus + analysis is sufficient to begin writing]
```

## HUMAN_REVIEW_NEEDED.md — Style Check Section

```markdown
## Style Check — [Section Name]

### check_language.py Results
- [Output from the script]

### Claim Calibration Issues
- [Line/paragraph]: [claim] uses "[strong verb]" but evidence level is [weaker]. Suggest: "[calibrated alternative]"

### Writing Style Violations
- [Specific violations of specs/writing-style.md rules]

### Claim-Source Mismatches
- [CLAIM-SOURCE MISMATCH] DOI [doi], Section [N.M]: cited_tracker claims "[claim text]" but deep-reader notes [do not mention this / state something different: "[what notes say]"]

### Verdict: [PASS / REVISE]
```

## HUMAN_REVIEW_NEEDED.md — Journal Compliance Section

```markdown
## Journal Compliance Check

### Word Count
- Target: [limit] | Current: [count] | Status: [OK / OVER by N]

### Citation Style
- [Issues found, if any]

### Page Limit
- Target: [limit] | Current: [count] | Status: [OK / OVER by N]

### Other Requirements
- [Any other journal-specific issues]
```

## HUMAN_REVIEW_NEEDED.md — Figure Compliance Section

```markdown
## Figure Compliance Check

### fig_NN_short_name
- DPI: [value] — [OK / BELOW minimum of N]
- Dimensions: [W x H] — [OK / EXCEEDS limit]
- Color: [OK / USES non-allowed colors]

### fig_MM_short_name
...
```
