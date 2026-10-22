"""Exercise all worker modalities using bundled Python, models, and empty offline caches."""
import argparse
import json
import math
import os
from pathlib import Path
import struct
import subprocess
import tempfile
import time
import wave

parser = argparse.ArgumentParser()
parser.add_argument("app", type=Path)
parser.add_argument("--output", type=Path)
args = parser.parse_args()
resources = args.app.resolve() / "Contents/Resources"
python = resources / "Python/bin/python3"
started = time.perf_counter()
with tempfile.TemporaryDirectory(prefix="CarfoOffline-") as temporary:
    root = Path(temporary)
    # PPM is supported by Pillow and needs no host image libraries to generate.
    image = root / "red.ppm"
    image.write_bytes(b"P6\n64 64\n255\n" + bytes([255, 0, 0]) * 64 * 64)
    audio = root / "tone.wav"
    with wave.open(str(audio), "wb") as wav:
        wav.setparams((1, 2, 16000, 0, "NONE", "not compressed"))
        wav.writeframes(b"".join(struct.pack("<h", int(2000 * math.sin(i * math.tau * 440 / 16000))) for i in range(16000)))
    requests = [{"op": "verify"}, {"op": "text", "text": "task: search result | query: red"},
                {"op": "images", "paths": [str(image)]}, {"op": "audio", "path": str(audio)},
                {"op": "texts", "texts": ["title: none | text: Halo dunia"]},
                {"op": "transcribe", "path": str(audio)}]
    env = dict(os.environ, HF_HOME=str(root / "cache"), XDG_CACHE_HOME=str(root / "cache"),
               HF_HUB_OFFLINE="1", TRANSFORMERS_OFFLINE="1", PYTHONNOUSERSITE="1", PYTHONDONTWRITEBYTECODE="1")
    env.pop("PYTHONPATH", None)
    source = "\n".join(json.dumps(dict(request, id=index)) for index, request in enumerate(requests)) + "\n"
    result = subprocess.run([str(python), "-I", "-B", "-u", str(resources / "Engine/worker.py"),
                             "--model", str(resources / "Model"), "--whisper", str(resources / "Whisper")],
                            input=source, text=True, capture_output=True, timeout=600, env=env)
    if result.returncode:
        raise SystemExit(result.stderr[-4000:])
    responses = [json.loads(line) for line in result.stdout.splitlines() if line.startswith("{")]
    if len(responses) != len(requests):
        raise SystemExit("Incomplete worker responses: " + result.stdout[-1000:])
    for index, response in enumerate(responses):
        if not response.get("ok") or response.get("id") != index:
            raise SystemExit(f"Offline operation {requests[index]['op']} failed: {response}")
    for response in responses[1:4]:
        if len(response.get("embedding", [])) != 768:
            raise SystemExit("Invalid embedding dimension")
    if len(responses[4].get("embeddings", [[]])[0]) != 768 or not isinstance(responses[5].get("cues"), list):
        raise SystemExit("Invalid transcript document or Whisper response")
report = {"ok": True, "scope": "offline synthetic worker smoke, all modalities; not retrieval quality",
          "operations": [r["op"] for r in requests], "elapsedSeconds": time.perf_counter() - started}
if args.output:
    args.output.write_text(json.dumps(report, indent=2) + "\n")
print(json.dumps(report))
