#!/usr/bin/env bash
set -eo pipefail

# Start Whisper.cpp HTTP server (OAI-style API) on 8080
whisper-server --port 8080

# Start XTTS REST server on 8020
#exec python -m xtts_api_server --listen -p 8020 -lsf 'latent_speaker_folder' -o 'output' -mf 'xtts_models' -d 'cuda' --deepspeed
