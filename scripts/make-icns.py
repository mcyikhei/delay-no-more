#!/usr/bin/env python3
"""Resize the supplied artwork and package it as a macOS app icon."""
from pathlib import Path
import struct
import subprocess
import sys
from tempfile import TemporaryDirectory

source, destination = map(Path, sys.argv[1:])
entries = [(b'icp4', 16), (b'icp5', 32), (b'icp6', 64), (b'ic07', 128),
           (b'ic08', 256), (b'ic09', 512), (b'ic10', 1024)]
chunks = []
with TemporaryDirectory() as folder:
    for kind, pixels in entries:
        scaled = Path(folder) / f'{pixels}.png'
        subprocess.run(
            ['/usr/bin/sips', '-z', str(pixels), str(pixels), str(source), '--out', str(scaled)],
            check=True, stdout=subprocess.DEVNULL,
        )
        png = scaled.read_bytes()
        chunks.append(kind + struct.pack('>I', len(png) + 8) + png)
payload = b''.join(chunks)
destination.write_bytes(b'icns' + struct.pack('>I', len(payload) + 8) + payload)
