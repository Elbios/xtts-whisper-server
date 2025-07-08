# ----------------- 1) build Whisper.cpp with CUDA -----------------
FROM pytorch/pytorch:2.7.0-cuda12.8-cudnn9-devel AS whisper-build

ARG WCPP_VER=v1.7.6
WORKDIR /opt

RUN apt-get update && \
    apt-get install -y --no-install-recommends git cmake build-essential && \
    rm -rf /var/lib/apt/lists/*

RUN git clone --depth 1 --branch ${WCPP_VER} https://github.com/ggml-org/whisper.cpp.git
WORKDIR /opt/whisper.cpp
RUN cmake -B build -DGGML_CUDA=1 -DCMAKE_BUILD_TYPE=Release \
 && cmake --build build -j $(nproc) --config Release

# ----------------- 2) final runtime image -----------------
FROM pytorch/pytorch:2.7.0-cuda12.8-cudnn9-runtime

LABEL description="XTTS + Whisper.cpp CUDA server"

# Minimal OS libs (keep portaudio19-dev as requested)
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ffmpeg gcc portaudio19-dev libasound2 ca-certificates && \
    rm -rf /var/lib/apt/lists/*

# ---------- Python deps ----------
WORKDIR /app
COPY requirements.txt .
RUN python -m pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir -r requirements.txt && \
    pip cache purge

# ---------- App assets ----------
COPY latent_speaker_folder ./latent_speaker_folder
COPY xtts_models ./xtts_models
COPY xtts-api-server ./xtts-api-server

WORKDIR /app/xtts-api-server
RUN pip install .
WORKDIR /app

ENV LD_LIBRARY_PATH=/opt/conda/lib/python3.11/site-packages/nvidia/cuda_runtime/lib:/opt/conda/lib/python3.11/site-packages/nvidia/cublas/lib:$LD_LIBRARY_PATH

# ---------- Whisper binaries ----------
COPY --from=whisper-build /opt/whisper.cpp/build/bin /opt/whispercpp
COPY --from=whisper-build /opt/whisper.cpp/build/src/libwhisper.so* /usr/local/lib/
COPY --from=whisper-build /opt/whisper.cpp/build/ggml/src/libggml* /usr/local/lib/
COPY --from=whisper-build /opt/whisper.cpp/build/ggml/src/ggml-cuda/libggml-cuda.so /usr/local/lib/
# downloader script
COPY --from=whisper-build /opt/whisper.cpp/models/download-ggml-model.sh /opt/whispercpp/
RUN chmod +x /opt/whispercpp/download-ggml-model.sh && ldconfig

RUN ln -s /opt/whispercpp/whisper-server /usr/local/bin/whisper-server && \
    ln -s /opt/whispercpp/whisper-cli    /usr/local/bin/whisper

# ---------- startup script ----------
COPY docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# ---------- Whisper model settings ----------
ENV WHISPER_MODEL=large-v3-turbo \
    WHISPER_MODELS_DIR=/opt/whispercpp/models

EXPOSE 8020 8080
ENTRYPOINT ["docker-entrypoint.sh"]
