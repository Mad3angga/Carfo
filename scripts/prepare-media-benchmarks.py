"""Generate portable codec/resolution and long-audio fixtures without personal media."""
from pathlib import Path
import shutil
import subprocess
import wave

root = Path(__file__).resolve().parents[1] / ".runtime/BenchMedia"
root.mkdir(parents=True, exist_ok=True)
ffmpeg = shutil.which("ffmpeg")
if not ffmpeg:
    raise SystemExit("FFmpeg is required for fixture generation")
for size in ("640x360", "1920x1080"):
    for codec, extension, options in (
        ("h264", "mp4", ["-c:v", "libx264", "-pix_fmt", "yuv420p"]),
        ("hevc", "mp4", ["-c:v", "libx265", "-tag:v", "hvc1", "-pix_fmt", "yuv420p", "-x265-params", "pools=1:log-level=error"]),
        ("prores", "mov", ["-c:v", "prores_ks", "-profile:v", "0", "-pix_fmt", "yuv422p10le"])):
        subprocess.run([ffmpeg, "-nostdin", "-y", "-hide_banner", "-loglevel", "error", "-f", "lavfi", "-i",
                        f"testsrc2=size={size}:rate=24:duration=2", "-threads", "2", *options,
                        str(root / f"{codec}-{size}.{extension}")], check=True)
with wave.open(str(root / "long.wav"), "wb") as audio:
    audio.setparams((1, 2, 16000, 0, "NONE", "not compressed"))
    for _ in range(20 * 60):
        audio.writeframesraw(bytes(32000))
print(root)
