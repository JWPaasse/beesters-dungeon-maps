#!/usr/bin/env python3
"""Download the latest CMaNGOS Classic database dump (GPL-3.0) to a file.

    python3 tools/get_classicdb.py /tmp/classicdb.sql.gz
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from build_quest_text import download  # noqa: E402

if __name__ == "__main__":
    Path(sys.argv[1]).write_bytes(download())
    print("Saved", sys.argv[1])
