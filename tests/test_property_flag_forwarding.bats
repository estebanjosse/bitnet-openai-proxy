#!/usr/bin/env bats
# Property 1: Server flags are forwarded for any env var combination
# Validates: Requirements 2.7
#
# For any combination of SERVER_HOST, SERVER_PORT, CTX_SIZE, N_PARALLEL, and
# LOG_LEVEL values, the entrypoint script SHALL forward each value to
# llama-server via the corresponding CLI flag.
#
# LOG_LEVEL → --verbosity mapping:
#   error → 0, warn → 1, info → 2, debug → 3

# ---------------------------------------------------------------------------
# Bats hooks
# ---------------------------------------------------------------------------

setup() {
    # Temporary workspace for the mock binary and fake model file
    TEST_TMPDIR="$(mktemp -d)"

    # Fake model file so MODEL_PATH validation passes
    FAKE_MODEL="$TEST_TMPDIR/model.gguf"
    touch "$FAKE_MODEL"

    # File where the mock llama-server will capture its arguments
    MOCK_ARGS_FILE="$TEST_TMPDIR/args.txt"

    # Install the mock llama-server from the shared helper
    MOCK_SCRIPT="$TEST_TMPDIR/llama-server"
    cp "$(dirname "$BATS_TEST_FILENAME")/helpers/mock_llama_server.sh" "$MOCK_SCRIPT"
    sed -i "s|MOCK_ARGS_FILE_PLACEHOLDER|$MOCK_ARGS_FILE|g" "$MOCK_SCRIPT"
    chmod +x "$MOCK_SCRIPT"

    # Prepend temp dir so the mock is found before any real llama-server
    export PATH="$TEST_TMPDIR:$PATH"

    export TEST_TMPDIR FAKE_MODEL MOCK_ARGS_FILE
}

teardown() {
    rm -rf "$TEST_TMPDIR"
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
# Helper: run one iteration and assert all flags are forwarded correctly
# ---------------------------------------------------------------------------
assert_flags_forwarded() {
    local host="$1"
    local port="$2"
    local ctx="$3"
    local parallel="$4"
    local log_level="$5"
    local verbosity
    verbosity="$(expected_verbosity "$log_level")"

    # Invoke the entrypoint with the generated env vars
    SERVER_HOST="$host" \
    SERVER_PORT="$port" \
    CTX_SIZE="$ctx" \
    N_PARALLEL="$parallel" \
    LOG_LEVEL="$log_level" \
    MODEL_PATH="$FAKE_MODEL" \
    sh "$(dirname "$BATS_TEST_FILENAME")/../entrypoint.sh"

    # Assert --host flag and value
    grep -qxF -- "--host"    "$MOCK_ARGS_FILE" || { echo "FAIL: --host flag missing (host=$host)"; return 1; }
    grep -qxF -- "$host"     "$MOCK_ARGS_FILE" || { echo "FAIL: --host value '$host' missing"; return 1; }

    # Assert --port flag and value
    grep -qxF -- "--port"    "$MOCK_ARGS_FILE" || { echo "FAIL: --port flag missing (port=$port)"; return 1; }
    grep -qxF -- "$port"     "$MOCK_ARGS_FILE" || { echo "FAIL: --port value '$port' missing"; return 1; }

    # Assert --ctx-size flag and value
    grep -qxF -- "--ctx-size" "$MOCK_ARGS_FILE" || { echo "FAIL: --ctx-size flag missing (ctx=$ctx)"; return 1; }
    grep -qxF -- "$ctx"       "$MOCK_ARGS_FILE" || { echo "FAIL: --ctx-size value '$ctx' missing"; return 1; }

    # Assert --parallel flag and value
    grep -qxF -- "--parallel" "$MOCK_ARGS_FILE" || { echo "FAIL: --parallel flag missing (parallel=$parallel)"; return 1; }
    grep -qxF -- "$parallel"  "$MOCK_ARGS_FILE" || { echo "FAIL: --parallel value '$parallel' missing"; return 1; }

    # Assert --verbosity flag and numeric value
    grep -qxF -- "--verbosity" "$MOCK_ARGS_FILE" || { echo "FAIL: --verbosity flag missing (log_level=$log_level)"; return 1; }
    grep -qxF -- "$verbosity"  "$MOCK_ARGS_FILE" || { echo "FAIL: --verbosity value '$verbosity' missing for log_level='$log_level'"; return 1; }
}

# ---------------------------------------------------------------------------
# Property test — minimum 2 iterations with random inputs
# ---------------------------------------------------------------------------

@test "Property 1: server flags are forwarded for any env var combination" {
    # Validates: Requirements 2.7
    local log_levels="error warn info debug"
    local iterations=2

    for i in $(seq 1 $iterations); do
        # Random IPv4 address in the 10.x.x.x range
        local host="10.$((RANDOM % 256)).$((RANDOM % 256)).$((RANDOM % 256))"

        # Random port in the range 1024–65535
        local port="$((1024 + RANDOM % 64512))"

        # Random context size in the range 128–8192
        local ctx="$((128 + RANDOM % 8065))"

        # Random parallel slot count in the range 1–16
        local parallel="$((1 + RANDOM % 16))"

        # Random LOG_LEVEL from the allowed enum
        local level_index="$((RANDOM % 4))"
        local log_level
        log_level="$(echo $log_levels | tr ' ' '\n' | sed -n "$((level_index + 1))p")"

        assert_flags_forwarded "$host" "$port" "$ctx" "$parallel" "$log_level"
    done
}
