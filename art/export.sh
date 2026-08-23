#!/usr/bin/env bash
# Writes a figure out as a `.glb` the game can instantiate. `art/export.py` is
# the command line, and `docs/THE_MODELS.md` is the contract it answers.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$HERE/blender.sh" export.py "$@"
