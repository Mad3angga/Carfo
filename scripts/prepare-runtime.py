"""Combine a standalone CPython distribution with a separately resolved package directory."""
import argparse
from pathlib import Path
import shutil

parser = argparse.ArgumentParser()
parser.add_argument("base", type=Path)
parser.add_argument("packages", type=Path)
parser.add_argument("destination", type=Path)
args = parser.parse_args()
if args.destination.exists():
    raise SystemExit("Destination must be a new directory.")
if not (args.base / "bin/python3").exists() or not args.packages.is_dir():
    raise SystemExit("Standalone Python and resolved packages are required.")
shutil.copytree(args.base, args.destination, symlinks=False,
                ignore=shutil.ignore_patterns("site-packages", "__pycache__"))
libraries = list((args.destination / "lib").glob("python3.*"))
if len(libraries) != 1:
    raise SystemExit("Cannot identify the Python standard library.")
shutil.copytree(args.packages, libraries[0] / "site-packages", symlinks=False,
                ignore=shutil.ignore_patterns("__pycache__"))
print(args.destination)
