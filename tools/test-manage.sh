#!/bin/bash
# End-to-end test of manage.py against a throwaway home directory. Never touches
# your real ~/.claude, ~/.codex or ~/.cursor.
#   tools/test-manage.sh
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export AGENT_SETUP_ADAPTER_PREFIX="$tmp/home"
export AGENT_SETUP_BACKUPS_ROOT="$tmp/backups"
manage() { python3 "$root/tools/manage.py" "$@"; }
pass=0
fail=0
check() {  # check <name> <expected> <actual>
  if [[ "$2" == "$3" ]]; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "FAIL: $1 (expected $2, got $3)"; fi
}

# A file the install will replace, so rollback has something to restore.
claude_md="$AGENT_SETUP_ADAPTER_PREFIX$HOME/.claude/CLAUDE.md"
mkdir -p "$(dirname "$claude_md")"
echo "my old instructions" > "$claude_md"

out=$(manage plan)
check "plan before install lists new targets" yes "$(printf '%s' "$out" | grep -q '^new' && echo yes || echo no)"
check "plan writes nothing" absent "$([[ -e "$AGENT_SETUP_ADAPTER_PREFIX$HOME/.codex" ]] && echo present || echo absent)"

out=$(manage install)
check "install reports installed" installed "$(printf '%s' "$out" | python3 -c 'import json,sys; print(json.load(sys.stdin)["status"])')"
backup_id=$(printf '%s' "$out" | python3 -c 'import json,sys; print(json.load(sys.stdin)["backup_id"])')

manage verify > /dev/null && rc=0 || rc=$?
check "verify passes after install" 0 "$rc"
check "Codex gets instructions but no skill copy" "yes no" "$([[ -f "$AGENT_SETUP_ADAPTER_PREFIX$HOME/.codex/AGENTS.md" ]] && echo yes || echo no) $([[ -e "$AGENT_SETUP_ADAPTER_PREFIX$HOME/.codex/skills" ]] && echo yes || echo no)"
import_line=$(grep '^@' "$claude_md" | head -1)
import_path=${import_line#@}; import_path=${import_path//\\ / }; import_path=${import_path/#\~/$HOME}
check "CLAUDE.md imports this repo's AGENTS.md" "$root/AGENTS.md" "$import_path"
check "CLAUDE.md carries the claude-code notes" yes "$(grep -qF "$(head -1 "$root/notes/claude-code.md")" "$claude_md" && echo yes || echo no)"
check "Codex AGENTS.md is a full copy" same "$(cmp -s "$root/AGENTS.md" "$AGENT_SETUP_ADAPTER_PREFIX$HOME/.codex/AGENTS.md" && echo same || echo different)"
check "plan after install changes nothing" yes "$(manage plan | grep -q '^0 of ' && echo yes || echo no)"

echo "drift" >> "$AGENT_SETUP_ADAPTER_PREFIX$HOME/.claude/skills/lesson/SKILL.md"
manage verify > /dev/null && rc=0 || rc=$?
check "verify fails after an installed copy drifts" 1 "$rc"

manage rollback "$backup_id" > /dev/null
check "rollback restores the old CLAUDE.md" "my old instructions" "$(cat "$claude_md")"
check "rollback removes skills that did not exist before" absent "$([[ -e "$AGENT_SETUP_ADAPTER_PREFIX$HOME/.claude/skills/lesson" ]] && echo present || echo absent)"

# A failed install must never delete a file it could not back up.
echo "precious" > "$claude_md"
chmod 000 "$claude_md"
err=$(manage install 2>&1 >/dev/null) && rc=0 || rc=$?
chmod 600 "$claude_md" 2>/dev/null || true
check "the failure is the unreadable file" yes "$(printf '%s' "$err" | grep -q PermissionError && echo yes || echo no)"
check "install fails when it cannot back up a file" nonzero "$([[ $rc -ne 0 ]] && echo nonzero || echo zero)"
check "that file survives the failed install" precious "$(cat "$claude_md" 2>/dev/null || echo missing)"

# Import paths: ~-relative under $HOME, absolute elsewhere, spaces escaped.
ref() { python3 -c 'import sys; from pathlib import Path; sys.path.insert(0, sys.argv[1]); import manage; print(manage.import_reference(Path(sys.argv[2])))' "$root/tools" "$1"; }
check "import path under home with a space" '~/a\ b/AGENTS.md' "$(ref "$HOME/a b/AGENTS.md")"
check "import path outside home with a space" '/opt/a\ b/AGENTS.md' "$(ref "/opt/a b/AGENTS.md")"

echo "manage.py: $pass passed, $fail failed"
[[ $fail -eq 0 ]]
