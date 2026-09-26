#!/usr/bin/env bash
# Hardware-free checks; no installed camera helpers or system configuration run.
set -Eeuo pipefail
repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd -- "$repo_dir"
export PYTHONDONTWRITEBYTECODE=1

for tool in python3 gst-launch-1.0 desktop-file-validate; do
  if ! command -v "$tool" >/dev/null; then
    printf 'Missing test dependency: %s\n' "$tool" >&2
    exit 1
  fi
done

shopt -s nullglob
shell_files=(bin/surface-camera bin/surface-camera-dma bin/camera-feed-launch ./*.sh scripts/*.sh scripts/configure-audio scripts/configure-workaround tests/*.sh)
for script in "${shell_files[@]}"; do
  bash -n "$script"
done

# Compile in memory: py_compile writes bytecode even with -B set.
python3 - <<'PY'
from pathlib import Path

sources = [Path("bin/camera-feed"), *sorted(Path("tests").glob("*.py"))]
for source in sources:
    compile(source.read_bytes(), str(source), "exec")
print("PASS: Bash and Python syntax.")
PY

python3 tests/test_camera_feed.py
bash tests/test_surface_camera.sh
bash tests/test_audio_config.sh

# Installer checks use temporary homes and fake privilege commands.
for test in tests/test_install*.sh; do
  bash "$test"
done
for test in tests/test_install*.py; do
  python3 "$test"
done

printf 'All hardware-free checks passed.\n'
