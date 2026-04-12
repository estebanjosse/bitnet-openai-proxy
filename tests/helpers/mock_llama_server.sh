#!/bin/sh
# Mock llama-server helper for property-based tests.
# When sourced or executed, this script writes all received arguments (one per
# line) to the file path stored in MOCK_ARGS_FILE, then exits 0.
#
# Usage:
#   1. Set MOCK_ARGS_FILE to the path where arguments should be captured.
#   2. Install this script as "llama-server" on PATH before invoking entrypoint.sh.
#
# Example (from a bats setup() hook):
#   export MOCK_ARGS_FILE="$TMPDIR/args.txt"
#   cp tests/helpers/mock_llama_server.sh "$TMPDIR/llama-server"
#   sed -i "s|MOCK_ARGS_FILE_PLACEHOLDER|$MOCK_ARGS_FILE|g" "$TMPDIR/llama-server"
#   chmod +x "$TMPDIR/llama-server"
#   export PATH="$TMPDIR:$PATH"

printf '%s\n' "$@" > MOCK_ARGS_FILE_PLACEHOLDER
