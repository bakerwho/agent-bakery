# Vault conventions

This folder is the place of record that every agent tool shares. Copy it out of
the repo to a private location (the default is `~/agent-vault`) before you
write real notes in it: it will hold details of your own work. Agents read it
at the start of any task bigger than a question and write back on each
decision, milestone or PR. `AGENTS.md` points them here.

It is plain Markdown, so any editor works. Obsidian is a good fit because the
notes link with `[[wikilinks]]`, but nothing depends on it.

| folder | holds |
|--------|-------|
| `reference/agent-rules.md` | the rulebook and corrections log |
| `workstreams/<name>/` | `roadmap.md`, plus `plans/YYYY-MM-DD-<topic>.md`, `evidence/`, `diagrams/` |
| `systems/<name>.md` | one per platform you work on: architecture, operations, known problems, gotchas |
| `repos/<repo>.md` | one per repo: layout, build/test/deploy, gotchas, `read_at: <sha>` |
| `templates/` | `roadmap.md`, `system.md`, `repo.md` |
| `inbox/` | plans and notes not yet in a workstream |
| `archive/` | finished or abandoned workstreams |

Roadmap `status` is one of `active`, `maintained`, `done`, `paused`. Every
roadmap lists its repos in `repos:` so an agent can find the workstream for the
repo it is in:

```bash
grep -rl --include=roadmap.md "<repo>" ~/agent-vault/workstreams
```

Never store secrets, credentials, customer names or customer data, or quoted
private messages. Paraphrase and link instead.
