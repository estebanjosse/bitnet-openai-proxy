#!/usr/bin/env bats
# Property 1: Server flags are forwarded for any env var combination
# Validates: Requirements 2.7
#
# This test verifies that for any combination of SERVER_HOST, SERVER_PORT,
# CTX_SIZE, N_PARALLEL, and LOG_LEVEL values, the entrypoint script correctly
# forwards each value to llama-server via the corresponding CLI flag.
#
# The LOG_LEVEL → --verbosity mapping tested here is:
#   error → 0, warn → 1, info → 2, debug → 3

# ---------------------------------------------------------------------------
# Bats hooks
# ---------------------------------------------------------------------------

setup() {
    # Create a temporary directory for the mock binary and fake model file
    TMPDIR="$(mktemp -d)"

    # Create a fake model file so MODEL_PATH validation passes
    FAKE_MODEL="$TMPDIR/model.gguf"
    touch "$FAKE_MODEL"

    # Create a mock llama-server that captures its arguments to a file
    MOCK_ARGS_FILE="$TMPDIR/llama_server_args.txt"
    cat > "$TMPDIR/llama-server" <<'EOF'
#!/bin/sh
# Mock llama-server: write all received arguments to a capture file, then exit 0
printf '%s\n' "$@" > "$MOCK_ARGS_FILE"
EOF
    # Substitute the capture file path into the mock script
    sed -i "s|MOCK_ARGS_FILE|$MOCK_ARGS_FILE|g" "$TMPDIR/llama-server"
    chmod +x "$TMPDIR/llama-server"

    # Prepend the temp dir to PATH so the mock is found instead of the real binary
    export PATH="$TMPDIR:$PATH"
}

teardown() {
    # Remove all temporary files created during the test
    rm -rf "$TMPDIR"
}

# ---------------------------------------------------------------------------
# Helper: map LOG_LEVEL name to expected --verbosity integer
# ---------------------------------------------------------------------------
expected_verbosity() {
    case "$1" in
        error) echo 0 ;;
        warn)  echo 1 ;;
        info)  echo 2 ;;
        debug) echo 3 ;;
        *)     echo 2 ;;
    esac
}

# ---------------------------------------------------------------------------
# Helper: run one iteration with the given env vars and assert all flags
# ---------------------------------------------------------------------------
run_iteration() {
    local host="$1"
    local port="$2"
    local ctx="$3"
    local parallel="$4"
    local log_level="$5"
    local verbosity
    verbosity="$(expected_verbosity "$log_level")"

    local args_file="$TMPDIR/llama_server_args.txt"

    # Invoke the entrypoint script with the generated env vars
    SERVER_HOST="$host" \
    SERVER_PORT="$port" \
    CTX_SIZE="$ctx" \
    N_PARALLEL="$parallel" \
    LOG_LEVEL="$log_level" \
    MODEL_PATH="$FAKE_MODEL" \
    sh "$(dirname "$BATS_TEST_FILENAME")/../entrypoint.sh"

    # Assert --host flag is present with the correct value
    grep -qxF -- "--host" "$args_file" \
        || { echo "FAIL: --host flag missing (host=$host)"; return 1; }
    grep -qxF -- "$host" "$args_file" \
        || { echo "FAIL: --host value '$host' missing"; return 1; }

    # Assert --port flag is present with the correct value
    grep -qxF -- "--port" "$args_file" \
        || { echo "FAIL: --port flag missing (port=$port)"; return 1; }
    grep -qxF -- "$port" "$args_file" \
        || { echo "FAIL: --port value '$port' missing"; return 1; }

    # Assert --ctx-size flag is present with the correct value
    grep -qxF -- "--ctx-size" "$args_file" \
        || { echo "FAIL: --ctx-size flag missing (ctx=$ctx)"; return 1; }
    grep -qxF -- "$ctx" "$args_file" \
        || { echo "FAIL: --ctx-size value '$ctx' missing"; return 1; }

    # Assert --parallel flag is present with the correct value
    grep -qxF -- "--parallel" "$args_file" \
        || { echo "FAIL: --parallel flag missing (parallel=$parallel)"; return 1; }
    grep -qxF -- "$parallel" "$args_file" \
        || { echo "FAIL: --parallel value '$parallel' missing"; return 1; }

    # Assert --verbosity flag is present with the correct numeric value
    grep -qxF -- "--verbosity" "$args_file" \
        || { echo "FAIL: --verbosity flag missing (log_level=$log_level)"; return 1; }
    grep -qxF -- "$verbosity" "$args_file" \
        || { echo "FAIL: --verbosity value '$verbosity' missing for log_level='$log_level'"; return 1; }
}

# ---------------------------------------------------------------------------
# Property test
# ---------------------------------------------------------------------------

@test "Property 1: server flags are forwarded for any env var combination" {
    # Run at least 2 iterations with randomly generated values to verify the
    # property holds across different input combinations.
    local log_levels="error warn info debug"
    local iterations=2

    for i in $(seq 1 $iterations); do
        # Generate a random IPv4 address in the 10.x.x.x range
        local host="10.$((RANDOM % 256)).$((RANDOM % 256)).$((RANDOM % 256))"

        # Generate a random port in the range 1024–65535
        local port="$((1024 + RANDOM % 64512))"

        # Generate a random context size in the range 128–8192
        local ctx="$((128 + RANDOM % 8065))"

        # Generate a random parallel slot count in the range 1–16
        local parallel="$((1 + RANDOM % 16))"

        # Pick a random LOG_LEVEL from the allowed enum values
        local level_index="$((RANDOM % 4))"
        local log_level
        log_level="$(echo $log_levels | tr ' ' '\n' | sed -n "$((level_index + 1))p")"

        # Run the iteration and assert all flags are forwarded correctly
        run_iteration "$host" "$port" "$ctx" "$parallel" "$log_level"
    done
}
