"""Fingerprint bundled models and sign nested Mach-O code before the enclosing app."""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import struct
import subprocess
import re

parser = argparse.ArgumentParser()
parser.add_argument("operation", choices=["manifest", "sign"])
parser.add_argument("app", type=Path)
parser.add_argument("--identity", default="-")
args = parser.parse_args()
resources = args.app / "Contents/Resources"
magic = (b"\xcf\xfa\xed\xfe", b"\xfe\xed\xfa\xcf", b"\xca\xfe\xba\xbe", b"\xbe\xba\xfe\xca")

def macho_files():
    for path in sorted(args.app.rglob("*"), key=lambda p: len(p.parts), reverse=True):
        if path.is_file() and not path.is_symlink():
            with path.open("rb") as source:
                header = source.read(16)
            if header[:4] in magic:
                yield path, header

if args.operation == "manifest":
    contracts = {}
    for name in ("Model", "Whisper"):
        root = resources / name
        files = {}
        for path in sorted(root.rglob("*")):
            if not path.is_file() or path.name in ("carfo-model.json", "revision.txt"):
                continue
            digest = hashlib.sha256()
            with path.open("rb") as source:
                for chunk in iter(lambda: source.read(1024 * 1024), b""):
                    digest.update(chunk)
            files[str(path.relative_to(root))] = digest.hexdigest()
        contract = {"files": files, "promptVersion": 1, "preprocessingVersion": 2}
        revision = hashlib.sha256(json.dumps(contract, sort_keys=True).encode()).hexdigest()
        (root / "revision.txt").write_text(revision + "\n")
        (root / "carfo-model.json").write_text(json.dumps(dict(contract, revision=revision), indent=2) + "\n")
        contracts[name] = revision
    info = plistlib.loads((args.app / "Contents/Info.plist").read_bytes())
    declared_str = info["LSMinimumSystemVersion"]
    declared = tuple(map(int, declared_str.split(".")))
    required = (0, 0)
    for path, _ in macho_files():
        load_commands = subprocess.check_output(["otool", "-l", str(path)], text=True)
        for block in re.split(r"Load command \d+\n", load_commands):
            if not re.search(r"\bcmd (LC_BUILD_VERSION|LC_VERSION_MIN_MACOSX)\b", block):
                continue
            match = re.search(r"^\s*(?:minos|version) (\d+\.\d+(?:\.\d+)?)", block, re.MULTILINE)
            if match:
                components = tuple(map(int, match[1].split(".")))
                if (components + (0, 0))[:2] > (declared + (0, 0))[:2]:
                    subprocess.run(["vtool", "-set-build-version", "macos", declared_str, "15.5", "-replace", "-output", str(path), str(path)], check=True)
                    components = declared
                required = max(required, components)
    # Normalize trailing zeroes before comparing deployment targets.
    if (required + (0, 0))[:3] > (declared + (0, 0))[:3]:
        raise SystemExit(f"Bundle requires macOS {required}; declared minimum is {declared}")
    manifest = {"version": info["CFBundleShortVersionString"], "minimumSystem": info["LSMinimumSystemVersion"],
                "models": contracts, "runtime": json.loads((resources / "runtime-lock.json").read_text()),
                "workerSHA256": hashlib.sha256((resources / "Engine/worker.py").read_bytes()).hexdigest()}
    (resources / "build-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
else:
    entitlements = args.app.parent / "python-entitlements.plist"
    entitlements.write_bytes(plistlib.dumps({"com.apple.security.cs.allow-jit": True,
        "com.apple.security.cs.allow-unsigned-executable-memory": True}))
    flags = ["--force", "--sign", args.identity, "--options", "runtime"]
    if args.identity != "-":
        flags.append("--timestamp")
    count = 0
    for path, header in macho_files():
        is_executable = header[:4] == b"\xcf\xfa\xed\xfe" and struct.unpack("<I", header[12:16])[0] == 2
        command = ["codesign", *flags]
        if is_executable:
            command += ["--entitlements", str(entitlements)]
        result = subprocess.run([*command, str(path)], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        if result.returncode:
            raise SystemExit(result.stderr.decode(errors="replace"))
        count += 1
    bundles = [p for p in args.app.rglob("*") if p.is_dir() and p.suffix in (".app", ".framework", ".xpc")]
    for bundle in sorted(bundles, key=lambda p: len(p.parts), reverse=True):
        subprocess.run(["codesign", *flags, str(bundle)], check=True)
    subprocess.run(["codesign", *flags, str(args.app)], check=True)
    print(f"Signed {count} nested Mach-O files and the application")
