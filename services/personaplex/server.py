import atexit
import json
import os
import shutil
import signal
import subprocess
import sys
import tempfile
import threading
import time
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

sys.stdout.reconfigure(line_buffering=True)

MODELS_DIR = os.environ.get("MODELS_DIR", "/mnt/models")
VOICES_PORT = int(os.environ.get("VOICES_PORT", "8999"))
HF_REPO = os.environ.get("HF_REPO", "nvidia/personaplex-7b-v1")


def find_snapshot_voices_dir() -> Path | None:
    """Return the voices/ dir inside the latest HF model snapshot, or None if not downloaded yet."""
    hf_cache = Path.home() / ".cache" / "huggingface" / "hub"
    snapshots_dir = hf_cache / f"models--{HF_REPO.replace('/', '--')}" / "snapshots"
    if not snapshots_dir.exists():
        return None
    snapshots = sorted(snapshots_dir.glob("*"), reverse=True)
    if not snapshots:
        return None
    return snapshots[0] / "voices"


def link_custom_voices(voices_dir: Path) -> None:
    """Symlink custom voice files from MODELS_DIR into the model snapshot voices dir."""
    models_path = Path(MODELS_DIR)
    if not models_path.exists():
        return
    voices_dir.mkdir(exist_ok=True)
    for voice_file in list(models_path.glob("*.wav")) + list(models_path.glob("*.pt")):
        target = voices_dir / voice_file.name
        if not target.exists():
            try:
                target.symlink_to(voice_file)
                print(f"Linked custom voice: {voice_file.name}", flush=True)
            except Exception as exc:
                print(f"WARN: could not link {voice_file.name}: {exc}", flush=True)


def voice_linker_loop() -> None:
    """Poll until the HF snapshot voices dir appears, then keep custom voices linked."""
    while True:
        try:
            voices_dir = find_snapshot_voices_dir()
            if voices_dir is not None:
                link_custom_voices(voices_dir)
        except Exception as exc:
            print(f"WARN: voice linker error: {exc}", flush=True)
        time.sleep(30)


def list_voices() -> list[str]:
    voices_dir = find_snapshot_voices_dir()
    if voices_dir and voices_dir.exists():
        files = list(voices_dir.glob("*.pt")) + list(voices_dir.glob("*.wav"))
        return sorted(f.name for f in files)
    print("WARN: model voices directory not yet available", flush=True)
    return []


class VoicesHandler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        pass

    def do_GET(self):
        if self.path == "/api/voices":
            try:
                voices = list_voices()
            except Exception as exc:
                print(f"WARN: list_voices failed: {exc}", flush=True)
                voices = []
            body = json.dumps(voices).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Access-Control-Allow-Origin", "*")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        else:
            self.send_response(404)
            self.end_headers()


def main() -> None:
    ssl_dir = tempfile.mkdtemp()
    atexit.register(shutil.rmtree, ssl_dir, ignore_errors=True)

    moshi_args = ["-m", "moshi.server", "--ssl", ssl_dir, "--host", "0.0.0.0", "--port", "8998"]

    if os.environ.get("CPU_OFFLOAD", "false").lower() == "true":
        moshi_args.append("--cpu-offload")

    if HF_REPO:
        moshi_args.extend(["--hf-repo", HF_REPO])

    moshi_proc = subprocess.Popen(["python3"] + moshi_args)

    threading.Thread(target=voice_linker_loop, daemon=True).start()

    def _shutdown(signum, frame):
        moshi_proc.terminate()
        sys.exit(0)

    signal.signal(signal.SIGTERM, _shutdown)
    signal.signal(signal.SIGINT, _shutdown)

    try:
        server = HTTPServer(("0.0.0.0", VOICES_PORT), VoicesHandler)
        print(f"Voices API listening on :{VOICES_PORT}", flush=True)
        server.serve_forever()
    except Exception as exc:
        print(f"ERROR: voices server failed to start: {exc}", flush=True)
        moshi_proc.terminate()
        sys.exit(1)


if __name__ == "__main__":
    main()
