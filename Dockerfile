# syntax=docker/dockerfile:1

FROM pytorch/pytorch:2.7.0-cuda12.8-cudnn9-runtime AS base
LABEL description="XTTS API server + Whisper.cpp (CUDA) slim"

ARG DEBIAN_FRONTEND=noninteractive
ARG WCPP_VER=v1.7.6
ARG WCPP_ZIP=whisper-cublas-12.4.0-bin-x64.zip

# ---- OS packages (single layer, cleaned) ----
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ffmpeg libportaudio2 libasound2 wget unzip ca-certificates && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# ---- Python deps ----
WORKDIR /app
COPY requirements.txt .
RUN python -m pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir -r requirements.txt && \
    pip cache purge          # extra safety

# ---- App code & speakers ----
COPY latent_speaker_folder ./latent_speaker_folder
COPY xtts_models            ./xtts_models       # keep or mount, see §5
COPY xtts_api_server        ./xtts_api_server

# ---- Whisper.cpp CUDA binary (~443 MB) ----
RUN wget -q https://github.com/ggml-org/whisper.cpp/releases/download/${WCPP_VER}/${WCPP_ZIP} \
 && unzip -q ${WCPP_ZIP} -d /opt/whispercpp \
 && rm ${WCPP_ZIP} \
 && ln -s /opt/whispercpp/main /usr/local/bin/whisper   # easy cli access

ENV HF_HOME=/root/.cache/huggingface \
    PATH="/opt/whispercpp:${PATH}"

EXPOSE 8020
CMD ["python", "-m", "xtts_api_server", "--listen", "-p", "8020", "--deepspeed"]
