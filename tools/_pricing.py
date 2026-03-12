"""Shared pricing table for Anthropic models.

Single source of truth — imported by ralph_agent.py and scripts/usage_report.py.
"""

# Per-million-token pricing (as of 2025-05)
# Source: https://docs.anthropic.com/en/docs/about-claude/models
PRICING = {
    "claude-opus-4-6":   {"input": 15.0, "output": 75.0, "cache_read": 1.5,  "cache_create": 18.75},
    "claude-sonnet-4-6": {"input": 3.0,  "output": 15.0, "cache_read": 0.3,  "cache_create": 3.75},
    "claude-haiku-4-5":  {"input": 0.8,  "output": 4.0,  "cache_read": 0.08, "cache_create": 1.0},
}
