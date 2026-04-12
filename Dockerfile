# BITNET_COMMIT: Git commit SHA to clone from estebanjosse/BitNet.
#                Defaults to the commit pinned in the 3rdparty/BitNet submodule.
#                Override with --build-arg BITNET_COMMIT=<sha> to test a specific commit.
#
# CMAKE_EXTRA_FLAGS examples:
# x86-64 i2_s (default):  --build-arg CMAKE_EXTRA_FLAGS="-DBITNET_X86_TL2=OFF"
# x86-64 TL2 kernels:     --build-arg CMAKE_EXTRA_FLAGS="-DBITNET_X86_TL2=ON"
# ARM64 TL1 kernels:      --platform linux/arm64 --build-arg CMAKE_EXTRA_FLAGS="-DBITNET_ARM_TL1=ON"

# ── Builder stage ─────────────────────────────────────────────────────────────
FROM ubuntu:22.04 AS builder

ARG BITNET_COMMIT=caf1ce1de9096b7c32fb058061cf08c79a972761
ARG CMAKE_EXTRA_FLAGS="-DBITNET_X86_TL2=OFF"

# Install build dependencies.
# cmake from the Kitware apt repo ensures version ≥ 3.22 (Ubuntu 22.04 ships 3.22.1,
# but we pin via the official Kitware repo for reliability).
# clang-18 is required by BitNet.cpp for its LUT kernel compilation.
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        gnupg \
        lsb-release \
        software-properties-common \
    && curl -fsSL https://apt.kitware.com/keys/kitware-archive-latest.asc \
        | gpg --dearmor -o /usr/share/keyrings/kitware-archive-keyring.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/kitware-archive-keyring.gpg] \
        https://apt.kitware.com/ubuntu/ $(lsb_release -cs) main" \
        > /etc/apt/sources.list.d/kitware.list \
    && add-apt-repository -y ppa:ubuntu-toolchain-r/test \
    && curl -fsSL https://apt.llvm.org/llvm-snapshot.gpg.key \
        | gpg --dearmor -o /usr/share/keyrings/llvm-archive-keyring.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/llvm-archive-keyring.gpg] \
        https://apt.llvm.org/jammy/ llvm-toolchain-jammy-18 main" \
        > /etc/apt/sources.list.d/llvm-18.list \
    && apt-get update && apt-get install -y --no-install-recommends \
        cmake \
        clang-18 \
        git \
        make \
        python3 \
        python3-pip \
    && rm -rf /var/lib/apt/lists/*

# Use clang-18 as the default C/C++ compiler.
ENV CC=clang-18
ENV CXX=clang++-18

WORKDIR /build

# Clone BitNet.cpp at the pinned commit and initialise nested submodules.
# A full git clone is required so that `git submodule update` can resolve
# the nested llama.cpp submodule — a plain COPY of the directory has no
# .git metadata and cannot initialise submodules.
RUN git clone https://github.com/estebanjosse/BitNet /build/BitNet \
    && git -C /build/BitNet checkout "$BITNET_COMMIT" \
    && git -C /build/BitNet submodule update --init --recursive

# Configure and build llama-server.
# BitNet's build unconditionally includes include/bitnet-lut-kernels.h, which must
# be generated before cmake runs. We copy the pretuned TL2 kernel header for the
# bitnet_b1_58-3B preset (also used by BitNet-b1.58-2B-4T) as a generic baseline.
# The header is only active at runtime when GGML_BITNET_X86_TL2 is defined; for
# the default i2_s path it is included but its symbols are never called.
RUN pip3 install --no-cache-dir /build/BitNet/3rdparty/llama.cpp/gguf-py \
    && cp /build/BitNet/preset_kernels/bitnet_b1_58-3B/bitnet-lut-kernels-tl2.h \
          /build/BitNet/include/bitnet-lut-kernels.h \
    && cmake -S /build/BitNet -B /build/cmake-build \
        -DCMAKE_C_COMPILER=clang-18 \
        -DCMAKE_CXX_COMPILER=clang++-18 \
        ${CMAKE_EXTRA_FLAGS} \
    && cmake --build /build/cmake-build --target llama-server --parallel $(nproc)

# ── Runtime stage ─────────────────────────────────────────────────────────────
FROM ubuntu:22.04 AS runtime

# Install runtime dependencies only (no build tools).
# libstdc++6 and libgomp1 are required by the llama-server binary.
# python3 and python3-pip are included solely for the huggingface-cli download tool.
RUN apt-get update && apt-get install -y --no-install-recommends \
        libstdc++6 \
        libgomp1 \
        curl \
        python3 \
        python3-pip \
    && rm -rf /var/lib/apt/lists/*

# Install the Hugging Face Hub CLI for model downloads at container startup.
RUN pip3 install --no-cache-dir huggingface-hub

# Copy cmake-produced shared libraries from the builder stage into a standard
# library path, then update the dynamic linker cache so llama-server can resolve
# them at startup. Docker COPY does not recurse across subdirectories with a glob,
# so we use a bind-mount with find+cp to collect all .so* files produced under
# /build/cmake-build/ (libllama.so, libggml.so, libggml-base.so, etc.).
RUN --mount=type=bind,from=builder,source=/build/cmake-build,target=/build/cmake-build \
    find /build/cmake-build -name '*.so*' -exec cp -P {} /usr/local/lib/ \; \
    && ldconfig

# Copy the llama-server binary from the builder stage.
COPY --from=builder /build/cmake-build/bin/llama-server /usr/local/bin/llama-server

# Create the models directory for volume mounts or downloaded models.
RUN mkdir /models

# Copy the entrypoint script and make it executable.
# Note: entrypoint.sh is created in task 3.
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 8080

ENTRYPOINT ["/entrypoint.sh"]

# ── Demo target ───────────────────────────────────────────────────────────────
# Build with: docker build --target demo -t bitnet-openai-proxy:demo .
#
# Downloads the default BitNet GGUF model at image build time so the container
# can be started with no environment variables for quick evaluation.
#
# Default model: microsoft/bitnet-b1.58-2B-4T-gguf / ggml-model-i2_s.gguf
# Override at build time with:
#   --build-arg DEMO_MODEL_REPO=<hf-repo-id>
#   --build-arg DEMO_MODEL_FILE=<filename.gguf>
FROM runtime AS demo

ARG DEMO_MODEL_REPO=microsoft/bitnet-b1.58-2B-4T-gguf
ARG DEMO_MODEL_FILE=ggml-model-i2_s.gguf

# Download the model into /models at build time.
RUN hf download "$DEMO_MODEL_REPO" "$DEMO_MODEL_FILE" \
        --local-dir /models

# Set MODEL_PATH so the entrypoint uses the bundled model without any user-supplied env vars.
ENV MODEL_PATH=/models/${DEMO_MODEL_FILE}
