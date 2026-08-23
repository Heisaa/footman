#!/usr/bin/env bash
# Builds and photographs the figures. `art/build.py` is the command line.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$HERE/blender.sh" build.py "$@"
