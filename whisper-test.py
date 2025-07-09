#!/usr/bin/env python3
"""
Transcribe output.wav via the stock whisper.cpp HTTP server
listening on localhost:8080.
"""

import requests, sys, json

AUDIO_FILE = "output.wav"
API_URL    = "http://localhost:8080/inference"   # <-- key change

# Form-data payload recognised by whisper.cpp
payload = {
    "temperature": 0,
    "response_format": "json"        # "text", "srt", "verbose_json", ...
}

with open(AUDIO_FILE, "rb") as f:
    files = {
        "file": (AUDIO_FILE, f, "audio/wav")
    }
    r = requests.post(API_URL, files=files, data=payload, timeout=300)
    r.raise_for_status()

# Handle either JSON or plain-text replies
if r.headers.get("Content-Type", "").startswith("application/json"):
    print(r.json().get("text", r.json()))   # prints just the transcript
else:
    print(r.text)
