#!/usr/bin/env bash
# Builds a figure at the density it ships at and writes it as a `.glb`.
# `art/model.py` is the command line; `docs/THE_MODELS.md` is the contract.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$HERE/blender.sh" model.py "$@"
