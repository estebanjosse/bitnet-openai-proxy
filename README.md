# bitnet-openai-proxy

> **OpenAI-compatible inference server for [BitNet.cpp](https://github.com/microsoft/BitNet), packaged as a Docker container.**

Self-host a lightweight, 1-bit LLM inference server that speaks the OpenAI API protocol — with no Python layer and no bloat.

[![GitHub Container Registry](https://img.shields.io/badge/ghcr.io-bitnet--openai--proxy-blue?logo=github)](https://github.com/estebanjosse/bitnet-openai-proxy/pkgs/container/bitnet-openai-proxy)
[![License](https://img.shields.io/github/license/estebanjosse/bitnet-openai-proxy)](LICENSE)

---

## Table of Contents

- [Overview](#overview)
- [Quick Start](#quick-start)
  - [Demo Mode](#demo-mode)
  - [Production Mode](#production-mode)
- [Docker Images](#docker-images)
- [Environment Variables](#environment-variables)
- [API Usage](#api-usage)
- [Model Management](#model-management)
- [CI/CD & Image Registry](#cicd--image-registry)
- [CPU Optimisation & Portability](#cpu-optimisation--portability)
- [Design Decisions](#design-decisions)
- [Roadmap](#roadmap)

---

## Overview

**bitnet-openai-proxy** packages [BitNet.cpp](https://github.com/microsoft/BitNet) — Microsoft's efficient 1-bit LLM inference engine built on the llama.cpp ecosystem — into a Docker container that exposes an **OpenAI-compatible REST API**.

Key goals for v1:

- Drop-in replacement for OpenAI API calls (`/v1/chat/completions`) with a self-hosted model.
- Minimal runtime footprint: the C++ `llama-server` binary is the only inference process.
- Two deployment flavours: a **demo image** for instant evaluation, and a **production image** for real deployments.
- Simple configuration via environment variables.

---

## Quick Start

### Prerequisites

- [Docker](https://docs.docker.com/get-docker/) ≥ 24
- (Production mode) A compatible BitNet GGUF model file or access to Hugging Face

---

### Demo Mode

The demo image ships with a pre-downloaded model. It is ready to serve requests immediately after `docker run`.

```bash
docker run --rm -p 8080:8080 \
  ghcr.io/estebanjosse/bitnet-openai-proxy:latest-demo
```

The server is ready when you see:
```
llama server listening at http://0.0.0.0:8080
```

---

### Production Mode

The production image contains no model. The model is downloaded (or loaded from a mounted volume) at container startup via the entrypoint script.

#### Option A — Download model at startup (Hugging Face)

```bash
docker run --rm -p 8080:8080 \
  -e MODEL_REPO="microsoft/bitnet-b1.58-2B-4T-gguf" \
  -e MODEL_FILE="ggml-model-i2_s.gguf" \
  -e HF_TOKEN="hf_..." \          # optional, for gated repos
  ghcr.io/estebanjosse/bitnet-openai-proxy:latest
```

#### Option B — Mount a local model (recommended for production)

Pre-download the model once, then bind-mount it for fast, reproducible container starts:

```bash
# Download once
mkdir -p ./models
hf download microsoft/bitnet-b1.58-2B-4T-gguf \
  ggml-model-i2_s.gguf --local-dir ./models

# Run with mounted model
docker run --rm -p 8080:8080 \
  -v "$(pwd)/models:/models:ro" \
  -e MODEL_PATH="/models/ggml-model-i2_s.gguf" \
  ghcr.io/estebanjosse/bitnet-openai-proxy:latest
```

#### Option C — Docker Compose (recommended for persistent deployments)

```yaml
# docker-compose.yml
services:
  bitnet:
    image: ghcr.io/estebanjosse/bitnet-openai-proxy:latest
    ports:
      - "8080:8080"
    volumes:
      - ./models:/models:ro
    environment:
      MODEL_PATH: /models/ggml-model-i2_s.gguf
      SERVER_HOST: 0.0.0.0
      SERVER_PORT: 8080
      CTX_SIZE: 4096
    restart: unless-stopped
```

```bash
docker compose up -d
```

---

## Docker Images

### Multi-stage Build

The `Dockerfile` uses a **two-stage build** to keep the runtime image lean:

| Stage | Base image | Purpose |
|-------|-----------|---------|
| `builder` | `ubuntu:22.04` (or similar build image) | Compiles BitNet.cpp from a pinned commit/tag |
| `runtime` | `ubuntu:22.04` (minimal) | Contains only the compiled binary and shared libraries |

The model is **never baked into the production image**. Model files are large, change frequently, and are better managed separately.

### Image Variants

| Variant | Tag suffix | Model included | Intended use |
|---------|-----------|----------------|-------------|
| **Demo** | `-demo` | ✅ Yes (baked in) | Quick evaluation, CI smoke-tests, demos |
| **Production** | *(default)* | ❌ No | Real deployments; model loaded at runtime |

---

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `MODEL_PATH` | — | Absolute path to the GGUF model file inside the container. Takes precedence over `MODEL_REPO`/`MODEL_FILE`. |
| `MODEL_REPO` | — | Hugging Face repository ID (e.g. `microsoft/bitnet-b1.58-2B-4T-gguf`). Used when `MODEL_PATH` is not set. |
| `MODEL_FILE` | — | Filename within `MODEL_REPO` to download (e.g. `ggml-model-i2_s.gguf`). |
| `HF_TOKEN` | — | Hugging Face access token for gated/private repositories. |
| `SERVER_HOST` | `0.0.0.0` | Host address the server binds to. |
| `SERVER_PORT` | `8080` | Port the server listens on. |
| `CTX_SIZE` | `2048` | Context window size (tokens). |
| `N_THREADS` | *(auto)* | Number of CPU threads. Defaults to all available cores. |
| `N_PARALLEL` | `1` | Number of parallel inference slots (concurrent requests). |
| `LOG_LEVEL` | `info` | Server log verbosity. Accepted values: `debug`, `info`, `warn`, `error`. |

---

## API Usage

The server exposes OpenAI-compatible endpoints. Any client that supports the OpenAI API can point to this server with minimal configuration changes.

### Health check

```bash
curl http://localhost:8080/health
```

### List models

```bash
curl http://localhost:8080/v1/models
```

### Chat completion

```bash
curl http://localhost:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "bitnet",
    "messages": [
      {"role": "system", "content": "You are a helpful assistant."},
      {"role": "user",   "content": "Explain 1-bit LLMs in one paragraph."}
    ],
    "temperature": 0.7,
    "max_tokens": 256
  }'
```

### Using the OpenAI Python SDK

```python
from openai import OpenAI

client = OpenAI(
    base_url="http://localhost:8080/v1",
    api_key="not-required",          # server does not enforce auth in v1
)

response = client.chat.completions.create(
    model="bitnet",
    messages=[{"role": "user", "content": "Hello!"}],
)
print(response.choices[0].message.content)
```

---

## Model Management

### Recommended models

BitNet.cpp requires models quantised with the BitNet format. The official Microsoft models are available on Hugging Face:

| Model | Repo | Size (GGUF) |
|-------|------|-------------|
| BitNet b1.58 2B 4T | `microsoft/bitnet-b1.58-2B-4T-gguf` | ~0.7 GB |

> More models and quantisation variants will be listed here as the BitNet ecosystem grows.

### Storage strategy

- **Development / demo**: use the `-demo` image. The model is baked in; no volume management needed.
- **Staging / production**: mount a named volume or host directory at `/models`. Download the model once; reuse across container restarts and upgrades.
- **Shared model cache (multi-container)**: mount the same volume read-only (`ro`) across multiple replicas.

```bash
# Create a named volume once
docker volume create bitnet-models

# Download model into the volume (run once)
docker run --rm \
  -v bitnet-models:/models \
  -e MODEL_REPO="microsoft/bitnet-b1.58-2B-4T-gguf" \
  -e MODEL_FILE="ggml-model-i2_s.gguf" \
  ghcr.io/estebanjosse/bitnet-openai-proxy:latest --download-only

# Start the server using the cached model
docker run -d -p 8080:8080 \
  -v bitnet-models:/models:ro \
  -e MODEL_PATH="/models/ggml-model-i2_s.gguf" \
  ghcr.io/estebanjosse/bitnet-openai-proxy:latest
```

---

## CI/CD & Image Registry

### GitHub Actions

Images are built and pushed automatically via GitHub Actions on every push to `main` and on version tags.

**Workflow summary:**

1. **Build** — multi-stage Docker build for both `production` and `demo` variants.
2. **Test** — smoke-test the production image against a known-good model.
3. **Push** — publish to [GitHub Container Registry (GHCR)](https://ghcr.io/estebanjosse/bitnet-openai-proxy).

### Tagging strategy

| Event | Tags applied |
|-------|-------------|
| Push to `main` | `latest`, `main-<short-sha>` |
| Version tag (`v1.2.3`) | `1.2.3`, `1.2`, `1`, `latest` |
| Pull request | `pr-<number>` (not pushed to registry) |

The same scheme is applied to both variants, with a `-demo` suffix for the demo image:

```
ghcr.io/estebanjosse/bitnet-openai-proxy:latest
ghcr.io/estebanjosse/bitnet-openai-proxy:latest-demo
ghcr.io/estebanjosse/bitnet-openai-proxy:1.2.3
ghcr.io/estebanjosse/bitnet-openai-proxy:1.2.3-demo
ghcr.io/estebanjosse/bitnet-openai-proxy:main-a1b2c3d
```

### Pulling images

```bash
# Latest production image
docker pull ghcr.io/estebanjosse/bitnet-openai-proxy:latest

# Latest demo image
docker pull ghcr.io/estebanjosse/bitnet-openai-proxy:latest-demo

# Specific version
docker pull ghcr.io/estebanjosse/bitnet-openai-proxy:1.2.3
```

---

## CPU Optimisation & Portability

BitNet.cpp ships with several architecture-specific optimised kernels. The `CMAKE_EXTRA_FLAGS` build argument lets you select the right kernel path for your hardware.

| `CMAKE_EXTRA_FLAGS` value | Architecture | Notes |
|---------------------------|-------------|-------|
| `-DBITNET_X86_TL2=OFF` *(default)* | x86-64 | Portable i2_s quantisation path; runs on any x86-64 CPU |
| `-DBITNET_X86_TL2=ON` | x86-64 | TL2 LUT kernels; higher throughput on modern x86-64 CPUs |
| `-DBITNET_ARM_TL1=ON` | ARM64 | TL1 kernels for ARM64 (Apple Silicon, ARM servers) |

> **Note:** The pre-built GHCR images use the default portable i2_s path (`-DBITNET_X86_TL2=OFF`). For TL2 or ARM64 workloads, build the image locally with the appropriate flags.

### Local build

```bash
# x86-64 i2_s — portable default (any x86-64 CPU)
docker build -t bitnet-openai-proxy .

# x86-64 TL2 kernels — higher throughput on modern x86-64 CPUs
docker build \
  --build-arg CMAKE_EXTRA_FLAGS="-DBITNET_X86_TL2=ON" \
  -t bitnet-openai-proxy:tl2 .

# ARM64 TL1 kernels — Apple Silicon, ARM servers
docker build \
  --platform linux/arm64 \
  --build-arg CMAKE_EXTRA_FLAGS="-DBITNET_ARM_TL1=ON" \
  -t bitnet-openai-proxy:arm64 .

# Demo image (model baked in), portable default
docker build --target demo -t bitnet-openai-proxy:demo .
```

You can also pin a specific BitNet.cpp commit with `--build-arg BITNET_COMMIT=<sha>` to test a particular upstream version, or point to a fork with `--build-arg BITNET_REPO=https://github.com/<owner>/<name>`.

### Performance tips

- Set `N_THREADS` to match your physical core count (not hyperthreaded count) for best throughput.
- Use `N_PARALLEL` > 1 only if you expect concurrent requests; each parallel slot consumes additional memory.
- Pin the container to specific CPUs with `--cpuset-cpus` to avoid NUMA effects on multi-socket systems.
- For maximum throughput on modern x86-64 hardware, build with `-DBITNET_X86_TL2=ON`.

---

## Design Decisions

### Why no Python/FastAPI layer in v1?

BitNet.cpp's `llama-server` already implements the OpenAI chat completions API in C++. Adding a Python reverse-proxy would introduce latency, additional dependencies, and operational complexity without providing meaningful benefit at this stage. A thin adapter layer may be added in future versions if broader API compatibility (e.g. Responses API, function calling) requires it.

### Why are models not baked into the production image?

Model files are large (hundreds of MB to several GB) and updated independently of the server binary. Baking them in would:

- Make every server-code change trigger a multi-GB image rebuild and push.
- Bloat the registry with duplicate model layers.
- Complicate model versioning and rollback.

The **demo image** intentionally breaks this rule for convenience — acceptable because it is a single-purpose, disposable artefact.

### Why a pinned BitNet.cpp commit?

Reproducibility. BitNet.cpp is under active development; pinning to a tested commit ensures that the image build is deterministic and that behaviour does not change unexpectedly between CI runs. The pin is updated intentionally as part of the release process.

The `BITNET_REPO` build argument lets you point the build at a fork without modifying the Dockerfile, which is useful for testing upstream patches or custom kernels before they land in the default repo.

---

## Roadmap

The following features are planned for future versions:

- [ ] **Streaming responses** — server-sent events for `stream: true` requests
- [ ] **Tool / function calling** — structured output and tool-use support
- [ ] **OpenAI Responses API** — compatibility with the newer `POST /v1/responses` endpoint
- [ ] **Metrics endpoint** — Prometheus-compatible `/metrics` for inference throughput and latency
- [ ] **Authentication** — optional API-key enforcement at the server level
- [ ] **Embeddings** — `POST /v1/embeddings` support
- [ ] **ARM64 GHCR images** — pre-built images for Apple Silicon and ARM servers
- [ ] **Kubernetes Helm chart** — production-grade deployment manifests

---

## Contributing

Contributions are welcome! Please open an issue to discuss significant changes before submitting a pull request.

## License

This project is licensed under the terms of the [LICENSE](LICENSE) file in this repository.
