#!/bin/bash
# Wrapper so settings.json can call every hook the same way. -I keeps a repo's
# own json.py or re.py in the working directory from shadowing the stdlib.
exec python3 -I "$(cd "$(dirname "$0")" && pwd)/style_gate.py"
