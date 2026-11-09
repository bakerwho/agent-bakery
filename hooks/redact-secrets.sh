#!/bin/bash
# Filter: copy stdin to stdout with likely secret values replaced by
# [REDACTED:<kind>]. Reads all input before printing, so multi-line PEM blocks
# are removed whole. Prints nothing if jq fails, so it never leaks on error.
#   terraform plan -no-color 2>&1 | ~/.agents/hooks/redact-secrets.sh

dir=$(cd "$(dirname "$0")" && pwd)
exec jq -Rsj --slurpfile p "$dir/secret-patterns.json" '
  gsub("-----BEGIN ([A-Z]+ )?PRIVATE KEY-----[\\s\\S]*?-----END ([A-Z]+ )?PRIVATE KEY-----"; "[REDACTED:PEM private key]")
  | reduce $p[0][] as $x (.; gsub($x.re; "[REDACTED:" + $x.name + "]"))'
