#!/bin/bash
echo "Starting GraphNeT conversion script..."

# Read positional arguments.
GCD_INPUT=$1
I3_FILE=$2
OUT_DIR=$3
PULSE_KEY=$4
GRAPHNET_ROOT=$5

# Prepare the GCD input in a job-local temporary directory.
# This keeps extracted files out of the working directory.
JOB_TMP_DIR=$(mktemp -d -p . tmp_job_XXXXXX)
cd "$JOB_TMP_DIR"

# Extract supported GCD tar archives.
if [[ "$GCD_INPUT" == *.tar ]] || [[ "$GCD_INPUT" == *.tar.gz ]] || [[ "$GCD_INPUT" == *.tgz ]]; then
    echo "🔄 Detected tarball GCD. Extracting in isolated chamber..."
    # Select the first extracted file matching *.i3*.
    tar -xf "$GCD_INPUT" --wildcards "*.i3*" 2>/dev/null
    EXTRACTED_GCD_NAME=$(ls *.i3* | head -n 1)
    GCD_FILE="$(pwd)/$EXTRACTED_GCD_NAME"
    echo "✅ Successfully extracted GCD File: $GCD_FILE"
else
    echo "⚡ Detected native GCD (.i3.gz or similar). Skipping extraction."
    # Use unarchived GCD files directly.
    GCD_FILE="$GCD_INPUT"
fi

echo "=================================================="
echo "Target I3 File : $I3_FILE"
echo "Using GCD File : $GCD_FILE"
echo "Output Dir     : $OUT_DIR"
echo "Pulse Key      : $PULSE_KEY"
echo "GraphNeT Root  : $GRAPHNET_ROOT"
echo "=================================================="

# Configure the IceCube and GraphNeT environments.
eval $(/cvmfs/icecube.opensciencegrid.org/py3-v4.4.2/setup.sh)
export PYTHONPATH="${GRAPHNET_ROOT}/src:$PYTHONPATH"

# Run conversion.py from the parent of the temporary directory.
echo "Launching GraphNeT conversion..."
/data/user/mlarson/icetray/build/env-shell.sh \
/data/user/jliao/envs/mlarson_graphnet_env/bin/python3 \
-u ../conversion.py "$GCD_FILE" "$I3_FILE" "$OUT_DIR" "$PULSE_KEY"

# Remove the job-local temporary directory.
cd ..
rm -rf "$JOB_TMP_DIR"
echo "Job finished successfully and isolated directory cleaned."
