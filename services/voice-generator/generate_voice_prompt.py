"""Generate a .pt voice prompt embedding from a directory of WAV files."""

import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HF_REPO = os.environ.get("HF_REPO", "nvidia/personaplex-7b-v1")


def concatenate_wavs(wav_dir, target_sr=24000):
    import torch
    import torchaudio

    wav_dir = Path(wav_dir)
    wav_files = sorted(wav_dir.glob("*.wav"))
    if not wav_files:
        print(f"ERROR: No WAV files found in {wav_dir}")
        sys.exit(1)

    print(f"Found {len(wav_files)} WAV files in {wav_dir}")

    segments = []
    silence = torch.zeros(1, int(target_sr * 0.3))

    for wav_path in wav_files:
        wav, sr = torchaudio.load(str(wav_path))
        if sr != target_sr:
            wav = torchaudio.functional.resample(wav, sr, target_sr)
        if wav.shape[0] > 1:
            wav = wav.mean(dim=0, keepdim=True)
        segments.append(wav)
        segments.append(silence)
        print(f"  Loaded {wav_path.name}: {wav.shape[-1] / target_sr:.1f}s")

    combined = torch.cat(segments, dim=-1)
    duration = combined.shape[-1] / target_sr
    print(f"Combined audio: {duration:.1f}s ({combined.shape[-1]} samples at {target_sr}Hz)")

    combined_path = tempfile.mktemp(suffix=".wav")
    torchaudio.save(combined_path, combined, target_sr)
    return combined_path


def discover_voice_dir():
    try:
        from huggingface_hub import snapshot_download

        model_dir = snapshot_download(
            HF_REPO,
            allow_patterns=["voice_prompts/*"],
            token=os.environ.get("HF_TOKEN"),
        )
        vdir = Path(model_dir) / "voice_prompts"
        if vdir.exists():
            print(f"Voice prompts directory: {vdir}")
            return vdir
    except Exception as e:
        print(f"Could not find voice_prompts dir: {e}")
    return None


def generate_via_offline(combined_wav_path, output_path):
    import torch
    import torchaudio

    dummy_input = tempfile.mktemp(suffix=".wav")
    dummy_output = tempfile.mktemp(suffix=".wav")

    try:
        silence = torch.zeros(1, 24000 * 2)
        torchaudio.save(dummy_input, silence, 24000)

        voice_dir = discover_voice_dir()
        if not voice_dir:
            print("ERROR: Cannot find voice_prompts directory")
            return False

        wav_name = Path(combined_wav_path).stem
        symlink_path = voice_dir / Path(combined_wav_path).name
        if not symlink_path.exists():
            symlink_path.symlink_to(combined_wav_path)

        cmd = [
            sys.executable, "-m", "moshi.offline",
            "--voice-prompt", Path(combined_wav_path).name,
            "--input-wav", dummy_input,
            "--output-wav", dummy_output,
            "--text-prompt", "You enjoy having a good conversation.",
        ]

        print(f"Running: {' '.join(cmd)}")
        subprocess.run(cmd, capture_output=False)

        pt_candidate = voice_dir / f"{wav_name}.pt"
        if pt_candidate.exists():
            shutil.copy2(pt_candidate, output_path)
            size_mb = os.path.getsize(output_path) / 1024 / 1024
            print(f"Embedding saved: {output_path} ({size_mb:.1f} MB)")
            return True

        return False
    finally:
        for p in [dummy_input, dummy_output]:
            try:
                os.unlink(p)
            except OSError:
                pass


def generate_direct(combined_wav_path, output_path):
    import torch

    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    dtype = torch.bfloat16 if device.type == "cuda" else torch.float32
    print(f"Device: {device}, dtype: {dtype}")

    from moshi.models.loaders import CheckpointInfo

    print(f"Loading model from {HF_REPO}...")
    info = CheckpointInfo.from_hf_repo(HF_REPO, token=os.environ.get("HF_TOKEN"))

    print("Loading Mimi codec...")
    mimi = info.get_mimi(device=device, dtype=dtype)
    mimi.set_num_codebooks(8)

    print("Loading Moshi LM...")
    lm = info.get_moshi(device=device, dtype=dtype)

    from moshi.models.lm import LMGen

    lm_gen = LMGen(lm, mimi=mimi, device=device, dtype=dtype)
    print(f"Processing voice prompt: {combined_wav_path}")

    if hasattr(lm_gen, "load_voice_prompt"):
        lm_gen.load_voice_prompt(combined_wav_path)
    else:
        print("ERROR: load_voice_prompt not found on LMGen")
        return False

    for method_name in ["_step_voice_prompt", "step_voice_prompt", "step_system_prompts"]:
        if hasattr(lm_gen, method_name):
            print(f"Calling {method_name}()...")
            getattr(lm_gen, method_name)()
            break

    for save_method in ["save_voice_prompt_embeddings_to", "save_voice_prompt_embeddings"]:
        if hasattr(lm_gen, save_method):
            print(f"Calling {save_method}({output_path})...")
            getattr(lm_gen, save_method)(output_path)
            size_mb = os.path.getsize(output_path) / 1024 / 1024
            print(f"Saved: {output_path} ({size_mb:.1f} MB)")
            return True

    auto_pt = Path(combined_wav_path).with_suffix(".pt")
    if auto_pt.exists():
        shutil.copy2(auto_pt, output_path)
        print(f"Found auto-saved embedding: {output_path}")
        return True

    print("ERROR: Could not save embeddings")
    return False


def main():
    wav_dir = Path(os.environ.get("WAV_DIR", "/mnt/input/wavs"))
    output_path = os.environ.get("OUTPUT_PATH", "/mnt/output/todd_voice.pt")

    if not wav_dir.is_dir():
        print(f"ERROR: Not a directory: {wav_dir}")
        sys.exit(1)

    print(f"Input dir: {wav_dir}")
    print(f"Output:    {output_path}\n")

    combined_path = concatenate_wavs(wav_dir)
    print(f"Saved combined WAV to temp: {combined_path}\n")

    try:
        print("--- Trying direct generation ---")
        if generate_direct(combined_path, output_path):
            print("\nDone.")
            return
        print("\n--- Falling back to offline method ---")
        if generate_via_offline(combined_path, output_path):
            print("\nDone.")
            return
        print("\nERROR: Failed to generate voice prompt embedding.")
        sys.exit(1)
    finally:
        try:
            os.unlink(combined_path)
        except OSError:
            pass


if __name__ == "__main__":
    main()
