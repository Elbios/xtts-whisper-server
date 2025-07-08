# docker-entrypoint.sh
#!/usr/bin/env bash
set -euo pipefail

# Ensure model directory exists
mkdir -p "${WHISPER_MODELS_DIR}"

MODEL_FILE="${WHISPER_MODELS_DIR}/ggml-${WHISPER_MODEL}.bin"

# Download the model if it is not already present
if [[ ! -f "${MODEL_FILE}" ]]; then
  echo "Downloading Whisper model: ${WHISPER_MODEL}"
  /opt/whispercpp/download-ggml-model.sh "${WHISPER_MODEL}" "${WHISPER_MODELS_DIR}"
fi

# Provide legacy path expected by some code
ln -sfn "${WHISPER_MODELS_DIR}" /app/models

# Start servers
whisper-server --port 8080 &
exec python -m xtts_api_server --listen -p 8020 \
     -lsf 'latent_speaker_folder' -o 'output' \
     -mf 'xtts_models' -d 'cuda' --deepspeed
