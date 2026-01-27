import os
import sys
import tempfile

ssl_dir = tempfile.mkdtemp()
args = ['-m', 'moshi.server', '--ssl', ssl_dir, '--host', '0.0.0.0']

if os.environ.get('CPU_OFFLOAD', 'false').lower() == 'true':
    args.append('--cpu-offload')

os.execvp('python3', ['python3'] + args)
