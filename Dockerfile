# ------------------------------------------------------------------
# Stage 1: Build Whisper.cpp and DeepSpeed wheel
# ------------------------------------------------------------------
FROM pytorch/pytorch:2.7.0-cuda12.8-cudnn9-devel AS whisper-build

# Set the version of Whisper.cpp to build
ARG WCPP_VER=v1.7.6
WORKDIR /opt

# Install build dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends git cmake build-essential && \
    rm -rf /var/lib/apt/lists/*

# Clone and build Whisper.cpp with CUDA support
RUN git clone --depth 1 --branch ${WCPP_VER} https://github.com/ggml-org/whisper.cpp.git
WORKDIR /opt/whisper.cpp
RUN cmake -B build -DGGML_CUDA=1 -DCMAKE_BUILD_TYPE=Release \
 && cmake --build build -j $(nproc) --config Release

# Build the DeepSpeed wheel for later installation
RUN python -m pip install --no-cache-dir --upgrade pip wheel \
 && pip wheel deepspeed==0.17.1 --wheel-dir /tmp/deepspeed-wheels

# ------------------------------------------------------------------
# Stage 2: Final runtime image
# ------------------------------------------------------------------
FROM pytorch/pytorch:2.7.0-cuda12.8-cudnn9-runtime

LABEL description="XTTS + Whisper.cpp CUDA server"

# 1. Install runtime OS libraries and a minimal build tool-chain for nvcc
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ffmpeg portaudio19-dev libasound2 \
        gcc g++ make \
        ca-certificates wget && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# 2. Copy nvcc, essential CUDA libraries, and headers from the build stage
# This is necessary for packages that compile CUDA extensions on-the-fly.
RUN mkdir -p /usr/local/cuda/lib64
COPY --from=whisper-build /usr/local/cuda/lib64/libcudart.so* /usr/local/cuda/lib64/
COPY --from=whisper-build /usr/local/cuda/lib64/libcurand.so* /usr/local/cuda/lib64/
COPY --from=whisper-build /usr/local/cuda/bin     /usr/local/cuda/bin
COPY --from=whisper-build /usr/local/cuda/include /usr/local/cuda/include
COPY --from=whisper-build /usr/local/cuda/nvvm    /usr/local/cuda/nvvm

# 3. Set environment variables for CUDA
ENV CUDA_HOME=/usr/local/cuda
ENV PATH="${CUDA_HOME}/bin:${PATH}"

# 4. Set up the application directory and install Python dependencies
WORKDIR /app
COPY requirements.txt .
RUN python -m pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir -r requirements.txt && \
    pip cache purge

# 5. Install the DeepSpeed wheel that was built in the first stage
COPY --from=whisper-build /tmp/deepspeed-wheels/deepspeed-0.17.1*.whl /tmp/
RUN pip install --no-cache-dir /tmp/deepspeed-0.17.1*.whl && rm /tmp/deepspeed-0.17.1*.whl

# 6. Copy application assets into the image
COPY xtts-api-server ./xtts-api-server

COPY latent_speaker_folder /app/latent_speaker_folder
COPY xtts_models /app/xtts_models
WORKDIR /app/xtts-api-server

# 7. Update the library path for CUDA components within the Python environment
ENV LD_LIBRARY_PATH=/opt/conda/lib/python3.11/site-packages/nvidia/cuda_runtime/lib:/opt/conda/lib/python3.11/site-packages/nvidia/cublas/lib:$LD_LIBRARY_PATH

# 8. Copy Whisper.cpp binaries and libraries from the build stage
COPY --from=whisper-build /opt/whisper.cpp/build/bin /opt/whispercpp
COPY --from=whisper-build /opt/whisper.cpp/build/src/libwhisper.so* /usr/local/lib/
COPY --from=whisper-build /opt/whisper.cpp/build/ggml/src/libggml* /usr/local/lib/
COPY --from=whisper-build /opt/whisper.cpp/build/ggml/src/ggml-cuda/libggml-cuda.so /usr/local/lib/
COPY --from=whisper-build /opt/whisper.cpp/models/download-ggml-model.sh /opt/whispercpp/

# 9. Make scripts executable and create symbolic links for easier access
RUN chmod +x /opt/whispercpp/download-ggml-model.sh && ldconfig
RUN ln -s /opt/whispercpp/whisper-server /usr/local/bin/whisper-server && \
    ln -s /opt/whispercpp/whisper-cli    /usr/local/bin/whisper

# 10. Copy and set up the startup script
COPY docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# 11. Configure Whisper model settings and expose ports
ENV WHISPER_MODEL=large-v3-turbo \
    WHISPER_MODELS_DIR=/opt/whispercpp/models

EXPOSE 8020 8080
ENTRYPOINT ["docker-entrypoint.sh"]