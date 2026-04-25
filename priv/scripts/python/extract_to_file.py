"""
Run extract_all and save the JSON output to priv/scripts/test_data/.

Usage: python extract_to_file.py <filepath>

The output file is saved alongside the input with a .json extension.
"""

import json
import os
import sys

from extract_all import extract_all


def main():
    if len(sys.argv) < 2:
        print("Usage: python extract_to_file.py <filepath>")
        sys.exit(1)

    filepath = sys.argv[1]
    if not os.path.isfile(filepath):
        print(f"File not found: {filepath}")
        sys.exit(1)

    result = extract_all(filepath)

    base_name = os.path.splitext(os.path.basename(filepath))[0]
    output_dir = os.path.join(os.path.dirname(__file__), "..", "test_data")
    os.makedirs(output_dir, exist_ok=True)
    output_path = os.path.join(output_dir, f"{base_name}.json")

    with open(output_path, "w") as f:
        json.dump(result.model_dump(), f, indent=2)

    print(f"Saved: {output_path}")


if __name__ == "__main__":
    main()
