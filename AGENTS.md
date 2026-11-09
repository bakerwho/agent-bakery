# Agent operating rules

These instructions use the open AGENTS.md format. `tools/manage.py install`
copies this file to every tool listed in `adapters.json` (`~/.claude/CLAUDE.md`
and `~/.codex/AGENTS.md` to start; Cursor's User Rules are pasted by hand), so
edit it here and nowhere else. Replace the examples with your own rules.

## Place of record

`~/agent-vault` is the place of record shared by every tool. For any task
bigger than a quick question:

1. Find the workstream:
   `grep -rl --include=roadmap.md "<repo>" ~/agent-vault/workstreams`
2. Read its roadmap, the `systems/` notes it lists, `repos/<repo>.md`, and
   `reference/agent-rules.md`.
3. No match and the work spans sessions: create `workstreams/<name>/` from
   `templates/roadmap.md`.

On a decision, milestone or PR, update that roadmap, add a dated Log line, and
bump `updated:`. Never put secrets, credentials or customer data in the vault.

## Rules from past corrections

The full rulebook, with each rule's case and check, is
`~/agent-vault/reference/agent-rules.md`. After the user corrects you, run the
`lesson` skill unasked so the correction becomes a rule every tool can read.

Promote a rule here only after it has been broken twice. Starter set:

- V1. Report done only with the evidence the user would check: run link,
  terminal state, before and after counts.
- E1. Every number carries its denominator, time range and source.
- E2. Read the code, data or docs before asserting. Ask when the source is
  silent.
- A1. Run the next step yourself when you have the tool. Ask only for
  decisions and authority you lack.

Before marking a PR ready or asking the user to decide, run the `preflight`
agent (Claude Code), or follow `~/.agents/agents/preflight.md` in a fresh
context in other tools, and fix what it reports.

## Starting a task

Before changing code, give a short map of the system involved: the pieces, how
they connect, and where the change lands. Use names that already exist in the
code and docs. Say what you verified and what you inferred.

## Answering questions

End a reply that answers questions with a short `## Answers` section: one line
per question, in the order asked, phrased as the answer itself.

## Writing

- Lead with the result, decision or constraint.
- No em dashes (U+2014) and no spaced hyphens used as dashes. Use a period,
  colon, comma or parentheses.
- Skip filler openers, canned praise and recap closers.
- Prefer a concrete mechanism or measurement over adjectives.
- Keep real uncertainty visible: say what is verified, inferred or unverified.

## Evidence and authority

- Prefer primary sources: exact file paths and lines, commands and their
  output, direct links.
- Keep read-only investigation separate from changes. Discussion is not
  approval for external or destructive actions.
- Make the smallest change that satisfies the request and leave unrelated work
  alone.
