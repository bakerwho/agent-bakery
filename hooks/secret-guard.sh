#!/bin/bash
# PreToolUse guard for Bash and Read: deny tool calls that would print a secret
# value into the transcript, and name the safe form in the denial reason.
#
# Denies rather than rewrites: a rewrite has to answer "allow", which would skip
# the user's permission prompt. Matches command text without parsing quotes, so
# it errs toward denying. Targets macOS /bin/bash 3.2: regexes live in variables
# and nothing uses bash 4 features. Test with test-hooks.sh after any edit.

input=$(cat)
tool=$(printf '%s' "$input" | jq -r '.tool_name // empty')

deny() {
  jq -n --arg r "secret-guard: $1" \
    '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
  exit 0
}

shopt -s nocasematch

REDACT_HINT='or pipe the output through ~/.agents/hooks/redact-secrets.sh'
CRED_HINT='List key names with cut -d= -f1 <file>, check auth with the tool status command (aws sts get-caller-identity, gh auth status, aws configure list-profiles, kubectl config get-contexts), '"$REDACT_HINT"'.'

# Files whose contents are credentials. .pub keys and .env.example stay readable.
CRED_FILE='(\.aws/credentials|\.netrc|\.pgpass|\.databrickscfg|\.codex/auth\.json|\.docker/config\.json|gh/hosts\.yml|\.kube/config|\.cursor/mcp\.json|\.claude\.json|\.codex/config\.toml|\.mcp\.json|\.npmrc|\.pypirc|\.git-credentials|\.vault-token|id_(rsa|ed25519|ecdsa|dsa)|\.(pem|p12|pfx|key)|(^|[/=])\.env(\.(local|prod|production|dev|development|staging|test))?)$'

if [[ "$tool" == "Read" ]]; then
  path=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty')
  if [[ "$path" =~ $CRED_FILE ]]; then
    deny "Read of a credential file ($path) would put secret values in the transcript. $CRED_HINT"
  fi
  exit 0
fi

[[ "$tool" == "Bash" ]] || exit 0
cmd=$(printf '%s' "$input" | jq -j '.tool_input.command // empty' | tr '\n' ';')
[[ -n "$cmd" ]] || exit 0

# Already redacted: let it through.
re='\|[[:space:]]*[^|;&]*redact-secrets\.sh'
[[ "$cmd" =~ $re ]] && exit 0

# Output reduced to names, labels or counts: let it through.
NAMES_ONLY='\|[[:space:]]*(cut[[:space:]]+-d.?=.?[[:space:]]*-f[[:space:]]*1([^0-9,-]|$)|sed[^|;&]*s/=\.\*//|jq[^;&]*(keys|label)|wc([[:space:]]|$))'
names_only=0
[[ "$cmd" =~ $NAMES_ONLY ]] && names_only=1

# Start of a command that prints to the transcript. A command inside $( ) is a
# capture and does not match, so X=$(gh auth token) stays allowed.
SEG='(^|[;&|][[:space:]]*)(([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*|then|do|else|time|sudo|command|exec|env|npx|bunx|uvx)[[:space:]]+)*'
SECRET_NAME='[A-Za-z0-9_]*(token|secret|password|passwd|api_key|apikey|private_key|credential|access_key)[A-Za-z0-9_]*'

# kubectl
re="${SEG}kubectl[^;&|]*[[:space:]]get[[:space:]]+secrets?([[:space:]/]|\$)[^;&|]*(-o|--output)[[:space:]=]*['\"]?(yaml|json|jsonpath|go-template)"
if [[ "$cmd" =~ $re ]] && (( ! names_only )); then
  deny "kubectl get secret with -o yaml/json/jsonpath prints secret data. Use kubectl describe secret <name> (key names and sizes only), or append | jq '.data | keys'."
fi
re="${SEG}kubectl[^;&|]*config[[:space:]]+view[^;&|]*(--raw|--flatten)"
[[ "$cmd" =~ $re ]] && deny "kubectl config view --raw prints client keys and tokens. Use kubectl config view (redacted) or kubectl config get-contexts."
re="${SEG}kubectl[^;&|]*create[[:space:]]+token"
[[ "$cmd" =~ $re ]] && deny "kubectl create token prints a bearer token. Capture it in a variable: T=\$(kubectl create token <sa>)."

# AWS
re="${SEG}aws[^;&|]*secretsmanager[^;&|]*get-secret-value"
if [[ "$cmd" =~ $re ]] && (( ! names_only )); then
  qre='--query[[:space:]=]+[^;&|]*'
  sre='Secret(String|Binary)'
  if ! [[ "$cmd" =~ $qre ]] || [[ "$cmd" =~ $sre ]]; then
    deny "aws secretsmanager get-secret-value prints the secret. Use describe-secret --secret-id <id>, select non-secret fields with --query (Name, ARN, VersionId), or list JSON keys with --query SecretString --output text | jq 'fromjson | keys'."
  fi
fi
re="${SEG}aws[^;&|]*ssm[^;&|]*get-parameters?(-by-path)?[^;&|]*--with-decryption"
vre='--query[^;&|]*Value'
qre='--query'
if [[ "$cmd" =~ $re ]] && { ! [[ "$cmd" =~ $qre ]] || [[ "$cmd" =~ $vre ]]; }; then
  deny "aws ssm get-parameter --with-decryption prints SecureString values. Drop --with-decryption, or select names with --query 'Parameters[].Name'."
fi
re="${SEG}aws[^;&|]*configure[[:space:]]+(export-credentials|get[[:space:]][^;&|]*(secret|token))"
[[ "$cmd" =~ $re ]] && deny "That aws configure call prints credentials. Use aws sts get-caller-identity to check the identity, or aws configure list (masked)."
re="${SEG}aws[^;&|]*sts[[:space:]]+(get-session-token|assume-role|assume-role-with-[a-z-]+|get-federation-token)"
qre='--query'
if [[ "$cmd" =~ $re ]] && ! [[ "$cmd" =~ $qre ]]; then
  deny "aws sts credential calls print keys and session tokens. Add --query 'AssumedRoleUser.Arn' (or another non-secret field), or capture the JSON in a variable."
fi
re="${SEG}aws[^;&|]*ecr[[:space:]]+get-login-password"
lre='\|[[:space:]]*(docker|podman|helm|oras|crane|skopeo|finch)[[:space:]]'
if [[ "$cmd" =~ $re ]] && ! [[ "$cmd" =~ $lre ]]; then
  deny "aws ecr get-login-password prints a registry password. Pipe it straight into the login: ... | docker login --username AWS --password-stdin <registry>."
fi

# 1Password
re="${SEG}op[[:space:]]+(read|inject)([[:space:]]|\$)"
[[ "$cmd" =~ $re ]] && deny "op read prints the secret. Capture it in a variable (X=\$(op read 'op://...')) and use \"\$X\" without echoing it."
re="${SEG}op[[:space:]]+item[[:space:]]+get[^;&|]*(--reveal|--format[[:space:]=]+json)"
if [[ "$cmd" =~ $re ]] && (( ! names_only )); then
  deny "op item get --reveal / --format json prints field values. Capture into a variable, or list labels only: op item get <item> --format json | jq '[.fields[].label]'."
fi

# Environment dumps and secret-named variables
re="${SEG}(env|printenv|export|set|export[[:space:]]+-p|declare[[:space:]]+-[a-z]*[px][a-z]*|typeset[[:space:]]+-[a-z]*x[a-z]*)[[:space:]]*(\$|[;&|)])"
if [[ "$cmd" =~ $re ]] && (( ! names_only )); then
  deny "Dumping the environment prints every exported token. Show names only: env | cut -d= -f1."
fi
re="${SEG}printenv[[:space:]]+${SECRET_NAME}"
[[ "$cmd" =~ $re ]] && deny "printenv of a secret-named variable prints its value. Check it is set without printing: [ -n \"\$VAR\" ] && echo set, or echo \${#VAR} for its length."
re="${SEG}(echo|printf)[^;&|]*\\\$\\{?${SECRET_NAME}"
[[ "$cmd" =~ $re ]] && deny "Echoing a secret-named variable prints its value. Check it is set without printing: [ -n \"\$VAR\" ] && echo set, or echo \${#VAR} for its length."

# Terraform / OpenTofu / CDK for Terraform
TF='(terraform|tofu)([[:space:]]+-chdir=[^[:space:]]+)?[[:space:]]+'
re="${SEG}${TF}output[^;&|]*(-json|-raw)"
if [[ "$cmd" =~ $re ]] && (( ! names_only )); then
  deny "terraform output -json/-raw prints sensitive outputs. Use terraform output (sensitive values masked), or terraform output -json | jq 'keys'."
fi
re="${SEG}${TF}state[[:space:]]+pull"
[[ "$cmd" =~ $re ]] && deny "terraform state pull prints the whole state, secrets included. Use terraform state list, or terraform state show <address> (masks sensitive attributes)."
re="${SEG}${TF}(plan|apply|show|import|refresh)([[:space:];&|)]|\$)"
[[ "$cmd" =~ $re ]] && deny "terraform/tofu plan, apply and show can print secret values (import IDs, unmarked variables). Run with -no-color 2>&1 and pipe through ~/.agents/hooks/redact-secrets.sh."
re="${SEG}(cdktf|cdktn)[[:space:]]+(plan|diff|deploy|apply)([[:space:];&|)]|\$)"
[[ "$cmd" =~ $re ]] && deny "cdktf/cdktn plan, diff and deploy can print secret values. Run with 2>&1 and pipe through ~/.agents/hooks/redact-secrets.sh."

# Commands whose job is to print a token
re="${SEG}(gh[[:space:]]+auth[[:space:]]+token|gh[[:space:]]+auth[[:space:]]+status[^;&|]*(--show-token|[[:space:]]-t([[:space:]]|\$))|databricks[[:space:]]+auth[[:space:]]+token|databricks[[:space:]]+secrets[[:space:]]+get-secret|gcloud[[:space:]]+auth[[:space:]]+(application-default[[:space:]]+)?print-(access|identity)-token|security[[:space:]]+find-(generic|internet)-password[^;&|]*[[:space:]]-w|git[[:space:]]+credential[[:space:]]+fill|vault[[:space:]]+(read|kv[[:space:]]+get))"
[[ "$cmd" =~ $re ]] && deny "That command prints a token. Capture or substitute it so the value never prints: GH_TOKEN=\$(gh auth token) <cmd>. To check auth, use the tool status command (gh auth status)."

# MCP listings carry Authorization headers
re="${SEG}(claude|codex|cursor-agent)[[:space:]]+mcp[[:space:]]+(list|get)"
[[ "$cmd" =~ $re ]] && deny "mcp list/get output includes server headers and tokens. Pipe it through ~/.agents/hooks/redact-secrets.sh."

# Reading credential files from the shell: for each command that starts with a
# reader, test every word with the same path rule the Read tool gets.
READERS=' cat head tail less more bat strings xxd od base64 grep egrep rg ag awk sed sort jq yq plutil '
PREFIX_WORDS=' sudo env command exec time then do else '
set -f
segments=$(printf '%s' "$cmd" | tr ';|&' '\n\n\n')
IFS=$'\n'
for seg in $segments; do
  IFS=$' \t'
  words=($seg)
  i=0
  while [[ $i -lt ${#words[@]} ]]; do
    w=${words[$i]}
    if [[ "$w" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]] || [[ "$PREFIX_WORDS" == *" $w "* ]]; then i=$((i + 1)); else break; fi
  done
  first=${words[$i]##*/}
  if [[ -n "$first" && "$READERS" == *" $first "* ]]; then
    j=$((i + 1))
    while [[ $j -lt ${#words[@]} ]]; do
      w=${words[$j]}; w=${w//\'/}; w=${w//\"/}; w=${w%)}
      [[ "$w" =~ $CRED_FILE ]] && deny "That reads a credential file ($w) into the transcript. $CRED_HINT"
      j=$((j + 1))
    done
  fi
  IFS=$'\n'
done

exit 0
