import os
import sys
import tempfile

print("=== Server.py Starting ===", flush=True)
print(f"Python: {sys.version}", flush=True)
print(f"Working directory: {os.getcwd()}", flush=True)

ssl_dir = tempfile.mkdtemp()
print(f"SSL directory: {ssl_dir}", flush=True)

args = ['-m', 'moshi.server', '--ssl', ssl_dir, '--host', '0.0.0.0']

cpu_offload = os.environ.get('CPU_OFFLOAD', 'false').lower() == 'true'
if cpu_offload:
    args.append('--cpu-offload')
    print("CPU offload: ENABLED", flush=True)
else:
    print("CPU offload: DISABLED", flush=True)

print(f"Executing: python3 {' '.join(args)}", flush=True)
print("", flush=True)

os.execvp('python3', ['python3'] + args)
