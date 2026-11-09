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

out=$(manage install)
check "install reports installed" installed "$(printf '%s' "$out" | python3 -c 'import json,sys; print(json.load(sys.stdin)["status"])')"
backup_id=$(printf '%s' "$out" | python3 -c 'import json,sys; print(json.load(sys.stdin)["backup_id"])')

manage verify > /dev/null && rc=0 || rc=$?
check "verify passes after install" 0 "$rc"
check "CLAUDE.md now matches AGENTS.md" same "$(cmp -s "$root/AGENTS.md" "$claude_md" && echo same || echo different)"

echo "drift" >> "$AGENT_SETUP_ADAPTER_PREFIX$HOME/.codex/skills/lesson/SKILL.md"
manage verify > /dev/null && rc=0 || rc=$?
check "verify fails after an installed copy drifts" 1 "$rc"

manage rollback "$backup_id" > /dev/null
check "rollback restores the old CLAUDE.md" "my old instructions" "$(cat "$claude_md")"
check "rollback removes skills that did not exist before" absent "$([[ -e "$AGENT_SETUP_ADAPTER_PREFIX$HOME/.codex/skills/lesson" ]] && echo present || echo absent)"

echo "manage.py: $pass passed, $fail failed"
[[ $fail -eq 0 ]]
