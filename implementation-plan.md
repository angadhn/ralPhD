# Implementation Plan — tool-call-prototype

**Thread:** tool-call-prototype
**Created:** 2026-03-10

## Goal

Prototype a thin Python runner (`ralph_agent.py`) that can replace `claude -p` inside `ralph-loop.sh`, giving per-agent tool registries (e.g., paper-writer gets `check_language`, scout doesn't) instead of Claude Code's full ~20+ built-in tool set.

Based on ghuntley's agent architecture: https://ghuntley.com/agent and https://github.com/ghuntley/how-to-build-a-coding-agent

## Context / Key Learnings from Session

1. **ghuntley's model**: ~200 lines of Go. A loop that calls the Claude API with registered tools, executes them, feeds results back, repeats until the model stops requesting tools. His repo is a progressive tutorial: `chat.go` → `read.go` → `list_files.go` → `bash_tool.go` → `edit_tool.go`.

2. **Our agents are prompts, not agents.** The `.claude/agents/*.md` files are system prompts loaded by Claude Code (which is the actual agent loop). ghuntley's architecture makes the distinction clear: the agent = the loop + tool registry, the prompt = behavioral guidance.

3. **Auth solved**: OAuth tokens (`sk-ant-oat01-...`) work with the Python SDK — they must be sent via `X-Api-Key` header (pass as `api_key=`), NOT `Authorization: Bearer` (pass as `auth_token=`). The API rejects Bearer-based OAuth. `get_client()` reads the fresh token from macOS keychain (`security find-generic-password -s "Claude Code-credentials"`). No `.env` or `ANTHROPIC_API_KEY` needed.

4. **`ralph_agent.py` is tested and working** (~270 lines). Keychain auth, tool definitions with typed schemas, per-agent tool registries, the core agent loop. Tested successfully with `claude-haiku-4-5-20251001`.

5. **Prompt changes are minimal.** Agent prompts lose explicit `python scripts/check_language.py <file>` commands and gain shorter nudges like "run commit gates" because the tool schema carries the invocation details.

6. **Future vision: `toolsmith` agent.** Once `ralph_agent.py` works, a new agent could create new agents (from `agent-template.md`) and write tool wrappers, making ralph self-extending.

7. **Howler precedent (research-companion):** Production system at ~9,200 LOC, 52 files, 21 agents, 8+ tools. Key architectural lessons: (a) tools as separate files in a directory — toolsmith drops files, not edits a monolith; (b) `agent-templates/` directory with an `index.ts` collector; (c) reusable prompt blocks (`prompts/blocks/`). Howler has NO per-agent tool control (any agent calls any script) — ralPhD's `AGENT_TOOLS` registry is strictly better.

8. **Tool coverage gap:** `citation_tools.py` (715 lines, 7 subcommands) is the biggest script but only `lint` is wrapped as a tool. Scout references `batch-lookup` in its prompt but must fall back to bash. Also missing ghuntley's `list_files` and `code_search` primitives (2 of his 5 essential tools).

9. **Growth path:** Benchmarking plan + Howler precedent point toward 15-20 agents and 15+ tools. The `tools/` directory split is motivated by this trajectory, not just current file length (464 lines).

## What exists already

- `ralph_agent.py` — written, parses, untested (auth blocker)
- `.env` — exists, gitignored, needs valid `ANTHROPIC_API_KEY`
- `.gitignore` — updated to exclude `.env`

## What changes (when unblocked)

### `ralph_agent.py` (exists, needs testing)

- Loads `.claude/agents/<name>.md` as system prompt
- Per-agent tool registries: `AGENT_TOOLS` dict maps agent name → tool list
- Tools: `check_language`, `read_file`, `write_file`, `bash`
- Tries auth in order: `CLAUDE_CODE_OAUTH_TOKEN` env var → keychain OAuth → `ANTHROPIC_API_KEY`
- Usage: `python ralph_agent.py --agent paper-writer --task "Write the methods section"`

### `.claude/agents/paper-writer.md` (lines 42-44, 94-96)

Commit gate prose commands → short nudges (model sees tools in registry).

### `.claude/agents/critic.md` (lines 22-23, 37, 71)

Explicit `python scripts/check_language.py` commands → "run check_language on the section file".

### `ralph-loop.sh` line 336

`claude -p` → `python ralph_agent.py --agent "$CURRENT_AGENT" --task "$PROMPT"` (only after testing).

## Tasks

- [x] 1. Write `ralph_agent.py` with tool-calling loop, `check_language`, `read_file`, `write_file`, `bash` — **human**
- [x] 2. ~~BLOCKER~~: OAuth token works via `X-Api-Key` header (not `Authorization: Bearer`). Keychain auth, no API key needed — **human**
- [x] 3. Test `ralph_agent.py` standalone: `python ralph_agent.py --agent paper-writer --task "Read checkpoint.md"` — **human**
- [x] 4. Update `paper-writer.md` commit gate references — **human**
- [x] 5. Update `critic.md` — all 6 script invocations simplified to tool names — **human**
- [x] 6. Test: critic called `check_language` as registered tool (not bash) — **human**
- [x] 7. Wire `ralph-loop.sh` line 336 to call `ralph_agent.py` — **human**
- [x] 8. Split `ralph_agent.py` into loop + `tools/` directory: `ralph_agent.py` keeps loop/auth/CLI (201 lines), `tools/__init__.py` has TOOLS registry + AGENT_TOOLS + `execute_tool()` + `get_tools_for_agent()`, `tools/core.py` has read_file/write_file/bash, `tools/checks.py` has check_language/check_journal/check_figure/citation_lint, `tools/pdf.py` has pdf_metadata/extract_figure — **research-coder**
- [x] 9. Complete tool inventory: wrapped `citation_lookup` (single+batch), `citation_verify`, `citation_manifest` (check+add); added `list_files` and `code_search` (ripgrep) as ghuntley's essential primitives; all agents now get 5 essentials; scout gets citation_lookup/verify/manifest; fixed figure-stylist to reference check_figure in workflow. 14 tools total, 6 agents. — **research-coder**
- [ ] 10. Interview user about which Howler agents to port — Howler has 15 agents ralPhD lacks (section editors, coherence-reviewer, triage, synthesizer, peer-reviewer, revision-agent, provocateur, etc.); determine priority and tool requirements for each — **human**
- [ ] 11. End-to-end test through ralph-loop — **human**
- [ ] 12. (Future) Create `toolsmith.md` agent + `tools/registry.json` for self-extending capability — toolsmith drops new files in `tools/`, adds entries to AGENT_TOOLS — **human**

## Key design decisions

**Why start with just check_language?** Simplest case: one input (file path), one optional flag (strict), structured text output. Same pattern extends to `check_journal`, `check_figure`, `citation_tools`.

**Why keep bash as a tool?** Agents still need git commit, pdflatex, etc. Bash is the escape hatch — same as ghuntley's model.

**Why not Agent SDK?** This prototype is about understanding the mechanics. The raw API loop is visible. Agent SDK can replace it later with zero prompt changes.

**Why not just simplify prompts and keep `claude -p`?** That's a valid interim step (and works today with no auth blocker). But it doesn't give per-agent tool registries — every agent still sees Claude Code's full tool set, which is ghuntley's core criticism about context allocation.

**What's lost vs Claude Code?** Permission management, context compression, subagent spawning, the TUI, git safety checks. This is a prototype — trades those for control over tool registration.

**Why split into `tools/` now?** Not because 464 lines is too long today, but because the growth path demands it. Toolsmith needs to drop files, not edit a monolith. Howler's production system (21 agents, 8+ tools) uses separate tool files. The split is: `tools/__init__.py` (registry + AGENT_TOOLS), `tools/core.py` (read/write/bash), `tools/checks.py` (language/journal/figure/citation), `tools/pdf.py` (metadata/extract). ralph_agent.py keeps loop + auth + CLI.

**Why complete `citation_tools.py` wrapping?** Scout's prompt references `batch-lookup` but must use bash — violates the colocated design. At 715 lines and 7 subcommands, it's our biggest script and the most tool-ready. Also: ghuntley's 5 essential tools include `list_files` and `code_search` — we're missing both.
