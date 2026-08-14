#!/usr/bin/env bash
set -euo pipefail

# Validate the complete shared Madison conversion runtime without modifying the
# caller's shell. The defaults are the paths used by the validated I3-to-SQLite
# workflow; each path can be overridden explicitly when the site deployment
# changes.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GRAPHNET_ROOT="${GRAPHNET_ROOT:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
CVMFS_SETUP="${CVMFS_SETUP:-/cvmfs/icecube.opensciencegrid.org/py3-v4.4.2/setup.sh}"
ICETRAY_ENV_SHELL="${ICETRAY_ENV_SHELL:-/data/user/mlarson/icetray/build/env-shell.sh}"
CONVERSION_PYTHON="${CONVERSION_PYTHON:-/data/user/jliao/envs/mlarson_graphnet_env/bin/python3}"
CONVERSION_SITE_PACKAGES="${CONVERSION_SITE_PACKAGES:-/data/user/jliao/envs/mlarson_graphnet_env/lib/python3.12/site-packages}"

require_file() {
    local path="$1"
    local description="$2"
    if [ ! -r "$path" ]; then
        printf 'Missing or unreadable %s: %s\n' "$description" "$path" >&2
        exit 1
    fi
}

require_executable() {
    local path="$1"
    local description="$2"
    if [ ! -x "$path" ]; then
        printf 'Missing or non-executable %s: %s\n' "$description" "$path" >&2
        exit 1
    fi
}

require_executable "$CVMFS_SETUP" "IceCube CVMFS setup"
require_executable "$ICETRAY_ENV_SHELL" "IceTray env-shell"
require_executable "$CONVERSION_PYTHON" "conversion Python"
require_file "$CONVERSION_SITE_PACKAGES" "conversion site-packages directory"
require_file "$GRAPHNET_ROOT/src/graphnet/__init__.py" "GraphNeT checkout"

# setup.sh emits shell code. This script is its own process, so the exported
# IceCube variables do not contaminate the user's interactive shell.
eval "$("$CVMFS_SETUP")"
export PYTHONPATH="$GRAPHNET_ROOT/src:${PYTHONPATH:-}"

"$ICETRAY_ENV_SHELL" "$CONVERSION_PYTHON" -     "$CONVERSION_SITE_PACKAGES" <<'PY'
import sys

site_packages = sys.argv[1]
if site_packages in sys.path:
    sys.path.remove(site_packages)
sys.path.insert(0, site_packages)

if "numpy" in sys.modules:
    del sys.modules["numpy"]

import graphnet
import icecube
import numpy
from graphnet.data import I3ToSQLiteConverter
from graphnet.data.extractors.icecube import (
    I3FeatureExtractorIceCube86,
    I3TruthExtractor,
)

print("Conversion runtime preflight: PASS")
print("python:", sys.version)
print("python executable:", sys.executable)
print("numpy:", numpy.__version__)
print("numpy location:", numpy.__file__)
print("graphnet location:", graphnet.__file__)
print("icecube location:", getattr(icecube, "__file__", None))
print("converter:", I3ToSQLiteConverter.__name__)
print("extractors:", I3TruthExtractor.__name__, I3FeatureExtractorIceCube86.__name__)
PY

printf 'GraphNeT root: %s\n' "$GRAPHNET_ROOT"
printf 'IceTray env-shell: %s\n' "$ICETRAY_ENV_SHELL"
printf 'Conversion Python: %s\n' "$CONVERSION_PYTHON"
