#!/bin/sh
# Run the entrypoint property-based test suite.
# Requires: bats (https://github.com/bats-core/bats-core)

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Check that bats is available on PATH
if ! command -v bats > /dev/null 2>&1; then
    echo "ERROR: 'bats' is not installed or not on PATH." >&2
    echo "Install it from https://github.com/bats-core/bats-core or via your package manager:" >&2
    echo "  apt-get install bats        # Debian/Ubuntu" >&2
    echo "  brew install bats-core      # macOS (Homebrew)" >&2
    exit 1
fi

echo "Running entrypoint property tests..."
bats "$SCRIPT_DIR/test_entrypoint_property1.bats"
