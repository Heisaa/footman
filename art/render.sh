#!/usr/bin/env bash
# Runs `art/build.py` in Blender and keeps the output to what was asked for.
#
# Blender wants writable config, cache and extension directories and will spend
# a screenful of tracebacks complaining when it cannot reach them. They are
# redirected here rather than in the Python, for the same reason `run.sh`
# redirects XDG_DATA_HOME: nothing in the build should have to know.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BLENDER="${BLENDER:-blender}"

SCRATCH="${TMPDIR:-/tmp}/footman-blender"
mkdir -p "$SCRATCH/config" "$SCRATCH/cache"
export XDG_CONFIG_HOME="$SCRATCH/config"
export XDG_CACHE_HOME="$SCRATCH/cache"
export BLENDER_USER_RESOURCES="$SCRATCH"

# `--offline-mode` stops the asset library reaching for the network, which in a
# sandbox is thirty seconds of timeout for nothing.
"$BLENDER" --background --factory-startup --offline-mode \
	--python "$HERE/build.py" -- "$@" 2>&1 \
	| grep -Ev '^(Blender [0-9]|Fra:|Read blend|MESA|libEGL|Failed to open dir)' \
	| grep -Ev 'Extensions:|register\(\)|bl_pkg|cattrs|Read-only file system'
