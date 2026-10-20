"""Prepare isolated media fixtures and a native validation app. Does not launch UI."""
from pathlib import Path
import math
import plistlib
import shutil
import struct
import subprocess
import wave

root = Path(__file__).resolve().parents[1]
source = root / "build/Carfo.app"
if not source.is_dir():
    raise SystemExit("Build the app first: zsh scripts/build-app.sh")
ffmpeg = shutil.which("ffmpeg")
if not ffmpeg:
    raise SystemExit("FFmpeg is needed only to generate these test fixtures.")
run = root / ".runtime/NativeValidation"
(run / "Videos").mkdir(parents=True, exist_ok=True)
for color in ("red", "blue"):
    subprocess.run([ffmpeg, "-nostdin", "-y", "-hide_banner", "-loglevel", "error", "-f", "lavfi", "-i", f"color=c={color}:s=640x360:r=24:d=2", "-f", "lavfi", "-i", "sine=frequency=440:sample_rate=16000:duration=2", "-c:v", "libx264", "-pix_fmt", "yuv420p", "-c:a", "aac", "-shortest", str(run / "Videos" / f"Test {color}.mp4")], check=True)
    subprocess.run([ffmpeg, "-nostdin", "-y", "-hide_banner", "-loglevel", "error", "-i", str(run / "Videos" / f"Test {color}.mp4"), "-frames:v", "1", "-update", "1", str(run / f"{color}.jpg")], check=True)
with wave.open(str(run / "tone.wav"), "wb") as audio:
    audio.setnchannels(1)
    audio.setsampwidth(2)
    audio.setframerate(16000)
    audio.writeframes(b"".join(struct.pack("<h", int(6000 * math.sin(2 * math.pi * 440 * index / 16000))) for index in range(32000)))
app = root / ".runtime/Carfo Check.app"
shutil.copytree(source, app, dirs_exist_ok=True)
shutil.copy2(app / "Contents/MacOS/Carfo", app / "Contents/MacOS/CarfoCheck")
(app / "Contents/MacOS/Carfo").unlink()
info = app / "Contents/Info.plist"
metadata = plistlib.loads(info.read_bytes())
metadata.update(CFBundleIdentifier="id.carfo.CarfoCheck", CFBundleDisplayName="Carfo Check", CFBundleName="Carfo Check", CFBundleExecutable="CarfoCheck", CarfoSelfTestDirectory=str(run), FootageSelfTestDirectory=str(run))
info.write_bytes(plistlib.dumps(metadata))
subprocess.run(["/usr/bin/codesign", "--force", "--sign", "-", str(app)], check=True)
print(f"Open in Finder: {app}")
print(f"Results: {run / 'self-test.json'}")
