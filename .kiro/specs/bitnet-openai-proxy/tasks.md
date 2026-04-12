# Implementation Plan: bitnet-openai-proxy

## Overview

This implementation plan breaks down the bitnet-openai-proxy feature into discrete coding tasks. The project packages BitNet.cpp into a Docker container with an OpenAI-compatible REST API. The implementation focuses on creating a multi-stage Dockerfile, a shell entrypoint script for model loading, and a GitHub Actions CI/CD pipeline.

## Tasks

- [ ] 1. Set up project structure and Git submodule
  - Create `3rdparty/` directory
  - Add BitNet.cpp as a Git submodule at `3rdparty/BitNet` pointing to `https://github.com/estebanjosse/BitNet`
  - Pin the submodule to a tested commit
  - Create `.gitmodules` configuration
  - _Requirements: 1.1_

- [ ] 2. Create multi-stage Dockerfile
  - [ ] 2.1 Implement builder stage
    - Define `ARG BITNET_COMMIT` with default from submodule
    - Define `ARG CMAKE_EXTRA_FLAGS` with default `-DBITNET_AVX2=ON`
    - Use `ubuntu:22.04` as base image
    - Install build dependencies (cmake ≥ 3.22, clang ≥ 18, git, python3, make)
    - Copy BitNet.cpp submodule from build context
    - Run cmake with `CMAKE_EXTRA_FLAGS` and compile `llama-server` binary
    - _Requirements: 1.1, 1.2, 1.5, 1.6_

  - [ ] 2.2 Implement runtime stage
    - Use `ubuntu:22.04` as minimal base image
    - Install runtime dependencies only (libstdc++6, libgomp1, curl, python3, pip)
    - Install `huggingface-hub` Python package for CLI tool
    - Copy `llama-server` binary from builder stage
    - Copy required shared libraries from builder stage
    - Create `/models` directory
    - Set `EXPOSE 8080`
    - _Requirements: 1.3, 1.4_

  - [ ] 2.3 Implement demo build target
    - Extend runtime stage with `demo` target
    - Add `RUN` step to download default GGUF model to `/models/` at build time
    - Set `ENV MODEL_PATH=/models/<default-model-file>`
    - _Requirements: 5.1, 5.2, 5.3_

  - [ ] 2.4 Add Dockerfile documentation comments
    - Document `BITNET_COMMIT` build argument usage
    - Document `CMAKE_EXTRA_FLAGS` examples for x86-64 AVX2, AVX-512, and ARM64
    - Document build targets (production vs demo)
    - _Requirements: 1.7, 9.4_

- [ ] 3. Implement entrypoint script
  - [ ] 3.1 Create entrypoint.sh with POSIX shell
    - Add shebang `#!/bin/sh`
    - Enable strict error handling (`set -e`, `set -u`)
    - Parse `--download-only` optional argument
    - _Requirements: 2.4_

  - [ ] 3.2 Implement model path resolution logic
    - Check if `MODEL_PATH` is set and file exists
    - If `MODEL_PATH` not set, check for `MODEL_REPO` and `MODEL_FILE`
    - Implement Hugging Face download using `huggingface-cli download`
    - Pass `HF_TOKEN` to download command when set
    - Handle `--download-only` mode (download and exit without starting server)
    - Print explicit error messages for missing or invalid model configuration
    - Exit with non-zero code on errors
    - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5, 2.6_

  - [ ] 3.3 Implement environment variable to CLI flag mapping
    - Map `SERVER_HOST` to `--host` (default: `0.0.0.0`)
    - Map `SERVER_PORT` to `--port` (default: `8080`)
    - Map `CTX_SIZE` to `--ctx-size` (default: `2048`)
    - Map `N_THREADS` to `--threads` (omit if not set for auto-detection)
    - Map `N_PARALLEL` to `--parallel` (default: `1`)
    - Map `LOG_LEVEL` to `--log-level` (default: `info`)
    - Build `llama-server` command line with all flags
    - _Requirements: 2.7, 2.8, 3.1, 3.2, 3.3, 3.4, 3.5, 3.6_

  - [ ] 3.4 Execute llama-server
    - Use `exec` to replace shell process with `llama-server`
    - Pass resolved model path via `--model` flag
    - Pass all environment-derived flags
    - _Requirements: 2.1, 2.7_

  - [ ]* 3.5 Write property test for entrypoint flag forwarding
    - **Property 1: Server flags are forwarded for any env var combination**
    - **Validates: Requirements 2.7**
    - Generate random values for SERVER_HOST, SERVER_PORT, CTX_SIZE, N_PARALLEL, LOG_LEVEL
    - Mock `llama-server` to capture arguments
    - Assert all expected flag-value pairs are present
    - Run minimum 2 iterations

  - [ ]* 3.6 Write property test for MODEL_PATH validation
    - **Property 2: Non-existent MODEL_PATH always produces a non-zero exit**
    - **Validates: Requirements 2.6**
    - Generate random non-existent file paths
    - Invoke entrypoint with each path
    - Assert exit code is non-zero and stderr contains error message
    - Run minimum 2 iterations

  - [ ]* 3.7 Write unit tests for entrypoint edge cases
    - Test `MODEL_PATH` set → `--model` flag present
    - Test `MODEL_REPO` + `MODEL_FILE` → `huggingface-cli download` called
    - Test `HF_TOKEN` set → `--token` flag present in download
    - Test `HF_TOKEN` not set → `--token` flag absent
    - Test `--download-only` → server not started, exit 0
    - Test `N_THREADS` not set → `--threads` flag absent
    - Test default values applied correctly
    - Test no model env vars → exit 1 with error
    - Test empty `MODEL_PATH` → exit 1 with error
    - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5, 2.6, 2.8, 3.2, 3.3, 3.4, 3.5, 3.6_

- [ ] 4. Checkpoint - Verify Dockerfile and entrypoint
  - Build production Docker image locally
  - Build demo Docker image locally
  - Test entrypoint script with mock llama-server
  - Ensure all tests pass, ask the user if questions arise.

- [ ] 5. Implement GitHub Actions CI/CD workflow
  - [ ] 5.1 Create workflow file structure
    - Create `.github/workflows/ci.yml`
    - Define workflow name and triggers (push to main, version tags, pull requests)
    - Set up GHCR authentication using `GITHUB_TOKEN`
    - _Requirements: 7.6_

  - [ ] 5.2 Implement build jobs for both image variants
    - Create `build-production` job using `docker/build-push-action`
    - Create `build-demo` job with `--target demo` flag
    - Use `docker/setup-buildx-action` for BuildKit
    - Use `docker/metadata-action` for tag generation
    - Configure jobs to run on push to main, version tags, and pull requests
    - _Requirements: 7.1, 7.5_

  - [ ] 5.3 Implement tag generation logic
    - Configure `docker/metadata-action` for production tags
    - Push to main: generate `latest`, `main-<sha7>` tags
    - Version tag `vX.Y.Z`: generate `X.Y.Z`, `X.Y`, `X`, `latest` tags
    - Pull request: generate `pr-<number>` tag (no push)
    - Configure demo variant with `-demo` suffix for all tags
    - _Requirements: 7.3, 7.4, 7.5_

  - [ ]* 5.4 Write property test for semver tag expansion
    - **Property 3: Semver tag expansion is correct for any valid version**
    - **Validates: Requirements 7.4**
    - Generate random non-negative integers X, Y, Z
    - Run tag generation logic
    - Assert output equals `{X.Y.Z, X.Y, X, latest}` for production
    - Assert output equals `{X.Y.Z-demo, X.Y-demo, X-demo, latest-demo}` for demo
    - Run minimum 10 iterations

  - [ ] 5.5 Implement smoke-test job
    - Start production container with test GGUF model via `MODEL_PATH`
    - Poll `GET /health` endpoint every 5 seconds, timeout after 60 seconds
    - Assert HTTP 200 response from health check
    - Send `POST /v1/chat/completions` with minimal valid payload
    - Assert HTTP 200 response from chat completions
    - Stop container after test
    - _Requirements: 8.1, 8.2, 8.3, 8.4_

  - [ ] 5.6 Implement push job with conditional execution
    - Create `push-ghcr` job that depends on smoke-test success
    - Condition push on `needs.smoke-test.result == 'success'`
    - Push both production and demo images to GHCR
    - Skip push for pull requests
    - Mark workflow as failed if smoke-test fails
    - _Requirements: 7.2, 7.3, 7.7_

- [ ] 6. Checkpoint - Verify CI/CD pipeline
  - Test workflow locally using `act` or similar tool
  - Verify tag generation logic produces correct tags
  - Verify smoke-test catches broken images
  - Ensure all tests pass, ask the user if questions arise.

- [ ] 7. Create integration test suite
  - [ ]* 7.1 Write integration tests for OpenAI API compatibility
    - Test `GET /health` returns HTTP 200 when server ready
    - Test `GET /v1/models` returns valid OpenAI models JSON
    - Test `POST /v1/chat/completions` with valid payload returns HTTP 200
    - Test `POST /v1/chat/completions` with invalid JSON returns HTTP 400
    - Test demo image starts with no env vars and serves requests
    - _Requirements: 4.1, 4.2, 4.3, 4.4, 4.5, 5.2, 6.2_

  - [ ]* 7.2 Write integration tests for model loading scenarios
    - Test production image with `MODEL_PATH` (mounted volume)
    - Test production image with `MODEL_REPO` + `MODEL_FILE` (HF download)
    - Test production image with `HF_TOKEN` for gated repos
    - Test `--download-only` mode downloads model and exits
    - _Requirements: 2.1, 2.2, 2.3, 2.4, 6.2_

- [ ] 8. Add CPU optimization build variants documentation
  - [ ] 8.1 Document build commands for different architectures
    - Add examples for x86-64 AVX2 (default)
    - Add examples for x86-64 AVX-512
    - Add examples for ARM64 with TL1 optimizations
    - Document `CMAKE_EXTRA_FLAGS` usage in README
    - _Requirements: 9.1, 9.2, 9.3, 9.4_

  - [ ]* 8.2 Test build variants locally
    - Build with AVX2 flags (default)
    - Build with AVX-512 flags
    - Build ARM64 variant (if ARM hardware available)
    - Verify each variant produces working binary
    - _Requirements: 9.1, 9.2, 9.3_

- [ ] 9. Final integration and documentation
  - [ ] 9.1 Update README with usage examples
    - Add quick start examples for demo mode
    - Add quick start examples for production mode (HF download and mounted volume)
    - Add Docker Compose example
    - Document environment variables table
    - Add API usage examples
    - _Requirements: 3.1, 4.1, 4.2, 4.3, 5.1, 5.2, 6.1, 6.2, 6.3_

  - [ ] 9.2 Create .dockerignore file
    - Exclude `.git/` directory
    - Exclude `.kiro/` directory
    - Exclude test files and CI artifacts
    - Keep `3rdparty/BitNet` submodule for build context

- [ ] 10. Final checkpoint - End-to-end validation
  - Build both image variants from scratch
  - Run full integration test suite
  - Test demo image with no configuration
  - Test production image with mounted model
  - Test production image with HF download
  - Verify CI workflow runs successfully
  - Ensure all tests pass, ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional and can be skipped for faster MVP
- Each task references specific requirements for traceability
- Checkpoints ensure incremental validation at key milestones
- Property tests validate universal correctness properties from the design
- Unit tests validate specific examples and edge cases
- Integration tests verify end-to-end functionality with real containers
- The entrypoint script is the only custom logic component requiring extensive testing
- Dockerfile and CI workflow are primarily declarative and verified through smoke tests
