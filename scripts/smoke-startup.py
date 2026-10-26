"""Launch the packaged app with SwiftPM build resources inaccessible."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("app", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    app = args.app.resolve()
    build = Path(__file__).resolve().parent.parent / ".build"
    profile = '(version 1)(allow default)(deny file-read* (subpath ' + json.dumps(str(build)) + '))'
    started = time.monotonic()
    with tempfile.TemporaryDirectory(prefix="CarfoStartup-") as temporary:
        root = Path(temporary)
        data = root / "Library"
        environment = dict(os.environ, CARFO_DATA_DIR=str(data),
                           CARFO_DEFAULTS_SUITE="id.carfo.startup." + root.name,
                           SWIFT_BACKTRACE="enable=no")
        with (root / "stdout.log").open("w+") as stdout, (root / "stderr.log").open("w+") as stderr:
            process = subprocess.Popen(["/usr/bin/sandbox-exec", "-p", profile,
                                        str(app / "Contents/MacOS/Carfo")],
                                       stdout=stdout, stderr=stderr, env=environment, cwd=root)
            timings = {}
            try:
                while time.monotonic() - started < 30:
                    if process.poll() is not None:
                        stderr.seek(0)
                        raise SystemExit(f"App exited during startup ({process.returncode}): {stderr.read()[-4000:]}")
                    try:
                        timings = json.loads((data / "startup-timings.json").read_text())
                    except (OSError, ValueError):
                        pass
                    if all(stage in timings for stage in ("searchViewAppearedMS", "metadataReadyMS", "indexReadyMS")):
                        break
                    time.sleep(0.1)
                else:
                    stderr.seek(0)
                    raise SystemExit("App did not complete startup: " + stderr.read()[-4000:])
                executable = app / "Contents/MacOS/Carfo"
                attributes = subprocess.check_output(["/usr/bin/xattr", str(executable)], text=True).splitlines()
                forbidden = {"com.apple.ResourceFork", "com.apple.FinderInfo"}.intersection(attributes)
                if forbidden:
                    raise SystemExit(f"Startup modified executable metadata: {sorted(forbidden)}")
                subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
                if process.poll() is not None:
                    stderr.seek(0)
                    raise SystemExit(f"App exited after startup ({process.returncode}): {stderr.read()[-4000:]}")
            finally:
                if process.poll() is None:
                    process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()
    report = {"ok": True, "scope": "packaged UI startup with SwiftPM build resources denied; signature preserved",
              "elapsedSeconds": time.monotonic() - started, "startupTimings": timings}
    if args.output:
        args.output.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report))


if __name__ == "__main__":
    main()
