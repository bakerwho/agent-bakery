"""Regex writing check for agent prose. Cheapest layer: no model, no network.

PostToolUse on Write/Edit of prose files: feedback only, never blocks, so a
deliberate quote still lands. PreToolUse on Bash: denies a commit message,
PR or issue text that contains an em dash, since that text reaches other
people and is cheap to fix before it is sent.
"""

import json
import os
import re
import sys

EM_DASH = "—"
PROSE_EXT = (".md", ".mdx", ".txt", ".html", ".rst")
# Files that quote the banned phrases as data.
EXEMPT = ("/.agents/hooks/", "/AGENTS.md", "/CLAUDE.md", "agent-rules", "writing-style", "de-ai-writing")

PHRASES = [
    (r"\bit(?:'s| is) worth noting\b", "it's worth noting"),
    (r"\bgame-changing\b", "game-changing"),
    (r"\brevolutionary\b", "revolutionary"),
    (r"\btransformative\b", "transformative"),
    (r"\bcutting-edge\b", "cutting-edge"),
    (r"\bbest-in-class\b", "best-in-class"),
    (r"\brobust(?:ly|ness)?\b", "robust"),
    (r"\bseamless(?:ly)?\b", "seamless"),
    (r"\bunlock(?:s|ed|ing)?\b", "unlock"),
    (r"\bempower(?:s|ed|ing)?\b", "empower"),
    (r"\bdelv(?:e|es|ed|ing)\b", "delve"),
    (r"\bleverag(?:es|ed|ing)\b|\bleverage (?:the|our|this|these|that|it|existing)\b", "leverage as a verb"),
    (r"\b(?:great|excellent) question\b", "canned praise"),
    (r"\bI hope this helps\b", "filler closer"),
    (r"\bin conclusion\b", "repeated summary closer"),
    (r"\blet's dive\b|\bdive into\b|\bdeep dive\b", "dive"),
    (r"[a-z,)] - [a-z(]", "spaced hyphen used as a dash"),
]


def findings(text):
    hits = []
    for lineno, line in enumerate(text.splitlines(), 1):
        if EM_DASH in line:
            hits.append((lineno, "em dash"))
        for pattern, label in PHRASES:
            if re.search(pattern, line, re.IGNORECASE if label != "spaced hyphen used as a dash" else 0):
                hits.append((lineno, label))
    return hits


def summarize(hits, limit=8):
    parts = ["line %d: %s" % hit for hit in hits[:limit]]
    if len(hits) > limit:
        parts.append("%d more" % (len(hits) - limit))
    return "; ".join(parts)


def post_write(data):
    tool_input = data.get("tool_input") or {}
    path = tool_input.get("file_path") or ""
    if not path.lower().endswith(PROSE_EXT) or any(e in path for e in EXEMPT):
        return
    text = tool_input.get("content") or tool_input.get("new_string") or ""
    hits = findings(text)
    if not hits:
        return
    where = "the text you wrote" if "new_string" in tool_input else os.path.basename(path)
    message = (
        "style-gate (feedback, not a block): %s has %s. Rewrite per the Writing rules in "
        "AGENTS.md (no em dashes or spaced hyphens; plain verbs; no filler) unless it is a "
        "deliberate quote. Line numbers count from the start of %s."
        % (os.path.basename(path), summarize(hits), where)
    )
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "PostToolUse", "additionalContext": message}}))


OUTBOUND = re.compile(r"\bgit\s+commit\b|\bgh\s+(pr|issue)\s+(create|edit|comment|review)\b|\bgh\s+api\b")
BODY_FILE = re.compile(r"(?:--body-file|--file|-F)[ =]['\"]?([^'\" ;|&]+)")


def pre_bash(data):
    command = (data.get("tool_input") or {}).get("command") or ""
    if not OUTBOUND.search(command):
        return
    text = command
    cwd = data.get("cwd") or "."
    for match in BODY_FILE.finditer(command):
        path = os.path.join(cwd, os.path.expanduser(match.group(1)))
        if os.path.isfile(path) and os.path.getsize(path) < 1_000_000:
            with open(path, encoding="utf-8", errors="replace") as handle:
                text += "\n" + handle.read()
    if EM_DASH not in text:
        return
    reason = (
        "style-gate: this commit, PR or issue text contains an em dash (U+2014). "
        "Rewrite with a period, colon, comma or parentheses (not a spaced hyphen), then rerun."
    )
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": reason}}))


def main():
    data = json.load(sys.stdin)
    event = data.get("hook_event_name")
    tool = data.get("tool_name")
    if event == "PostToolUse" and tool in ("Write", "Edit"):
        post_write(data)
    elif event == "PreToolUse" and tool == "Bash":
        pre_bash(data)


if __name__ == "__main__":
    main()
