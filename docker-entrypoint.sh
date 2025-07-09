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

# Background watchdog: stop instance if $LOG silent > 30 min
(
  MAX_IDLE=${MAX_IDLE_SECONDS:-1800}   # fall back to 30 min if env var not set
  while true; do
      last_change=$(stat -c %Y "$LOG")     # epoch-seconds mtime
      now=$(date +%s)
      if (( now - last_change > MAX_IDLE )); then
          echo "[watchdog] No log activity for 30 min - destroying instance"
          vastai --api-key "$(cat /root/.vast_api_key)" \
                 stop instance "$VAST_CONTAINERLABEL"
          # container disappears in ~2 s, so nothing after this matters
      fi
      sleep 60
  done
) &

# Wait so container keeps running until servers exit manually
wait $WHISPER_PID $XTTS_PID