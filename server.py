#!/usr/bin/env python3
from __future__ import annotations

import asyncio
import io
import os
import re
import time
from contextlib import asynccontextmanager
from pathlib import Path
from typing import Optional

import numpy as np
import torch
import torchaudio
from fastapi import FastAPI, File, Form, UploadFile
from fastapi.responses import JSONResponse, StreamingResponse
from huggingface_hub import hf_hub_download
from pydub import AudioSegment
from pydantic import BaseModel

from irodori_tts.inference_runtime import (
    InferenceRuntime,
    RuntimeKey,
    SamplingRequest,
)

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
HF_CHECKPOINT_VOICEDESIGN = os.environ.get(
    "HF_CHECKPOINT_VOICEDESIGN", "Aratako/Irodori-TTS-500M-v2-VoiceDesign"
)
HF_CHECKPOINT_BASE = os.environ.get("HF_CHECKPOINT_BASE", "Aratako/Irodori-TTS-500M-v2")
MODEL_DEVICE = os.environ.get("MODEL_DEVICE", "cuda")
CODEC_DEVICE = os.environ.get("CODEC_DEVICE", "cuda")
MODEL_PRECISION = os.environ.get("MODEL_PRECISION", "bf16")
CODEC_PRECISION = os.environ.get("CODEC_PRECISION", "bf16")
NUM_STEPS = int(os.environ.get("NUM_STEPS", "40"))
CFG_SCALE_TEXT = float(os.environ.get("CFG_SCALE_TEXT", "3.0"))
CFG_SCALE_CAPTION = float(os.environ.get("CFG_SCALE_CAPTION", "4.0"))
CFG_SCALE_SPEAKER = float(os.environ.get("CFG_SCALE_SPEAKER", "5.0"))
FIXED_SECONDS = float(os.environ.get("FIXED_SECONDS", "30.0"))
MODEL_TTL = float(os.environ.get("MODEL_TTL", "300"))
MODEL_LOAD_TIMEOUT = float(os.environ.get("MODEL_LOAD_TIMEOUT", "300"))
VOICES_DIR = Path(os.environ.get("VOICES_DIR", "/voices"))

CODEC_REPO = "Aratako/Semantic-DACVAE-Japanese-32dim"

MODEL_VOICEDESIGN = "irodori-tts-500m-v2-voicedesign"
MODEL_BASE = "irodori-tts-500m-v2"
MODEL_CHECKPOINTS: dict[str, str] = {
    MODEL_VOICEDESIGN: HF_CHECKPOINT_VOICEDESIGN,
    MODEL_BASE: HF_CHECKPOINT_BASE,
}

CONTENT_TYPES: dict[str, str] = {
    "mp3": "audio/mpeg",
    "wav": "audio/wav",
    "opus": "audio/ogg; codecs=opus",
    "flac": "audio/flac",
    "aac": "audio/aac",
}
VOICE_UPLOAD_EXTS = {".wav", ".mp3", ".flac", ".ogg"}
_VOICE_ID_RE = re.compile(r"^[\w\-]+$")


# ---------------------------------------------------------------------------
# Checkpoint helper  (ported from gradio_app_voicedesign.py)
# ---------------------------------------------------------------------------
def _resolve_checkpoint(repo_or_path: str) -> str:
    raw = repo_or_path.strip()
    if Path(raw).suffix.lower() in {".pt", ".safetensors"}:
        return raw
    resolved = hf_hub_download(repo_id=raw, filename="model.safetensors")
    print(f"[server] checkpoint: hf://{raw} -> {resolved}", flush=True)
    return resolved


def _build_runtime_key(model_id: str) -> RuntimeKey:
    return RuntimeKey(
        checkpoint=_resolve_checkpoint(MODEL_CHECKPOINTS[model_id]),
        model_device=MODEL_DEVICE,
        codec_repo=CODEC_REPO,
        model_precision=MODEL_PRECISION,
        codec_device=CODEC_DEVICE,
        codec_precision=CODEC_PRECISION,
        enable_watermark=False,
        compile_model=False,
        compile_dynamic=False,
    )


# ---------------------------------------------------------------------------
# TTL-based dynamic model cache
# ---------------------------------------------------------------------------
_runtime: InferenceRuntime | None = None
_runtime_model_id: str | None = None
_last_used: float = 0.0
_evict_task: asyncio.Task | None = None
_lock = asyncio.Lock()


def _reset_evict_timer() -> None:
    global _evict_task
    if _evict_task and not _evict_task.done():
        _evict_task.cancel()
    _evict_task = asyncio.create_task(_evict_after_ttl())


async def _evict_after_ttl() -> None:
    global _runtime, _runtime_model_id
    await asyncio.sleep(MODEL_TTL)
    async with _lock:
        if _runtime is not None and time.monotonic() - _last_used >= MODEL_TTL:
            print(f"[server] TTL expired: unloading {_runtime_model_id}", flush=True)
            loop = asyncio.get_running_loop()
            await loop.run_in_executor(None, _runtime.unload)
            _runtime = None
            _runtime_model_id = None


async def acquire_runtime(model_id: str) -> InferenceRuntime:
    """Return a loaded InferenceRuntime for the given model_id.

    Waits up to MODEL_LOAD_TIMEOUT seconds for the lock; raises 503 on timeout.
    """
    global _runtime, _runtime_model_id, _last_used

    try:
        await asyncio.wait_for(_lock.acquire(), timeout=MODEL_LOAD_TIMEOUT)
    except asyncio.TimeoutError:
        raise _ServiceUnavailable("Model is loading. Please retry later.")

    try:
        if _runtime is not None and _runtime_model_id == model_id:
            _last_used = time.monotonic()
            _reset_evict_timer()
            return _runtime

        # Unload existing model if different
        if _runtime is not None:
            print(f"[server] unloading {_runtime_model_id} to load {model_id}", flush=True)
            loop = asyncio.get_running_loop()
            await loop.run_in_executor(None, _runtime.unload)
            _runtime = None
            _runtime_model_id = None

        # Load new model in thread pool (keeps event loop responsive)
        print(f"[server] loading {model_id} ...", flush=True)
        key = _build_runtime_key(model_id)
        loop = asyncio.get_running_loop()
        runtime = await loop.run_in_executor(None, lambda: InferenceRuntime.from_key(key))
        print(f"[server] {model_id} ready.", flush=True)

        _runtime = runtime
        _runtime_model_id = model_id
        _last_used = time.monotonic()
        _reset_evict_timer()
        return _runtime
    finally:
        _lock.release()


class _ServiceUnavailable(Exception):
    pass


# ---------------------------------------------------------------------------
# Audio encoding
# ---------------------------------------------------------------------------
def _encode_audio(audio: torch.Tensor, sample_rate: int, fmt: str, speed: float) -> bytes:
    """Convert a raw audio tensor to the requested format bytes via pydub/ffmpeg.

    speed != 1.0 is applied via resampling (pitch-preserving tempo change is
    not implemented; this changes pitch proportionally like sample-rate tricks).
    """
    if audio.dim() == 1:
        audio = audio.unsqueeze(0)  # (1, T)

    if abs(speed - 1.0) > 1e-3:
        orig_len = audio.shape[-1]
        new_len = max(1, round(orig_len / speed))
        audio = torchaudio.functional.resample(audio, orig_len, new_len)

    audio_np = audio.cpu().float().squeeze(0).numpy()
    audio_int16 = (audio_np * 32767).clip(-32768, 32767).astype(np.int16)

    segment = AudioSegment(
        audio_int16.tobytes(),
        frame_rate=sample_rate,
        sample_width=2,
        channels=1,
    )

    pydub_fmt = "ogg" if fmt == "opus" else fmt
    export_kwargs: dict = {"codec": "libopus"} if fmt == "opus" else {}

    buf = io.BytesIO()
    segment.export(buf, format=pydub_fmt, **export_kwargs)
    return buf.getvalue()


# ---------------------------------------------------------------------------
# Voice file helpers
# ---------------------------------------------------------------------------
def _find_voice_file(voice_id: str) -> Path | None:
    for ext in VOICE_UPLOAD_EXTS:
        p = VOICES_DIR / f"{voice_id}{ext}"
        if p.exists():
            return p
    return None


def _voice_metadata(path: Path) -> dict:
    return {
        "id": path.stem,
        "object": "voice_content",
        "filename": path.name,
        "created_at": int(path.stat().st_mtime),
    }


# ---------------------------------------------------------------------------
# App lifespan
# ---------------------------------------------------------------------------
@asynccontextmanager
async def lifespan(_app: FastAPI):
    VOICES_DIR.mkdir(parents=True, exist_ok=True)
    print("[server] ready.", flush=True)
    yield


app = FastAPI(lifespan=lifespan)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
def _error(status: int, message: str, param: str | None = None) -> JSONResponse:
    return JSONResponse(
        status_code=status,
        content={
            "error": {
                "message": message,
                "type": "invalid_request_error" if status < 500 else "server_error",
                "param": param,
                "code": None,
            }
        },
    )


# ---------------------------------------------------------------------------
# GET /v1/models
# ---------------------------------------------------------------------------
@app.get("/v1/models")
def list_models():
    return {
        "object": "list",
        "data": [
            {"id": MODEL_VOICEDESIGN, "object": "model", "created": 1700000000, "owned_by": "irodori"},
            {"id": MODEL_BASE,        "object": "model", "created": 1700000000, "owned_by": "irodori"},
        ],
    }


# ---------------------------------------------------------------------------
# POST /v1/audio/speech
# ---------------------------------------------------------------------------
class SpeechRequest(BaseModel):
    model: str
    input: str
    voice: str = "alloy"
    instructions: Optional[str] = None
    response_format: str = "mp3"
    speed: float = 1.0


@app.post("/v1/audio/speech")
async def create_speech(req: SpeechRequest):
    # --- Validation ---
    text = req.input.strip()
    if not text:
        return _error(400, "Field 'input' must not be empty.", "input")

    fmt = req.response_format.lower()
    if fmt not in CONTENT_TYPES:
        return _error(
            400,
            f"Unsupported response_format '{fmt}'. Choose from: {', '.join(CONTENT_TYPES)}.",
            "response_format",
        )

    if not (0.25 <= req.speed <= 4.0):
        return _error(400, "Field 'speed' must be between 0.25 and 4.0.", "speed")

    model_id = req.model
    if model_id not in MODEL_CHECKPOINTS:
        return _error(400, f"Unknown model '{model_id}'.", "model")

    # --- Model-specific parameter resolution ---
    if model_id == MODEL_BASE:
        voice_file = _find_voice_file(req.voice)
        if voice_file is None:
            return _error(404, f"Voice '{req.voice}' not found.", "voice")
        ref_wav = str(voice_file)
        no_ref = False
        caption = None
        cfg_scale_caption = 0.0
        cfg_scale_speaker = CFG_SCALE_SPEAKER
    else:  # MODEL_VOICEDESIGN
        ref_wav = None
        no_ref = True
        caption = req.instructions.strip() if req.instructions else None
        cfg_scale_caption = CFG_SCALE_CAPTION
        cfg_scale_speaker = 0.0

    # --- Acquire runtime (TTL cache, may trigger model load) ---
    try:
        runtime = await acquire_runtime(model_id)
    except _ServiceUnavailable as exc:
        return JSONResponse(status_code=503, content={"error": {"message": str(exc), "type": "server_error", "param": None, "code": None}})
    except Exception as exc:
        return _error(500, f"Model load failed: {exc}")

    # --- Inference (in thread pool to keep event loop responsive) ---
    try:
        loop = asyncio.get_running_loop()
        result = await loop.run_in_executor(
            None,
            lambda: runtime.synthesize(
                SamplingRequest(
                    text=text,
                    caption=caption,
                    ref_wav=ref_wav,
                    ref_latent=None,
                    no_ref=no_ref,
                    ref_normalize_db=-16.0,
                    ref_ensure_max=True,
                    num_candidates=1,
                    decode_mode="sequential",
                    seconds=FIXED_SECONDS,
                    max_ref_seconds=30.0,
                    num_steps=NUM_STEPS,
                    cfg_guidance_mode="independent",
                    cfg_scale_text=CFG_SCALE_TEXT,
                    cfg_scale_caption=cfg_scale_caption,
                    cfg_scale_speaker=cfg_scale_speaker,
                    cfg_min_t=0.5,
                    cfg_max_t=1.0,
                    context_kv_cache=True,
                    trim_tail=True,
                ),
                log_fn=lambda msg: print(msg, flush=True),
            ),
        )
    except Exception as exc:
        return _error(500, str(exc))

    # --- Encode and return ---
    try:
        audio_bytes = _encode_audio(result.audios[0], result.sample_rate, fmt, req.speed)
    except Exception as exc:
        return _error(500, f"Audio encoding failed: {exc}")

    return StreamingResponse(io.BytesIO(audio_bytes), media_type=CONTENT_TYPES[fmt])


# ---------------------------------------------------------------------------
# /v1/audio/voice_contents  (reference audio management for irodori-tts-500m-v2)
# ---------------------------------------------------------------------------
@app.get("/v1/audio/voice_contents")
def list_voice_contents():
    items = []
    for p in sorted(VOICES_DIR.iterdir(), key=lambda f: f.stat().st_mtime):
        if p.suffix.lower() in VOICE_UPLOAD_EXTS:
            items.append(_voice_metadata(p))
    return {"object": "list", "data": items}


@app.post("/v1/audio/voice_contents", status_code=201)
async def create_voice_content(
    file: UploadFile = File(...),
    voice_id: Optional[str] = Form(None),
):
    ext = Path(file.filename or "").suffix.lower()
    if ext not in VOICE_UPLOAD_EXTS:
        return _error(400, f"Unsupported file format '{ext}'. Use wav, mp3, flac, or ogg.", "file")

    vid = voice_id.strip() if voice_id else Path(file.filename or "").stem
    if not vid or not _VOICE_ID_RE.match(vid):
        return _error(400, "voice_id must be non-empty alphanumeric/underscore/hyphen.", "voice_id")

    if _find_voice_file(vid) is not None:
        return _error(400, f"Voice '{vid}' already exists. Use PUT to replace.", "voice_id")

    dest = VOICES_DIR / f"{vid}{ext}"
    dest.write_bytes(await file.read())
    return JSONResponse(status_code=201, content=_voice_metadata(dest))


@app.get("/v1/audio/voice_contents/{voice_id}")
def get_voice_content(voice_id: str):
    p = _find_voice_file(voice_id)
    if p is None:
        return _error(404, f"Voice '{voice_id}' not found.", "voice_id")
    return _voice_metadata(p)


@app.put("/v1/audio/voice_contents/{voice_id}")
async def update_voice_content(voice_id: str, file: UploadFile = File(...)):
    ext = Path(file.filename or "").suffix.lower()
    if ext not in VOICE_UPLOAD_EXTS:
        return _error(400, f"Unsupported file format '{ext}'. Use wav, mp3, flac, or ogg.", "file")

    old = _find_voice_file(voice_id)
    if old is None:
        return _error(404, f"Voice '{voice_id}' not found.", "voice_id")

    if old.suffix.lower() != ext:
        old.unlink()

    dest = VOICES_DIR / f"{voice_id}{ext}"
    dest.write_bytes(await file.read())
    return _voice_metadata(dest)


@app.delete("/v1/audio/voice_contents/{voice_id}")
def delete_voice_content(voice_id: str):
    p = _find_voice_file(voice_id)
    if p is None:
        return _error(404, f"Voice '{voice_id}' not found.", "voice_id")
    p.unlink()
    return {"id": voice_id, "object": "voice_content", "deleted": True}


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8880)
