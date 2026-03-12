"""Interactive tools: ask_choice, ask_question.

Let agents interact with the user during planning sessions.
Questions print to stderr (visible in the terminal) and responses
are read from /dev/tty (the actual terminal, not stdin which may be piped).
"""

import sys


def _read_terminal_line(prompt_text=""):
    """Read a line from the terminal (/dev/tty), bypassing stdin."""
    try:
        with open("/dev/tty", "r") as tty:
            if prompt_text:
                print(prompt_text, end="", file=sys.stderr, flush=True)
            return tty.readline().strip()
    except OSError:
        return ""


def _handle_ask_choice(inp):
    question = inp["question"]
    options = inp["options"]

    print(f"\n{question}\n", file=sys.stderr)
    for i, opt in enumerate(options, 1):
        print(f"  {i}. {opt}", file=sys.stderr)
    print(file=sys.stderr)

    while True:
        response = _read_terminal_line("Your choice (number or text): ")
        if not response:
            return "Error: no terminal available for interactive input"

        # Accept a number
        try:
            idx = int(response) - 1
            if 0 <= idx < len(options):
                chosen = options[idx]
                print(f"  → {chosen}\n", file=sys.stderr)
                return chosen
            else:
                print(f"  Please enter 1–{len(options)}.", file=sys.stderr)
                continue
        except ValueError:
            pass

        # Accept free text (for "other" style options or elaboration)
        print(f"  → {response}\n", file=sys.stderr)
        return response


def _handle_ask_question(inp):
    question = inp["question"]

    print(f"\n{question}\n", file=sys.stderr)

    response = _read_terminal_line("> ")
    if not response:
        return "Error: no terminal available for interactive input"

    print(f"  → {response}\n", file=sys.stderr)
    return response


TOOLS = {
    "ask_choice": {
        "name": "ask_choice",
        "description": (
            "Present a multiple-choice question to the user and return their "
            "selection. The user sees numbered options and can pick by number "
            "or type a free-text answer. Use for structured intake questions "
            "where there are clear categories."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "question": {
                    "type": "string",
                    "description": "The question to display",
                },
                "options": {
                    "type": "array",
                    "items": {"type": "string"},
                    "description": "List of options. The user can pick one or type a free-text answer.",
                },
            },
            "required": ["question", "options"],
        },
        "function": _handle_ask_choice,
    },
    "ask_question": {
        "name": "ask_question",
        "description": (
            "Ask the user an open-ended question and return their free-text "
            "answer. Use when you need a detailed or unpredictable response "
            "rather than a choice from fixed options."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "question": {
                    "type": "string",
                    "description": "The question to display",
                },
            },
            "required": ["question"],
        },
        "function": _handle_ask_question,
    },
}
