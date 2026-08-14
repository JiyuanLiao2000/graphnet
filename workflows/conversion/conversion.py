"""Convert one I3 file to an SQLite database via a temporary directory."""

import sys
import os

# Private Python environment used by the Madison conversion workflow.
my_env_path = "/data/user/jliao/envs/mlarson_graphnet_env/lib/python3.12/site-packages"

# Give the private environment the highest import priority.
if my_env_path in sys.path:
    sys.path.remove(my_env_path)
sys.path.insert(0, my_env_path)

# Remove a previously imported NumPy module before re-importing it.
if 'numpy' in sys.modules:
    del sys.modules['numpy']

# Re-import NumPy from the highest-priority path.
import numpy

# Report the NumPy installation used by the job.
print(f"Internal Check - NumPy Location: {numpy.__file__}")
print(f"Internal Check - NumPy Version: {numpy.__version__}")







import tempfile
from typing import List
from graphnet.data import I3ToSQLiteConverter
from graphnet.data.extractors.icecube import (
    I3TruthExtractor,
    I3FeatureExtractorIceCube86,
)

def main_icecube86(input_i3_dir: str,
                   outdir: str,
                   gcd_rescue: str,
                   workers: int,
                   pulse_key: str) -> None:
    """Convert a single IceCube-86 I3 file to SQLite format."""
    extractors = [I3TruthExtractor(),
                  I3FeatureExtractorIceCube86(pulse_key)]

    converter = I3ToSQLiteConverter(extractors = extractors,
                                      outdir = outdir,
                                      gcd_rescue = gcd_rescue,
                                      num_workers = workers)

    # Convert the contents of the temporary input directory.
    converter(input_i3_dir)

if __name__ == "__main__":
    if len(sys.argv) != 5:
        print(
            "Usage: python3 conversion.py "
            "<gcd_file_path> <i3_file_path> <output_directory> <pulse_key>"
        )
        sys.exit(1)

    gcd_path = sys.argv[1]
    i3_path = sys.argv[2]
    out_directory = sys.argv[3]
    pulse_key = sys.argv[4]

    base_name = os.path.basename(i3_path)
    db_name = base_name.split('.i3')[0]

    print("="*50)
    print("GraphNeT Conversion Job Started")
    print("="*50)
    print(f"Target Database Name : {db_name}")
    print(f"Input I3 File        : {i3_path}")
    print(f"Input GCD File       : {gcd_path}")
    print(f"Output Directory     : {out_directory}")
    print(f"Pulse Key            : {pulse_key}")
    print("="*50, flush=True)

    os.makedirs(out_directory, exist_ok=True)
    num_workers = 1

    # Expose the input I3 file through an isolated temporary directory.
    with tempfile.TemporaryDirectory() as tmp_dir:
        print(f"Created temporary directory: {tmp_dir}", flush=True)
        symlink_path = os.path.join(tmp_dir, base_name)

        # Create a symbolic link without copying the input file.
        os.symlink(i3_path, symlink_path)
        print(f"Created symlink for i3 file inside temp directory.", flush=True)

        # Pass the temporary directory to the converter.
        main_icecube86(input_i3_dir = tmp_dir,
                       outdir = out_directory,
                       workers = num_workers,
                       gcd_rescue = gcd_path,
                       pulse_key = pulse_key)

    # TemporaryDirectory removes the directory and symbolic link on exit.

    print("\nConversion successfully completed for:", db_name)
