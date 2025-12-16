import base64
import os
import subprocess
import tempfile

import numpy as np
import torch
import torchaudio
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from speechbrain.inference import SpeakerRecognition

# -------------------------
# Configuration
# -------------------------

MODEL_SOURCE = "speechbrain/spkrec-ecapa-voxceleb"
MODEL_DIR = "models/spkrec"

EXPECTED_SR = 16000
MODEL_SR = 16000
MIN_SECONDS = 2.0

# -------------------------
# Load model once
# -------------------------

try:
    print("DEBUG: Loading SpeechBrain model")
    from speechbrain.utils.fetching import LocalStrategy

    spkrec = SpeakerRecognition.from_hparams(
        source=MODEL_SOURCE,
        savedir=MODEL_DIR,
        run_opts={"device": "cpu"},
        local_strategy=LocalStrategy.NO_LINK,
    )
    print("DEBUG: SpeechBrain model loaded successfully")
except Exception as e:
    print(f"DEBUG: Failed to load SpeechBrain model: {e}")
    exit(1)

resampler = torchaudio.transforms.Resample(orig_freq=EXPECTED_SR, new_freq=MODEL_SR)

# -------------------------
# Utilities
# -------------------------


def pcm16_to_waveform(pcm_bytes: bytes) -> torch.Tensor:
    samples = np.frombuffer(pcm_bytes, dtype=np.int16)
    if samples.size == 0:
        raise ValueError("Empty audio buffer")

    waveform = samples.astype(np.float32) / 32768.0
    waveform = torch.from_numpy(waveform).unsqueeze(0)
    return waveform


def extract_embedding(pcm_bytes: bytes) -> np.ndarray:
    waveform = pcm16_to_waveform(pcm_bytes)
    if EXPECTED_SR != MODEL_SR:
        waveform = resampler(waveform)

    min_samples = int(MIN_SECONDS * MODEL_SR)
    if waveform.shape[1] < min_samples:
        raise ValueError("Audio too short")

    with torch.no_grad():
        emb = spkrec.encode_batch(waveform)

    emb = emb.squeeze(0).cpu().numpy()
    emb /= np.linalg.norm(emb)
    return emb.astype(np.float32)


def serialize_embedding(emb: np.ndarray) -> str:
    return base64.b64encode(emb.tobytes()).decode("ascii")


def deserialize_embedding(data: str) -> np.ndarray:
    try:
        raw = base64.b64decode(data)
        print(f"DEBUG: Decoded {len(raw)} bytes from base64")
        emb = np.frombuffer(raw, dtype=np.float32).copy()  # Make a writable copy
        print(f"DEBUG: Created array with shape {emb.shape}")
        norm = np.linalg.norm(emb)
        print(f"DEBUG: Norm is {norm}")
        if norm > 0:
            emb /= norm
        else:
            print("DEBUG: Warning - norm is zero or negative")
        return emb
    except Exception as e:
        print(f"DEBUG: Error in deserialize_embedding: {e}")
        raise


def cosine_similarity(a: np.ndarray, b: np.ndarray) -> float:
    return float(np.dot(a, b))


# -------------------------
# API models
# -------------------------


class EmbedRequest(BaseModel):
    pcm_base64: str


class EmbedResponse(BaseModel):
    embedding: str


class VerifyRequest(BaseModel):
    pcm_base64: str
    candidates: list[str]


class VerifyResponse(BaseModel):
    best_index: int
    score: float


# -------------------------
# FastAPI app
# -------------------------

app = FastAPI()


@app.post("/embed", response_model=EmbedResponse)
def embed(req: EmbedRequest):
    try:
        pcm = base64.b64decode(req.pcm_base64)
        emb = extract_embedding(pcm)
        return EmbedResponse(embedding=serialize_embedding(emb))
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))


@app.post("/verify", response_model=VerifyResponse)
def verify(req: VerifyRequest):
    try:
        print(f"DEBUG: Verify request with {len(req.candidates)} candidates")
        pcm = base64.b64decode(req.pcm_base64)
        print(f"DEBUG: Decoded {len(pcm)} bytes of audio data")

        if os.getenv("DEBUG_PLAY_AUDIO"):
            print("DEBUG: Playing audio sample")
            with tempfile.NamedTemporaryFile(suffix=".pcm", delete=False) as f:
                f.write(pcm)
                temp_file = f.name
            try:
                subprocess.run(
                    [
                        "mpv",
                        "--no-config",
                        "--demuxer=rawaudio",
                        "--demuxer-rawaudio-format=s16le",
                        "--demuxer-rawaudio-channels=1",
                        "--demuxer-rawaudio-rate=16000",
                        temp_file,
                    ],
                    check=True,
                )
            except subprocess.CalledProcessError as e:
                print(f"DEBUG: Failed to play audio: {e}")
            finally:
                os.unlink(temp_file)

        test_emb = extract_embedding(pcm)
        print(f"DEBUG: Extracted test embedding with shape {test_emb.shape}")

        best_score = -1.0
        best_idx = -1

        for i, cand in enumerate(req.candidates):
            print(f"DEBUG: Processing candidate {i}")
            emb = deserialize_embedding(cand)
            print(f"DEBUG: Deserialized candidate embedding with shape {emb.shape}")
            score = cosine_similarity(test_emb, emb)
            print(f"DEBUG: Cosine similarity score: {score}")
            if score > best_score:
                best_score = score
                best_idx = i

        print(f"DEBUG: Best score: {best_score}, best index: {best_idx}")
        return VerifyResponse(best_index=best_idx, score=best_score)
    except Exception as e:
        print(f"DEBUG: Error in verify: {e}")
        raise HTTPException(status_code=400, detail=str(e))
