import os
import subprocess
import tempfile
from pathlib import Path

hf_token = os.environ.get('HF_TOKEN', '')
if hf_token:
    os.environ['HF_TOKEN'] = hf_token

ssl_dir = tempfile.mkdtemp()

cmd = ['python', '-m', 'moshi.server', '--ssl', ssl_dir, '--host', '0.0.0.0']

cpu_offload = os.environ.get('CPU_OFFLOAD', 'false').lower() == 'true'
if cpu_offload:
    cmd.append('--cpu-offload')

subprocess.run(cmd)
