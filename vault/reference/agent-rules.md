---
status: maintained
owner: <you>
created: YYYY-MM-DD
updated: YYYY-MM-DD
---
# Agent rules

Every rule records a mistake an agent made and was corrected on. Each has a
bold imperative with a stable ID, a *Why* line naming dated cases, and a
*Check* line naming what would have caught it. The preflight agent cites these
IDs, so IDs never change: retire a rule by striking it through, not by
renumbering.

The `lesson` skill adds rules and log rows. You can also seed the file by hand,
or by asking an agent to read your recent sessions and group the times you
corrected it.

Sections: V verification, E evidence, A autonomy and asks, W writing for
others, X secrets, P pull requests. Add sections as you need them.

The rules below are examples of the format. Replace the *Why* lines with your
own dated cases, or delete the rules.

## V. Verification

- **V1. Report done only with the evidence the user would check.** For a job:
  run link, terminal state, and before/after counts for every target. For a
  doc or post: open it and confirm the content shows. A run marked success
  proves nothing until its output is read.
  *Why:* (example) a job reported done had written zero rows (YYYY-MM-DD).
  *Check:* the report has a run link, terminal state and before/after counts,
  or says NOT VERIFIED.

## E. Evidence and claims

- **E1. Ground every number.** State the denominator, time range and source
  next to it.
  *Why:* (example) a percentage with no total or date range (YYYY-MM-DD).
  *Check:* every figure has total, range and source beside it.

- **E2. Read the code, data or docs before asserting.** When the source is
  silent, ask; never fill an unknown with a guess.
  *Why:* (example) a column's meaning asserted without reading the table
  (YYYY-MM-DD).
  *Check:* each behavioral claim cites file:line, a query result or a doc link.

## A. Autonomy and asks

- **A1. Run the next step yourself when you have the tool.** Do not hand over
  copy-paste steps or end with "want me to?" for work inside the task.
  *Why:* (example) red CI reported instead of fixed (YYYY-MM-DD).
  *Check:* every ask in the reply is a decision or an authority only the user
  holds.

## W. Writing for others

## X. Secrets

- **X1. Never print a secret value into the transcript.** Capture it in a
  variable, list key names, or pipe output through
  `~/.agents/hooks/redact-secrets.sh`.
  *Check:* `hooks/secret-guard.sh` denies the common forms; `hooks/test-hooks.sh`
  passes.

## P. Pull requests

- **P1. A PR is ready only when rebased, CI green on the latest head, review
  comments addressed, and tested.**
  *Check:* `gh pr checks <n>` and `gh pr view <n> --json mergeStateStatus`.

## Corrections log

One row per correction. A second row on the same rule means its check failed
to stop the mistake: sharpen the check, or promote the rule into
`~/.agents/AGENTS.md`.

| date | where | what happened | rule |
|------|-------|---------------|------|
