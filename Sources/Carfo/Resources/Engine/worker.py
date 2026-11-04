# pyright: reportMissingImports=false, reportOptionalMemberAccess=false, reportOptionalCall=false, reportAttributeAccessIssue=false
"""Local-only EmbeddingGemma 2 inference and Whisper transcription over a private stdin/stdout pipe."""
import argparse
import contextlib
import json
import os
from pathlib import Path
import sys
import traceback
from typing import Any
import wave

for key in ("HF_HUB_OFFLINE", "TRANSFORMERS_OFFLINE", "HF_HUB_DISABLE_TELEMETRY", "DO_NOT_TRACK"):
    os.environ[key] = "1"
os.environ["TOKENIZERS_PARALLELISM"] = "false"
os.environ["PYTHONDONTWRITEBYTECODE"] = "1"


def read_pcm16_wav(path, max_seconds, offset_seconds=0.0, duration_seconds=None):
    import numpy as np
    with wave.open(str(Path(path).resolve(strict=True)), "rb") as audio:
        if audio.getnchannels() != 1 or audio.getframerate() != 16000 or audio.getsampwidth() != 2:
            raise ValueError("Audio lokal harus berupa WAV mono 16 kHz PCM16.")
        framerate = audio.getframerate()
        total_frames = audio.getnframes()
        start_frame = int(offset_seconds * framerate)
        if start_frame >= total_frames:
            return np.zeros(0, dtype=np.float32)
        audio.setpos(start_frame)
        frames_to_read = total_frames - start_frame
        if duration_seconds is not None:
            frames_to_read = min(frames_to_read, int(duration_seconds * framerate))
        frames_to_read = min(frames_to_read, int(framerate * max_seconds))
        return np.frombuffer(audio.readframes(frames_to_read), dtype="<i2").astype(np.float32) / 32768.0


class Transcriber:
    """Whisper speech-to-text with sentence-level timestamps, fully offline."""

    def __init__(self, directory):
        self.directory = Path(directory).resolve() if directory else None

    def transcribe(self, request: dict[str, Any]) -> dict[str, Any]:
        if self.directory is None or not (self.directory / "config.json").exists():
            raise RuntimeError("Model transkripsi Whisper belum ditemukan. Siapkan mlx-community/whisper-small-mlx di Mac ini.")
        try:
            import mlx_whisper  # type: ignore
        except ImportError as error:
            raise RuntimeError("Paket mlx-whisper belum terpasang di runtime Python. " + str(error)) from error
        offset = float(request.get("offset", 0.0))
        duration = request.get("duration")
        duration_sec = float(duration) if duration is not None else None
        samples = read_pcm16_wav(request["path"], max_seconds=4 * 3600, offset_seconds=offset, duration_seconds=duration_sec)
        if len(samples) == 0:
            return {"cues": [], "language": None}
        language = request.get("language") or None
        result = mlx_whisper.transcribe(
            samples,
            path_or_hf_repo=str(self.directory),
            language=language,
            condition_on_previous_text=False,
            verbose=None,
        )
        cues = []
        for segment in result.get("segments", []):
            text = str(segment.get("text", "")).strip()
            start, end = float(segment.get("start", 0)), float(segment.get("end", 0))
            if not text or end <= start:
                continue
            if float(segment.get("no_speech_prob", 0)) > 0.6 and float(segment.get("avg_logprob", 0)) < -1.0:
                continue
            cues.append({"start": start + offset, "end": end + offset, "text": text})
        language_result = result.get("language")
        del samples, result
        import gc; gc.collect()
        return {"cues": cues, "language": language_result}


class EmbeddingEngine:
    def __init__(self, directory):
        self.directory = Path(directory).resolve(strict=True)
        config = json.loads((self.directory / "config.json").read_text())
        if config.get("model_type") != "embedding_gemma2":
            raise ValueError("Pilih folder model EmbeddingGemma 2 yang berisi config.json dan bobot safetensors.")
        self.model: Any = None
        self.processor: Any = None
        self.mx: Any = None
        self.op_count = 0

    def load(self):
        if self.model is not None:
            return
        try:
            import mlx.core as mx  # type: ignore
            from mlx_vlm.utils import load  # type: ignore
            self.model, self.processor = load(str(self.directory), local_files_only=True, trust_remote_code=False)
            self.mx = mx
            print("EmbeddingGemma 2 loaded locally using MLX.", file=sys.stderr, flush=True)
        except ImportError as error:
            raise RuntimeError("Mesin MLX belum dapat dimuat. Pastikan runtime Python mendukung mlx dan mlx_vlm untuk EmbeddingGemma 2. " + str(error)) from error

    def clear_cache(self):
        if self.mx is not None and hasattr(self.mx, "metal"):
            try:
                self.mx.metal.clear_cache()
            except Exception:
                pass
        import gc; gc.collect()

    def maybe_clear_cache(self, interval: int = 30):
        self.op_count += 1
        if self.op_count % interval == 0:
            self.clear_cache()

    def encode(self, request: dict[str, Any]) -> dict[str, Any]:
        self.load()
        op = request["op"]
        if op == "texts":
            texts = request.get("texts", [])
            if not 1 <= len(texts) <= 64:
                raise ValueError("Satu permintaan harus berisi 1 hingga 64 teks.")
            try:
                tokenizer = self.processor.tokenizer
                encoded = tokenizer(texts, padding=True, truncation=True, max_length=2048, return_tensors="np")
                inputs = {key: self.mx.array(encoded[key]) for key in ("input_ids", "attention_mask") if key in encoded}
                result = self.model(**inputs).text_embeds
                self.mx.eval(result)
                vector = result.astype(self.mx.float32)
                norm = self.mx.sqrt(self.mx.sum(vector * vector, axis=-1, keepdims=True))
                vector = vector / (norm + 1e-12)
                self.mx.eval(vector)
                embeddings = vector.tolist()
                del inputs, result, vector, norm
            except Exception:
                embeddings = [self.encode({"op": "text", "text": text})["embedding"] for text in texts]
            self.maybe_clear_cache(interval=10)
            return {"embeddings": embeddings, "dimensions": 768}
        if op == "verify":
            return {"backend": "MLX · Apple Silicon", "model": "EmbeddingGemma 2", "dimensions": 768}
        if op == "purge":
            self.clear_cache()
            self.op_count = 0
            return {"purged": True}
        if op == "text":
            text = request.get("text", "").strip()
            if not text or len(text) > 12000:
                raise ValueError("Tulis pencarian yang lebih singkat.")
            tokenizer = self.processor.tokenizer
            encoded = tokenizer([text], padding=True, truncation=True, max_length=2048, return_tensors="np")
            inputs = {key: self.mx.array(encoded[key]) for key in ("input_ids", "attention_mask")}
        elif op == "images":
            from PIL import Image
            paths = request.get("paths", [])
            if not 1 <= len(paths) <= 8:
                raise ValueError("Satu segmen harus berisi 1 hingga 8 frame.")
            frames = []
            for path in paths:
                with Image.open(Path(path).resolve(strict=True)) as image:
                    frames.append(image.convert("RGB").copy())
            media = self.processor.image_processor(images=frames, return_tensors="np")
            prompt = "".join(self.processor.replace_image_token(media, index) for index in range(len(frames)))
            text = self.processor.tokenizer([prompt], return_tensors="np", padding=True)
            inputs = {**media, **text}
            del frames
        elif op == "audio":
            offset = float(request.get("offset", 0.0))
            duration = request.get("duration")
            duration_sec = float(duration) if duration is not None else 30.0
            samples = read_pcm16_wav(request["path"], max_seconds=30, offset_seconds=offset, duration_seconds=duration_sec)
            media = self.processor.feature_extractor([samples], sampling_rate=16000, return_tensors="np", padding=True)
            prompt = self.processor.replace_audio_token(media, 0)
            text = self.processor.tokenizer([prompt], return_tensors="np", padding=True)
            inputs = {**media, **text}
            del samples
        else:
            raise ValueError("Operasi mesin lokal tidak dikenali.")
        supported = {"input_ids", "attention_mask", "pixel_values", "image_position_ids", "pixel_values_videos", "video_position_ids", "input_features", "input_features_mask", "position_ids"}
        inputs = {key: value if isinstance(value, self.mx.array) else self.mx.array(value) for key, value in inputs.items() if key in supported}
        result = self.model(**inputs).text_embeds
        self.mx.eval(result)
        vector = result[0].astype(self.mx.float32)
        if vector.shape != (768,) or not bool(self.mx.all(self.mx.isfinite(vector)).item()):
            raise ValueError("Model menghasilkan embedding tidak valid.")
        norm = self.mx.sqrt(self.mx.sum(vector * vector))
        if float(norm.item()) <= 0:
            raise ValueError("Model menghasilkan embedding kosong.")
        vector = vector / norm
        self.mx.eval(vector)
        out = vector.tolist()
        del inputs, result, vector, norm
        self.maybe_clear_cache()
        return {"embedding": out, "dimensions": 768}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", required=True)
    parser.add_argument("--whisper", default=None)
    args = parser.parse_args()
    with contextlib.redirect_stdout(sys.stderr):
        engine = EmbeddingEngine(args.model)
        transcriber = Transcriber(args.whisper)
    for line in sys.stdin:
        req_id = None
        try:
            request = json.loads(line)
            req_id = request.get("id")
            response: dict[str, Any]
            with contextlib.redirect_stdout(sys.stderr):
                if request.get("op") == "transcribe":
                    response = transcriber.transcribe(request)
                elif request.get("op") == "purge":
                    engine.clear_cache()
                    response = {"ok": True, "purged": True}
                else:
                    response = engine.encode(request)
            response["ok"] = True
        except Exception as error:
            traceback.print_exc(file=sys.stderr)
            response = {"ok": False, "error": str(error)}
        if req_id is not None:
            response["id"] = req_id
        print(json.dumps(response, ensure_ascii=False, allow_nan=False), flush=True)


if __name__ == "__main__":
    main()
