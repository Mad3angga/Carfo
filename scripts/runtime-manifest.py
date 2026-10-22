"""Record and verify the installed dependency closure used by the offline worker."""
import argparse
import importlib.metadata as metadata
import json
from pathlib import Path
import platform
from packaging.requirements import Requirement
from packaging.utils import canonicalize_name


def snapshot():
    pending = [(name, frozenset()) for name in ("mlx-vlm", "mlx-whisper", "pillow", "numpy")]
    seen = set()
    packages = {}
    while pending:
        name, extras = pending.pop()
        name = canonicalize_name(name)
        if (name, extras) in seen:
            continue
        seen.add((name, extras))
        dist = metadata.distribution(name)
        packages[name] = dist.version
        for item in dist.requires or []:
            requirement = Requirement(item)
            if requirement.marker and not any(requirement.marker.evaluate({"extra": extra}) for extra in (extras or {""})):
                continue
            installed = metadata.version(requirement.name)
            if requirement.specifier and not requirement.specifier.contains(installed, prereleases=True):
                raise SystemExit(f"Unsatisfied dependency: {item}; installed {installed}")
            pending.append((requirement.name, frozenset(requirement.extras)))
    return {"python": platform.python_version(), "machine": platform.machine(), "packages": dict(sorted(packages.items()))}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("operation", choices=["record", "verify"])
    parser.add_argument("manifest", type=Path)
    args = parser.parse_args()
    current = snapshot()
    if args.operation == "record":
        args.manifest.write_text(json.dumps(current, indent=2) + "\n")
        args.manifest.with_name("requirements-runtime.txt").write_text(
            "# Python " + current["python"] + "; Apple Silicon\n" +
            "\n".join(f"{name}=={version}" for name, version in current["packages"].items()) + "\n")
    else:
        expected = json.loads(args.manifest.read_text())
        if current != expected:
            raise SystemExit("Runtime differs from Support/runtime-lock.json; rebuild using the pinned dependencies.")
        import mlx.core  # noqa: F401
        import mlx_vlm  # noqa: F401
        import mlx_whisper  # noqa: F401
        from PIL import Image  # noqa: F401
        print(f"Runtime verified: Python {current['python']}, {len(current['packages'])} required distributions")


if __name__ == "__main__":
    main()
