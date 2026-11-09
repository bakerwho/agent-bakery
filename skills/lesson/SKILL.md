---
name: lesson
description: Record a user correction as a rule in the shared rulebook and fix the same mistake elsewhere in this session's work. Run it unasked, right after the user corrects an approach, contradicts a claim, reshapes a draft, restates a preference, or asks whether something was actually verified.
---

# Lesson

Vault: ~/agent-vault (the one line to change if your vault lives elsewhere)
Rulebook: <vault>/reference/agent-rules.md

Run this after any correction, without being asked. Keep it short: it should take a few tool calls, not a detour.

1. One line: what you did, what the user wanted, and why your default got it wrong.
2. Place it.
   - Matches an existing rule: note its ID.
   - New and general: add it to the rulebook in its section with the next free ID, in the rulebook's format (bold imperative, a *Why* line naming this dated case, a *Check* line naming the command or test that would have caught it).
   - Specific to one repo, system or workstream: add it to that note in the vault (repos/, systems/ or the workstream roadmap) instead.
3. Log it: add a row to the corrections log at the bottom of the rulebook (date, where, what happened, rule ID or new:<ID>). Bump `updated:` in the rulebook frontmatter.
4. Sweep: fix the same mistake in this session's other PRs, drafts and replies. List hits in the workstream's other open work for the user; do not edit work that is not this session's.
5. Repeats: a rule with two or more log rows has a weak check. Propose a sharper check, or promotion to ~/.agents/AGENTS.md. Do not edit AGENTS.md without a yes; after a yes, run `python3 ~/.agents/tools/manage.py install` so every tool gets it.
6. Report in three lines or fewer: rule ID, sweep result, any proposal.

Never put secrets, credentials, customer names or data, or quoted private messages in the vault. Paraphrase.
Never record a correction only in one tool's memory (Claude per-project memory, Cursor or Codex memories): it does not reach the other tools or repos.
Never add a near-duplicate rule. Sharpen the existing rule's check instead.
A one-time permission ("force-push this branch", "post it") is not a standing rule. Record it only if the user says it should apply from now on.
If the vault is not writable, print the rule text and the log row for the user to paste.
