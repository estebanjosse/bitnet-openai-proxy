# Requirements Document

## Introduction

`bitnet-openai-proxy` is an OpenAI-compatible inference server for BitNet.cpp, packaged as a Docker container. It exposes an OpenAI-compatible REST API (`/v1/chat/completions`) by relying directly on the C++ `llama-server` binary from BitNet.cpp, with no intermediate Python layer. The project provides two Docker image variants: a **demo** image (model included) and a **production** image (model loaded at runtime). A GitHub Actions CI/CD pipeline builds, tests, and publishes images to GitHub Container Registry (GHCR).

---

## Glossary

- **BitNet.cpp**: Microsoft's open-source 1-bit LLM inference engine, built on the llama.cpp ecosystem.
- **llama-server**: C++ binary provided by BitNet.cpp that exposes an OpenAI-compatible REST API.
- **GGUF**: Model file format used by llama.cpp and BitNet.cpp.
- **Entrypoint_Script**: Shell script executed at container startup that orchestrates model loading and launches `llama-server`.
- **Demo_Image**: Docker image variant with a baked-in model, intended for quick evaluation.
- **Production_Image**: Docker image variant without a model, intended for real deployments.
- **Builder_Stage**: Multi-stage Docker stage that compiles BitNet.cpp from a pinned commit.
- **Runtime_Stage**: Multi-stage Docker stage that contains only the compiled binary and its dependencies.
- **GHCR**: GitHub Container Registry, Docker image registry hosted by GitHub.
- **HF**: Hugging Face, machine learning model sharing platform.
- **CI_Pipeline**: GitHub Actions pipeline that builds, tests, and publishes Docker images.

---

## Requirements

### Requirement 1: Multi-stage Docker Build

**User Story:** As a project maintainer, I want a multi-stage Dockerfile, so that the runtime image is minimal and contains only the binary and its dependencies.

#### Acceptance Criteria

1. THE Builder_Stage SHALL compile BitNet.cpp from a pinned Git commit configurable via a build argument.
2. THE Builder_Stage SHALL produce the `llama-server` binary and the required shared libraries.
3. THE Runtime_Stage SHALL copy only the `llama-server` binary and shared libraries from the Builder_Stage.
4. THE Runtime_Stage SHALL use a minimal base image (`ubuntu:22.04` or equivalent).
5. THE Dockerfile SHALL expose a `CMAKE_EXTRA_FLAGS` build argument to pass additional CMake flags at compile time.
6. WHEN `CMAKE_EXTRA_FLAGS` is not provided, THE Builder_Stage SHALL compile with AVX2 flags enabled by default for x86-64.
7. WHERE the `--platform linux/arm64` build argument is provided, THE Builder_Stage SHALL accept ARM64 flags via `CMAKE_EXTRA_FLAGS`.

---

### Requirement 2: Entrypoint Script — Model Loading

**User Story:** As an operator, I want a flexible entrypoint script, so that I can provide a model in multiple ways without modifying the image.

#### Acceptance Criteria

1. WHEN the `MODEL_PATH` environment variable is set, THE Entrypoint_Script SHALL use the GGUF file at that path to start `llama-server`.
2. WHEN `MODEL_PATH` is not set and both `MODEL_REPO` and `MODEL_FILE` are set, THE Entrypoint_Script SHALL download `MODEL_FILE` from the HF repository `MODEL_REPO` before starting `llama-server`.
3. WHEN `HF_TOKEN` is set, THE Entrypoint_Script SHALL pass the authentication token when downloading from Hugging Face.
4. WHEN the `--download-only` argument is passed to the container, THE Entrypoint_Script SHALL download the model to `/models` and exit without starting `llama-server`.
5. IF neither `MODEL_PATH` nor (`MODEL_REPO` and `MODEL_FILE`) are set, THEN THE Entrypoint_Script SHALL print an explicit error message and exit with a non-zero exit code.
6. IF the file referenced by `MODEL_PATH` does not exist, THEN THE Entrypoint_Script SHALL print an explicit error message and exit with a non-zero exit code.
7. THE Entrypoint_Script SHALL pass `SERVER_HOST`, `SERVER_PORT`, `CTX_SIZE`, `N_THREADS`, `N_PARALLEL`, and `LOG_LEVEL` to `llama-server` via the corresponding flags.
8. WHEN `N_THREADS` is not set, THE Entrypoint_Script SHALL let `llama-server` auto-detect the number of available threads.

---

### Requirement 3: Environment Variables

**User Story:** As an operator, I want to configure the server solely via environment variables, so that I do not need to modify the image or the script.

#### Acceptance Criteria

1. THE Entrypoint_Script SHALL recognise the following environment variables: `MODEL_PATH`, `MODEL_REPO`, `MODEL_FILE`, `HF_TOKEN`, `SERVER_HOST`, `SERVER_PORT`, `CTX_SIZE`, `N_THREADS`, `N_PARALLEL`, `LOG_LEVEL`.
2. WHEN `SERVER_HOST` is not set, THE Entrypoint_Script SHALL use the default value `0.0.0.0`.
3. WHEN `SERVER_PORT` is not set, THE Entrypoint_Script SHALL use the default value `8080`.
4. WHEN `CTX_SIZE` is not set, THE Entrypoint_Script SHALL use the default value `2048`.
5. WHEN `N_PARALLEL` is not set, THE Entrypoint_Script SHALL use the default value `1`.
6. WHEN `LOG_LEVEL` is not set, THE Entrypoint_Script SHALL use the default value `info`.

---

### Requirement 4: OpenAI-Compatible REST API

**User Story:** As a developer, I want the server to expose an OpenAI-compatible API, so that I can reuse my existing OpenAI clients without modification.

#### Acceptance Criteria

1. WHILE `llama-server` is running, THE llama-server SHALL respond to `GET /health` requests with HTTP status 200.
2. WHILE `llama-server` is running, THE llama-server SHALL respond to `GET /v1/models` requests with the list of loaded models in OpenAI-compatible JSON format.
3. WHILE `llama-server` is running, THE llama-server SHALL process `POST /v1/chat/completions` requests with a JSON body conforming to the OpenAI Chat Completions format.
4. WHEN a valid `POST /v1/chat/completions` request is received, THE llama-server SHALL return a JSON response conforming to the OpenAI Chat Completions format with HTTP status 200.
5. IF a `POST /v1/chat/completions` request contains an invalid JSON body, THEN THE llama-server SHALL return HTTP status 400 with an error message.

---

### Requirement 5: Demo Image

**User Story:** As an evaluator, I want a ready-to-use Docker image with a bundled model, so that I can test the server without managing volumes or downloads.

#### Acceptance Criteria

1. THE Demo_Image SHALL include a pre-downloaded BitNet GGUF model baked into the image at build time.
2. WHEN the Demo_Image container is started with no environment variables, THE Entrypoint_Script SHALL start `llama-server` with the bundled model.
3. THE Demo_Image SHALL be built from the same Dockerfile as the Production_Image, using a distinct build argument or build target.

---

### Requirement 6: Production Image

**User Story:** As a production operator, I want a Docker image with no bundled model, so that I can manage the model independently of the image and minimise image size.

#### Acceptance Criteria

1. THE Production_Image SHALL contain no GGUF model files.
2. THE Production_Image SHALL support model loading via `MODEL_PATH` (mounted volume) or via `MODEL_REPO`/`MODEL_FILE` (HF download at startup).
3. THE Production_Image SHALL expose port `8080` by default.

---

### Requirement 7: GitHub Actions CI/CD Pipeline

**User Story:** As a maintainer, I want an automated CI/CD pipeline, so that images are built, tested, and published automatically on every push.

#### Acceptance Criteria

1. WHEN a commit is pushed to the `main` branch, THE CI_Pipeline SHALL build both image variants (Production_Image and Demo_Image).
2. WHEN a commit is pushed to the `main` branch, THE CI_Pipeline SHALL run a smoke-test against the Production_Image.
3. WHEN the smoke-test passes, THE CI_Pipeline SHALL push images to GHCR with the `latest` and `main-<short-sha>` tags.
4. WHEN a version tag `vX.Y.Z` is created, THE CI_Pipeline SHALL push images with tags `X.Y.Z`, `X.Y`, `X`, and `latest` for the Production_Image, and the same tags suffixed with `-demo` for the Demo_Image.
5. WHEN a pull request is opened, THE CI_Pipeline SHALL build images without pushing to GHCR and apply the `pr-<number>` tag.
6. THE CI_Pipeline SHALL authenticate with GHCR using the `GITHUB_TOKEN` provided by GitHub Actions.
7. IF the smoke-test fails, THEN THE CI_Pipeline SHALL mark the workflow as failed and not push images to GHCR.

---

### Requirement 8: CI Smoke-Test

**User Story:** As a maintainer, I want an automated smoke-test of the production image, so that regressions are caught before publishing.

#### Acceptance Criteria

1. THE CI_Pipeline SHALL start a Production_Image container with a test model provided via `MODEL_PATH`.
2. WHEN the container is started, THE CI_Pipeline SHALL wait for the `GET /health` endpoint to return HTTP 200 before continuing.
3. THE CI_Pipeline SHALL send a `POST /v1/chat/completions` request to the container and verify that the response has HTTP status 200.
4. IF the container does not respond to `GET /health` within 60 seconds, THEN THE CI_Pipeline SHALL mark the smoke-test as failed.

---

### Requirement 9: CPU Optimisations and Portability

**User Story:** As an operator, I want to build the image with specific CPU optimisations, so that I get the best performance on my hardware.

#### Acceptance Criteria

1. THE Dockerfile SHALL accept a `CMAKE_EXTRA_FLAGS` build argument to pass additional CMake optimisation flags.
2. WHEN `CMAKE_EXTRA_FLAGS` contains `-DBITNET_AVX512=ON`, THE Builder_Stage SHALL compile BitNet.cpp with AVX-512 support.
3. WHEN the build is run with `--platform linux/arm64` and `CMAKE_EXTRA_FLAGS` contains `-DBITNET_ARM_TL1=ON`, THE Builder_Stage SHALL compile BitNet.cpp with ARM64 optimisations.
4. THE Dockerfile SHALL document the recommended `CMAKE_EXTRA_FLAGS` values for x86-64 (AVX2, AVX-512) and ARM64 architectures in comments.
