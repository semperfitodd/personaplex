"""Generate a combined voice prompt WAV from a directory of input WAV files and upload to S3.

Resamples all inputs to 24 kHz mono, concatenates them with 300ms silence between clips,
and saves the result as a WAV file. The output is loaded by moshi.server via
load_voice_prompt() (audio path), not load_voice_prompt_embeddings() (LM state path).
No GPU required.
"""

import os
import sys
import tempfile
from datetime import datetime, timezone
from math import gcd
from pathlib import Path

import boto3
import numpy as np
import soundfile as sf
from scipy.signal import resample_poly

sys.stdout.reconfigure(line_buffering=True)

TARGET_SR = 24000


def load_wav(wav_path: Path, target_sr: int = TARGET_SR) -> np.ndarray:
    data, sr = sf.read(str(wav_path), dtype="float32", always_2d=True)
    data = data.mean(axis=1)
    if sr != target_sr:
        g = gcd(sr, target_sr)
        data = resample_poly(data, target_sr // g, sr // g).astype(np.float32)
    return data


def concatenate_wavs(wav_dir: Path, target_sr: int = TARGET_SR) -> np.ndarray:
    wav_files = sorted(wav_dir.glob("*.wav"))
    if not wav_files:
        print(f"ERROR: No WAV files found in {wav_dir}")
        sys.exit(1)

    print(f"Found {len(wav_files)} WAV file(s) in {wav_dir}")

    segments: list[np.ndarray] = []
    silence = np.zeros(int(target_sr * 0.3), dtype=np.float32)

    for wav_path in wav_files:
        data = load_wav(wav_path, target_sr)
        segments.append(data)
        segments.append(silence)
        print(f"  {wav_path.name}: {len(data) / target_sr:.1f}s")

    combined = np.concatenate(segments)
    print(f"Combined: {len(combined) / target_sr:.1f}s  ({len(combined)} samples @ {target_sr} Hz)")
    return combined


def upload_to_s3(local_path: str, bucket: str, key: str) -> None:
    size_mb = os.path.getsize(local_path) / 1024 / 1024
    print(f"Uploading to s3://{bucket}/{key}  ({size_mb:.1f} MB)...")
    region = os.environ.get("AWS_REGION", "us-east-1")
    boto3.client("s3", region_name=region).upload_file(local_path, bucket, key)
    print("Upload complete.")


def main() -> None:
    wav_dir = Path(os.environ.get("WAV_DIR", "/mnt/input/wavs"))
    output_stem = os.environ.get("OUTPUT_PATH", "voice_prompt.wav")
    s3_bucket = os.environ.get("S3_OUTPUT_BUCKET", "")

    timestamp = datetime.now(timezone.utc).strftime("%Y%m%d%H%M%S")
    stem = Path(output_stem).stem
    output_key = f"{stem}_{timestamp}.wav"

    if not wav_dir.is_dir():
        print(f"ERROR: Not a directory: {wav_dir}")
        sys.exit(1)

    print(f"Input:  {wav_dir}")
    print(f"Output: {output_key}\n")

    audio = concatenate_wavs(wav_dir)

    with tempfile.TemporaryDirectory() as tmp_dir:
        tmp_wav = os.path.join(tmp_dir, output_key)
        sf.write(tmp_wav, audio, TARGET_SR, subtype="PCM_16")
        size_mb = os.path.getsize(tmp_wav) / 1024 / 1024
        print(f"WAV saved: {audio.shape}  ({size_mb:.1f} MB)")

        if s3_bucket:
            upload_to_s3(tmp_wav, s3_bucket, output_key)
        else:
            import shutil
            shutil.copy(tmp_wav, output_key)
            print(f"Saved locally: {output_key}")

    print(f"\nDone: {output_key}")


if __name__ == "__main__":
    main()
