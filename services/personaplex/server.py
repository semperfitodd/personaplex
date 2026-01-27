import os
import subprocess
import tempfile

ssl_dir = tempfile.mkdtemp()
cmd = ['python3', '-m', 'moshi.server', '--ssl', ssl_dir, '--host', '0.0.0.0']

if os.environ.get('CPU_OFFLOAD', 'false').lower() == 'true':
    cmd.append('--cpu-offload')

subprocess.run(cmd)
