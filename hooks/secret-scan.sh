#!/bin/bash
# PostToolUse scan: flag likely secrets in tool output. By now the value is in
# the transcript, so tell the agent not to repeat it and tell the user which
# credential to rotate. Patterns live in secret-patterns.json.

dir=$(cd "$(dirname "$0")" && pwd)
jq -c --slurpfile p "$dir/secret-patterns.json" '
  .tool_name as $tool
  | ((.tool_response // .) | [.. | strings] | join("\n")) as $out
  | [$p[0][] | . as $x | select($out | test($x.re)) | $x.name] | unique
  | select(length > 0)
  | join(", ") as $kinds
  | {hookSpecificOutput: {hookEventName: "PostToolUse",
       additionalContext: "secret-scan: the \($tool) output above appears to contain: \($kinds). Do not repeat, quote, summarize, store or write the value anywhere (files, vault, memory, messages, PRs). Tell the user which credential it is so they can rotate it if it is real, and rerun with ~/.agents/hooks/redact-secrets.sh if you need that output again."},
     systemMessage: "secret-scan: \($tool) output appears to contain \($kinds). Rotate it if it is a real credential."}'
