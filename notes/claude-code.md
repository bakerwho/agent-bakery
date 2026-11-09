## Claude Code notes

These lines come from `notes/claude-code.md` and reach Claude Code only. Put
instructions here that only make sense in one tool, or that this tool needs
phrased differently. Keep shared rules in `AGENTS.md`.

- The secret and style hooks in `~/.agents/hooks/` run here. If one denies a
  command, use the safer form it names.
- Run the `preflight` subagent before marking a PR ready or asking the user to
  decide.
