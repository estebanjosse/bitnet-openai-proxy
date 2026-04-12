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

# TODO (task 3.2): model path resolution and Hugging Face download logic
# TODO (task 3.3): environment variable to llama-server CLI flag mapping
# TODO (task 3.4): exec llama-server with resolved model path and flags
