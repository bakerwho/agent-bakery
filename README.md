# agent-bakery

One folder of open-format agent instructions and skills that every AI coding
tool you use can read (Claude Code, Codex and Cursor to start, and any other
tool you add an adapter for). It also ships a shared notes vault, a rulebook
that every correction you make is written into, a review agent that checks
work against that rulebook, and hooks that stop secrets from leaking into the
transcript.

You edit `AGENTS.md` and `skills/` here. `tools/manage.py install` backs up
each tool's current files, copies yours in where a tool needs a copy, and
checks every copy by hash.

## Where each file lands

You clone this repo to `~/.agents`, so its `skills/` folder is
`~/.agents/skills`. Codex and Cursor already load skills from that folder, so
they need no copy. Claude Code does not, so it gets one.

```
 this repo (~/.agents)                       what each tool reads
 ─────────────────────                       ────────────────────
 skills/*/  (= ~/.agents/skills) ─────────► Codex, Cursor (read it in place)
     │
     ├─ tools/manage.py install ───────────► ~/.claude/skills      (copy)
 AGENTS.md ─┤  (targets in adapters.json) ─► ~/.claude/CLAUDE.md   (copy)
     │      │                           └──► ~/.codex/AGENTS.md    (copy)
 agents/*.md ─────────────────────────────► ~/.claude/agents      (copy)

 Cursor has no global rules file: paste AGENTS.md into Cursor's
 Customize → Rules (User Rules) once, and again when you change it.

 hooks/  wired into ~/.claude/settings.json: block secret leaks, flag style slips

 vault/  copied once to ~/agent-vault (private). AGENTS.md tells every agent to
         read it before a task and write back after. The lesson skill adds
         rules to its reference/agent-rules.md; the preflight agent checks
         work against them.
```

| path | what it is |
|------|------------|
| `AGENTS.md` | Your always-loaded operating rules, in the open [AGENTS.md](https://agents.md) format. Starter content; rewrite it. |
| `skills/<name>/SKILL.md` | Skills in the open [Agent Skills](https://agentskills.io) format: a folder with a `SKILL.md` (YAML `name` and `description`, then instructions) and any scripts or references it needs. |
| `catalog.json` | The skills that get copied and verified. A skill folder not listed here is not copied, but Codex and Cursor still see it because they read `skills/` directly. |
| `adapters.json` | One entry per tool that needs a copy: its skills folder (`skills_path`), its instructions file (`instructions_path`) and that file's format (`markdown`, or `mdc` for a Cursor project rule). Both paths are optional. |
| `agents/` | Subagent definitions. Copied only for adapters with an `agents_path` (Claude Code). |
| `tools/manage.py` | The installer. Python 3.9+, standard library only. |
| `hooks/` | Claude Code hooks: `secret-guard.sh` denies commands that would print a secret, `secret-scan.sh` flags secrets that reached tool output, `redact-secrets.sh` filters them, `style-gate.sh` flags banned phrases and em dashes. |
| `vault/` | Starter place of record: rulebook, roadmap/system/repo templates, folder layout. |

Sources for the tool paths, checked 2026-11-09: Codex loads user skills from
`$HOME/.agents/skills` and global instructions from `~/.codex/AGENTS.md`
([skills](https://developers.openai.com/codex/skills),
[AGENTS.md](https://developers.openai.com/codex/guides/agents-md)). Cursor
loads skills from `~/.agents/skills`, `~/.cursor/skills`, `~/.claude/skills`
and `~/.codex/skills`, and keeps User Rules in its settings, not on disk
([skills](https://cursor.com/docs/skills), [rules](https://cursor.com/docs/rules)).

## Requirements

- macOS or Linux, with `git`, `python3` (3.9 or later; CI tests 3.9 and the
  runner default), `bash` and `jq`.
- At least one of Claude Code, Codex or Cursor. The hooks and subagents work in
  Claude Code only.

## Quick start

### 1. Get your own private copy

On GitHub, click **Use this template**, then **Create a new repository**, and
choose **Private**. Your `AGENTS.md` will hold your own rules, so keep your copy
private unless you mean to share them. (A fork of this repo would be public.)

Then clone it to `~/.agents`. Hook commands and skill text refer to that path,
and Codex and Cursor find skills there.

```bash
[ -e ~/.agents ] && mv ~/.agents ~/.agents.before-agent-bakery.$(date +%Y%m%d%H%M%S)
git clone https://github.com/<you>/<your-repo>.git ~/.agents
cd ~/.agents
```

The first line moves aside an existing `~/.agents` folder so nothing in it is
lost. If it has a `skills/` folder, Codex and Cursor were loading those skills:
copy the ones you want into the new `skills/` and add them to `catalog.json`.

### 2. Run the tests

```bash
bash tools/test-manage.sh
bash hooks/test-hooks.sh
```

`test-manage.sh` installs into a throwaway directory, checks `verify`, makes a
copy drift, and rolls back. It never touches your real tool folders.

### 3. Dry run into a temporary folder

```bash
export AGENT_SETUP_ADAPTER_PREFIX=$(mktemp -d)
export AGENT_SETUP_BACKUPS_ROOT=$(mktemp -d)
python3 tools/manage.py install
find "$AGENT_SETUP_ADAPTER_PREFIX" -type f
unset AGENT_SETUP_ADAPTER_PREFIX AGENT_SETUP_BACKUPS_ROOT
```

The prefix is put in front of every target path, so you can see exactly what a
real install would write.

### 4. Make it yours, then install for real

Edit `AGENTS.md`. Remove adapters for tools you do not use from
`adapters.json`. Then:

```bash
python3 tools/manage.py install
python3 tools/manage.py verify
```

`install` **replaces** each tool's instructions file (for example your existing
`~/.claude/CLAUDE.md`) with a copy of `AGENTS.md`, and replaces any skill folder
with the same name. The old files go to `backups/<timestamp>/` first. Move
anything from your old instructions that you want to keep into `AGENTS.md`
before you install, or copy it back out of the backup afterwards.

For Cursor, open **Customize → Rules**, and paste `AGENTS.md` into User Rules.

To undo an install:

```bash
ls backups/
python3 tools/manage.py rollback <backup-id>
```

### 5. Set up the vault

```bash
cp -R ~/.agents/vault ~/agent-vault
```

Keep `~/agent-vault` out of your repo: it will hold notes on your own work.
Putting it under its own private git repo is a good idea. To use another
location, change the path in `AGENTS.md`, `skills/lesson/SKILL.md` and
`agents/preflight.md` (one line each), then run `install` again.

### 6. Wire the hooks (Claude Code)

Merge `hooks/claude-settings.example.json` into `~/.claude/settings.json`. If
you have no `hooks` key yet, you can copy the whole `hooks` object in. Then
check one fires: ask Claude Code to run `env`, and it should be denied with a
safer command suggested.

Every hook command ends in `|| true`, so a broken hook lets the tool call
through instead of blocking your work.

## Everyday use

**Add a skill.** Create `skills/<name>/SKILL.md`. The folder name and the
`name:` field must match and use only lowercase letters, digits and hyphens.

```markdown
---
name: my-skill
description: What it does and when an agent should use it, in one or two sentences (1024 characters max).
---

# My skill

Steps the agent follows.
```

Add an entry to `catalog.json`, then run `install`. `install` refuses to run if
any listed skill fails validation, and says which.

**Change your rules.** Edit `AGENTS.md`, run `install`, and update Cursor's
User Rules. Never edit the copies in `~/.claude` or `~/.codex`: the next
install overwrites them, and `verify` reports them as drifted.

**Add a tool.** If the tool reads `~/.agents/skills`, it needs only an
instructions entry. Otherwise give it a `skills_path` too. For example, for
Gemini CLI (check the paths against your tool's current docs):

```json
{
  "name": "gemini-cli",
  "skills_path": "~/.gemini/skills",
  "instructions_path": "~/.gemini/GEMINI.md",
  "instructions_format": "markdown"
}
```

A tool that needs a different file format needs a renderer in
`render_instructions` in `tools/manage.py`.

**Record a correction.** When you correct an agent, it should run the `lesson`
skill on its own (AGENTS.md tells it to). The skill adds a rule or a log row to
`~/agent-vault/reference/agent-rules.md`, so every tool you use reads the
lesson.

**Review before you look.** In Claude Code, ask for the `preflight` agent on a
PR or draft. It reads the rulebook and returns `READY`, `FIX_FIRST` or
`NOT_VERIFIED` with a table of findings.

**Share across machines.** Commit and push your copy; on the other machine,
`git pull` and `install`.

## Known limits

- Cursor loads skills from both `~/.agents/skills` and `~/.claude/skills`, so
  with the Claude Code copy in place it finds each skill twice. Cursor's docs
  do not say how it handles two skills with the same name. Not tested here.
- Removing a skill from `catalog.json` does not delete copies already
  installed. Delete them by hand from `~/.claude/skills`.
- Copies take effect only after `install`. The upside: `verify` can prove
  every copy matches the source.
- Hooks and subagents are Claude Code only. Other tools get the instructions
  and skills.

## Compared with GUI skill managers

Desktop apps such as [Skills Manager](https://sm.idoevergreen.me/) show every
skill installed across 12 tools (Claude Code, Cursor, Codex, Copilot, Gemini
CLI, Windsurf and others), install skills from GitHub repos, and copy a skill
from one tool to another in a click. There is nothing to configure before the
first use.

agent-bakery takes a different approach: one git-tracked source of truth,
instructions as well as skills, backups and rollback on every install, hash
checks for drift, and the vault and rulebook so corrections carry across tools.
It has no GUI and no skill browser. The two can coexist, as long as only one of
them writes to a given skills folder.

One collision to know about: Skills Manager's source (`apps/desktop/electron/main.ts`)
treats `~/.agents/skills` as Codex's skills folder. With this repo cloned to
`~/.agents`, that folder is your source of truth, and deleting a "Codex" skill
in the app deletes it here. Commit often.

## License

MIT. See [LICENSE](LICENSE).
