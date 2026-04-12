#!/bin/sh
# Container entrypoint — resolves the model and launches llama-server.
set -e
set -u

# Parse optional arguments
DOWNLOAD_ONLY=0
for arg in "$@"; do
    case "$arg" in
        --download-only)
            DOWNLOAD_ONLY=1
            ;;
    esac
done

# ---------------------------------------------------------------------------
# Model path resolution
# ---------------------------------------------------------------------------
MODEL_PATH="${MODEL_PATH:-}"
MODEL_REPO="${MODEL_REPO:-}"
MODEL_FILE="${MODEL_FILE:-}"
HF_TOKEN="${HF_TOKEN:-}"

if [ -n "$MODEL_PATH" ]; then
    # Use the explicitly provided model path
    if [ ! -f "$MODEL_PATH" ]; then
        echo "ERROR: MODEL_PATH is set to '$MODEL_PATH' but the file does not exist." >&2
        exit 1
    fi
    MODEL_FILE_PATH="$MODEL_PATH"
elif [ -n "$MODEL_REPO" ] && [ -n "$MODEL_FILE" ]; then
    # Download model from Hugging Face
    echo "Downloading '$MODEL_FILE' from Hugging Face repository '$MODEL_REPO'..."
    hf download "$MODEL_REPO" "$MODEL_FILE" \
        --local-dir /models \
        ${HF_TOKEN:+--token "$HF_TOKEN"}
    MODEL_FILE_PATH="/models/$MODEL_FILE"
else
    echo "ERROR: No model specified. Set MODEL_PATH, or set both MODEL_REPO and MODEL_FILE." >&2
    exit 1
fi

# Handle --download-only mode: exit after download without starting the server
if [ "$DOWNLOAD_ONLY" -eq 1 ]; then
    echo "Model downloaded to '$MODEL_FILE_PATH'. Exiting (--download-only)."
    exit 0
fi

# TODO (task 3.3): environment variable to llama-server CLI flag mapping
# TODO (task 3.4): exec llama-server with resolved model path and flags
