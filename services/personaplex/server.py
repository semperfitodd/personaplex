import os
import tempfile

ssl_dir = tempfile.mkdtemp()
args = ["-m", "moshi.server", "--ssl", ssl_dir, "--host", "0.0.0.0", "--port", "8998"]

if os.environ.get("CPU_OFFLOAD", "false").lower() == "true":
    args.append("--cpu-offload")

if os.environ.get("USE_FLOAT16", "false").lower() == "true":
    args.append("--half")

hf_repo = os.environ.get("HF_REPO", "")
if hf_repo:
    args.extend(["--hf-repo", hf_repo])

os.execvp("python3", ["python3"] + args)
