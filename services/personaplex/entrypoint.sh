#!/bin/bash
set -ex

echo "=== PersonaPlex Starting ==="
echo "Timestamp: $(date -u +"%Y-%m-%d %H:%M:%S UTC")"

if [ -z "$HF_TOKEN" ]; then
    echo "ERROR: HF_TOKEN not set"
    exit 1
fi
echo "✓ HF_TOKEN configured"

echo "Checking moshi module..."
if ! python3 -c "import moshi; print(f'Moshi version: {moshi.__version__ if hasattr(moshi, \"__version__\") else \"unknown\"}')" 2>&1; then
    echo "ERROR: moshi module not found or failed to import"
    exit 1
fi
echo "✓ Moshi module available"

if command -v nvidia-smi &> /dev/null; then
    echo "GPU Info:"
    nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader
else
    echo "WARNING: nvidia-smi not available"
fi

echo "Python version: $(python3 --version)"
echo "Python path: $(which python3)"
echo "Pip packages:"
python3 -m pip list | grep -E "(moshi|torch|accelerate)" || echo "No matching packages"

echo ""
echo "=== Starting Moshi Server ==="
echo "Command: python3 server.py"
echo "CPU_OFFLOAD: ${CPU_OFFLOAD:-false}"
echo ""

exec python3 server.py
