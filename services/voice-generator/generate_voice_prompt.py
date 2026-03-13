"""Generate a .pt voice prompt embedding from a directory of WAV files."""

import os
import shutil
import sys
import tempfile
from pathlib import Path

sys.stdout.reconfigure(line_buffering=True)

import torch
from huggingface_hub import hf_hub_download

HF_REPO = os.environ.get("HF_REPO", "nvidia/personaplex-7b-v1")
HF_TOKEN = os.environ.get("HF_TOKEN")


def concatenate_wavs(wav_dir, target_sr=24000):
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


def generate_embedding(combined_wav_path, output_path):
    import sentencepiece
    from moshi.models import loaders, LMGen

    device = "cuda" if torch.cuda.is_available() else "cpu"
    print(f"Device: {device}")

    print("Downloading model weights...")
    mimi_weight = hf_hub_download(HF_REPO, loaders.MIMI_NAME, token=HF_TOKEN)
    moshi_weight = hf_hub_download(HF_REPO, loaders.MOSHI_NAME, token=HF_TOKEN)
    tokenizer_path = hf_hub_download(HF_REPO, loaders.TEXT_TOKENIZER_NAME, token=HF_TOKEN)

    print("Loading Mimi codec...")
    mimi = loaders.get_mimi(mimi_weight, device)

    print("Loading Moshi LM...")
    lm = loaders.get_moshi_lm(moshi_weight, device=device)
    lm.eval()

    text_tokenizer = sentencepiece.SentencePieceProcessor(tokenizer_path)
    text_prompt = os.environ.get("TEXT_PROMPT", "You enjoy having a good conversation.")
    text_prompt_tokens = text_tokenizer.encode(f"<system> {text_prompt} <system>")

    frame_size = int(mimi.sample_rate / mimi.frame_rate)
    lm_gen = LMGen(
        lm,
        audio_silence_frame_cnt=int(0.5 * mimi.frame_rate),
        sample_rate=mimi.sample_rate,
        device=device,
        frame_rate=mimi.frame_rate,
        save_voice_prompt_embeddings=True,
        text_prompt_tokens=text_prompt_tokens,
    )

    mimi.streaming_forever(1)
    lm_gen.streaming_forever(1)

    print("Warming up...")
    for _ in range(4):
        chunk = torch.zeros(1, 1, frame_size, dtype=torch.float32, device=device)
        codes = mimi.encode(chunk)
        for c in range(codes.shape[-1]):
            lm_gen.step(codes[:, :, c : c + 1])
    if torch.cuda.is_available():
        torch.cuda.synchronize()

    print(f"Loading voice prompt: {combined_wav_path}")
    lm_gen.load_voice_prompt(combined_wav_path)

    print("Processing voice prompt (generating embedding)...")
    mimi.reset_streaming()
    lm_gen.reset_streaming()
    lm_gen.step_system_prompts(mimi)

    auto_pt = Path(combined_wav_path).with_suffix(".pt")
    if auto_pt.exists():
        shutil.copy(str(auto_pt), output_path)
        size_mb = os.path.getsize(output_path) / 1024 / 1024
        print(f"Embedding saved: {output_path} ({size_mb:.1f} MB)")
        return True

    print("ERROR: .pt file was not generated")
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
        with torch.no_grad():
            if not generate_embedding(combined_path, output_path):
                sys.exit(1)
        print("\nDone.")
    finally:
        try:
            os.unlink(combined_path)
        except OSError:
            pass
        auto_pt = Path(combined_path).with_suffix(".pt")
        try:
            os.unlink(auto_pt)
        except OSError:
            pass


if __name__ == "__main__":
    main()
