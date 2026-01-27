#!/bin/bash
set -e

if [ -z "$HF_TOKEN" ]; then
    echo "ERROR: HF_TOKEN not set"
    exit 1
fi

if ! python3 -c "import moshi" 2>/dev/null; then
    echo "ERROR: moshi module not found"
    exit 1
fi

if command -v nvidia-smi &> /dev/null; then
    nvidia-smi --query-gpu=name,memory.total --format=csv,noheader
fi

exec python3 server.py
