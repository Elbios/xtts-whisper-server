#!/usr/bin/env bash
set -euo pipefail

# Prep models
mkdir -p "${WHISPER_MODELS_DIR}"
MODEL_FILE="${WHISPER_MODELS_DIR}/ggml-${WHISPER_MODEL}.bin"
if [[ ! -f "${MODEL_FILE}" ]]; then
  echo "Downloading Whisper model: ${WHISPER_MODEL}"
  /opt/whispercpp/download-ggml-model.sh "${WHISPER_MODEL}" "${WHISPER_MODELS_DIR}"
fi

# Log file that both servers will append to
LOG=/var/log/inference.log
touch "$LOG"

# Start the servers, teeing stdout+stderr to $LOG
whisper-server --host 0.0.0.0 --port 8080 --model "${MODEL_FILE}" \
  2>&1 | tee -a "$LOG" &
WHISPER_PID=$!

python -m xtts_api_server --listen -p 8020 \
        -lsf '/app/latent_speaker_folder' -o '/app/output' \
        -mf '/app/xtts_models' -d 'cuda' --deepspeed \
  2>&1 | tee -a "$LOG" &
XTTS_PID=$!

# Background watchdog: stop instance if $LOG silent > MAX_IDLE
(
  MAX_IDLE=${MAX_IDLE_SECONDS:-1800}   # default to 30 min if unset
  while true; do
      last_change=$(stat -c %Y "$LOG")
      now=$(date +%s)
      idle=$(( now - last_change ))
      if (( idle > MAX_IDLE )); then
          mins=$(( idle / 60 ))
          secs=$(( idle % 60 ))
          printf "[watchdog] No log activity for %dm%02ds - stopping instance\n" "$mins" "$secs"
          vastai --api-key "$CONTAINER_API_KEY" stop instance "$CONTAINER_ID"
      fi
      sleep 60
  done
) &

# Wait so container keeps running until servers exit manually
wait $WHISPER_PID $XTTS_PID