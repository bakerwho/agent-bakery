#!/bin/bash
# Feed sample tool-call JSON through every hook and check the decisions.
#   ~/.agents/hooks/test-hooks.sh            # bash from PATH
#   /bin/bash ~/.agents/hooks/test-hooks.sh  # macOS bash 3.2
# Fake secrets are built by concatenation so this file never matches a pattern.

dir=$(cd "$(dirname "$0")" && pwd)
pass=0
fail=0

check() {  # check <name> <expect: deny|allow|flag|clean|redacted> <actual>
  if [[ "$2" == "$3" ]]; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "FAIL: $1 (expected $2, got $3)"; fi
}

guard() {  # guard <tool> <field> <value>
  local json out
  json=$(jq -n --arg t "$1" --arg f "$2" --arg v "$3" '{hook_event_name: "PreToolUse", tool_name: $t, tool_input: {($f): $v}}')
  out=$(printf '%s' "$json" | "$dir/secret-guard.sh")
  if printf '%s' "$out" | grep -q '"permissionDecision": *"deny"'; then echo deny; else echo allow; fi
}

bash_deny()  { check "guard denies: $1" deny "$(guard Bash command "$1")"; }
bash_allow() { check "guard allows: $1" allow "$(guard Bash command "$1")"; }

# --- secret-guard: Bash commands that print secrets
bash_deny  'kubectl get secret x -o yaml'
bash_deny  'kubectl -n ml get secrets db-creds -o jsonpath={.data.password}'
bash_deny  'KUBECONFIG=~/k kubectl get secret/x --output=json'
bash_deny  'kubectl config view --raw'
bash_deny  'aws secretsmanager get-secret-value --secret-id x'
bash_deny  'aws secretsmanager get-secret-value --secret-id x --query SecretString --output text'
bash_deny  'aws ssm get-parameter --name /x --with-decryption'
bash_deny  'aws configure get aws_secret_access_key --profile p'
bash_deny  'aws configure export-credentials --profile p'
bash_deny  'aws sts assume-role --role-arn arn:aws:iam::1:role/r --role-session-name s'
bash_deny  'aws ecr get-login-password --region us-west-2'
bash_deny  "op read 'op://vault/item/password'"
bash_deny  'op item get x --reveal'
bash_deny  'env'
bash_deny  'env | grep AWS'
bash_deny  'cd /tmp && printenv'
bash_deny  'export -p'
bash_deny  'printenv GITHUB_TOKEN'
bash_deny  'echo $LABELBOX_API_KEY'
bash_deny  'echo "${DATABRICKS_TOKEN}"'
bash_deny  'terraform output -json'
bash_deny  'terraform -chdir=infra output -raw db_password'
bash_deny  'tofu state pull'
bash_deny  'cd terraform && terraform plan -no-color'
bash_deny  'npx cdktf diff'
bash_deny  'cdktn deploy stack'
bash_deny  'gh auth token'
bash_deny  'gh auth status --show-token'
bash_deny  'databricks auth token --host x'
bash_deny  'security find-generic-password -s x -w'
bash_deny  'claude mcp list'
bash_deny  'codex mcp get glean'
bash_deny  'cat ~/.aws/credentials'
bash_deny  'head -20 ~/.codex/config.toml'
bash_deny  'jq .mcpServers ~/.claude.json'
bash_deny  'cat .env'
bash_deny  'grep TOKEN ./app/.env.local'
bash_deny  'cat ~/.ssh/id_ed25519'
bash_deny  $'ls\ngh auth token'

# --- secret-guard: safe forms named in the denials
bash_allow 'kubectl describe secret x'
bash_allow 'kubectl get secrets -A'
bash_allow "kubectl get secret x -o json | jq '.data | keys'"
bash_allow 'kubectl config view'
bash_allow 'aws secretsmanager describe-secret --secret-id x'
bash_allow "aws secretsmanager get-secret-value --secret-id x --query 'Name'"
bash_allow "aws secretsmanager get-secret-value --secret-id x --query SecretString --output text | jq 'fromjson | keys'"
bash_allow "aws ssm get-parameters-by-path --path /x --with-decryption --query 'Parameters[].Name'"
bash_allow 'aws sts get-caller-identity'
bash_allow "aws sts assume-role --role-arn r --role-session-name s --query 'AssumedRoleUser.Arn'"
bash_allow 'aws ecr get-login-password | docker login --username AWS --password-stdin 1.dkr.ecr.us-west-2.amazonaws.com'
bash_allow "TOKEN=\$(op read 'op://vault/item/password') && use-it"
bash_allow 'env | cut -d= -f1'
bash_allow 'env FOO=bar python3 x.py'
bash_allow 'set -euo pipefail; make test'
bash_allow 'printenv AWS_PROFILE'
bash_allow 'echo ${#GITHUB_TOKEN}'
bash_allow '[ -n "$GITHUB_TOKEN" ] && echo set'
bash_allow 'terraform output'
bash_allow 'terraform state list'
bash_allow 'terraform plan -no-color 2>&1 | ~/.agents/hooks/redact-secrets.sh'
bash_allow 'npx cdktf diff 2>&1 | ~/.agents/hooks/redact-secrets.sh'
bash_allow 'GH_TOKEN=$(gh auth token) gh api user'
bash_allow 'gh auth status'
bash_allow 'claude mcp list | ~/.agents/hooks/redact-secrets.sh'
bash_allow 'cut -d= -f1 .env'
bash_allow 'cat .env.example'
bash_allow 'cat ~/.ssh/id_ed25519.pub'
bash_allow 'aws configure list-profiles'
bash_allow 'grep -rn "gh auth token" docs/'
bash_allow 'git status && git diff --stat'

# --- secret-guard: Read tool
check 'guard denies Read ~/.aws/credentials' deny "$(guard Read file_path "$HOME/.aws/credentials")"
check 'guard denies Read repo .env' deny "$(guard Read file_path /repo/app/.env)"
check 'guard denies Read ~/.codex/auth.json' deny "$(guard Read file_path "$HOME/.codex/auth.json")"
check 'guard allows Read .env.example' allow "$(guard Read file_path /repo/.env.example)"
check 'guard allows Read source file' allow "$(guard Read file_path /repo/src/main.py)"

# --- secret-scan
AKID="AKIA""IOSFODNN7EXAMPLE"
GHTOK="ghp_""aBcDeFgHiJkLmNoPqRsTuVwXyZ0123456789"
SKKEY="sk-""proj-abcdefghijklmnopqrstuvwx"
PEM="-----BEGIN ""RSA PRIVATE KEY-----"
BEARER="Authorization: Bearer ""abcdefghijklmnopqrstuvwxyz012345"
DAPI="dapi""0123456789abcdef0123456789abcdef"

scan() {  # scan <tool> <output text>
  local json out
  json=$(jq -n --arg t "$1" --arg o "$2" '{hook_event_name: "PostToolUse", tool_name: $t, tool_input: {command: "x"}, tool_response: {stdout: $o, stderr: ""}}')
  out=$(printf '%s' "$json" | "$dir/secret-scan.sh")
  if printf '%s' "$out" | grep -q 'secret-scan'; then echo flag; else echo clean; fi
}
check 'scan flags AWS key id'        flag  "$(scan Bash "id=$AKID")"
check 'scan flags GitHub token'      flag  "$(scan Bash "token: $GHTOK")"
check 'scan flags sk- key'           flag  "$(scan Read "OPENAI=$SKKEY")"
check 'scan flags PEM key'           flag  "$(scan Grep "$PEM")"
check 'scan flags bearer header'     flag  "$(scan mcp__x__y "$BEARER")"
check 'scan flags Databricks token'  flag  "$(scan Bash "$DAPI")"
check 'scan ignores plain output'    clean "$(scan Bash 'total 24 drwxr-xr-x README.md')"
check 'scan ignores a sha'           clean "$(scan Bash 'commit 63d5e11d65f0a1b2c3d4e5f6a7b8c9d0e1f2a3b4')"
out=$(jq -n --arg o "x $AKID" '{tool_name: "Bash", tool_response: {stdout: $o}}' | "$dir/secret-scan.sh")
if printf '%s' "$out" | grep -q 'IOSFODNN7'; then check 'scan never echoes the value' clean leaked; else check 'scan never echoes the value' clean clean; fi

# --- redact-secrets
red=$(printf 'a %s b\n%s\nMIIEow\n-----END RSA PRIVATE KEY-----\nok\n' "$AKID" "$PEM" | "$dir/redact-secrets.sh")
if printf '%s' "$red" | grep -q 'IOSFODNN7\|MIIEow'; then check 'redact removes key id and PEM body' redacted leaked; else check 'redact removes key id and PEM body' redacted redacted; fi
check 'redact keeps clean lines' ok "$(printf '%s' "$red" | tail -1)"

# --- style-gate
style() {  # style <event> <tool> <json tool_input>
  jq -n --arg e "$1" --arg t "$2" --argjson i "$3" '{hook_event_name: $e, tool_name: $t, cwd: "/tmp", tool_input: $i}' | "$dir/style-gate.sh"
}
EM=$(printf '\342\200\224')
out=$(style PostToolUse Write "$(jq -n --arg c "Fast ${EM} and robust." '{file_path: "/repo/README.md", content: $c}')")
check 'style-gate flags em dash and banned word in .md' flag "$(printf '%s' "$out" | grep -q 'em dash.*robust' && echo flag || echo clean)"
out=$(style PostToolUse Write "$(jq -n --arg c "x ${EM} y" '{file_path: "/repo/main.py", content: $c}')")
check 'style-gate ignores code files' clean "$( [[ -z "$out" ]] && echo clean || echo flag)"
out=$(style PostToolUse Write "$(jq -n --arg c "robust" '{file_path: "/h/.agents/AGENTS.md", content: $c}')")
check 'style-gate exempts AGENTS.md' clean "$( [[ -z "$out" ]] && echo clean || echo flag)"
out=$(style PreToolUse Bash "$(jq -n --arg c "git commit -m 'fix ${EM} oops'" '{command: $c}')")
check 'style-gate denies em dash in commit message' deny "$(printf '%s' "$out" | grep -q '"deny"' && echo deny || echo allow)"
out=$(style PreToolUse Bash '{"command": "git commit -m \"fix: plain message\""}')
check 'style-gate allows a plain commit' allow "$( [[ -z "$out" ]] && echo allow || echo deny)"

echo "secret and style hooks: $pass passed, $fail failed (bash ${BASH_VERSION})"
[[ $fail -eq 0 ]]
