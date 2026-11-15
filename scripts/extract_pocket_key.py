#!/usr/bin/env python3
"""Extract a single existing APP&SK key from a LOCAL full HCI/PacketLogger capture.

Never contacts a device, never prints a key, never guesses an account ID.
Output is a temporary local JSON file for Pocket Libre iOS's key importer.
"""
import argparse
import json
import os
from pathlib import Path
import re
import sys

PATTERN = re.compile(rb"APP&SK&([A-Za-z0-9]{16})(?![A-Za-z0-9])")


def extract_keys(path: Path) -> set[str]:
    keys: set[str] = set()
    overlap = b""
    with path.open("rb") as source:
        while chunk := source.read(1024 * 1024):
            data = overlap + chunk
            # Keep the entire last 24 bytes pending so the negative lookahead is
            # not evaluated at an artificial chunk boundary.
            cutoff = max(0, len(data) - 24)
            for match in PATTERN.finditer(data):
                if match.end() < cutoff:
                    keys.add(match.group(1).decode("ascii"))
            overlap = data[max(0, cutoff - 24):]
        for match in PATTERN.finditer(overlap):
            keys.add(match.group(1).decode("ascii"))
    return keys


def export_key(source: Path, destination: Path) -> None:
    keys = extract_keys(source)
    if len(keys) != 1:
        raise ValueError(f"{len(keys)} unterschiedliche Schlüssel gefunden; keine Datei geschrieben. Eine kurze, vollständige Aufzeichnung nur der eigenen Pocket-Verbindung verwenden.")
    destination.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    payload = json.dumps({"session_key": next(iter(keys))}).encode("utf-8")
    # Refuse overwrites/symlinks, create owner-readable only from the outset.
    descriptor = os.open(destination, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(descriptor, "wb") as output:
        output.write(payload)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("capture", type=Path)
    parser.add_argument("--output", type=Path, default=Path.home() / "PocketLocalSetup" / "pocket-key.json")
    args = parser.parse_args()
    try:
        export_key(args.capture, args.output)
    except (ValueError, OSError):
        # Do not echo capture contents, credentials or arbitrary file errors.
        print("Keine Schlüsseldatei erstellt. Prüfe: vollständiger Capture, genau ein Schlüssel, neue Ausgabedatei.", file=sys.stderr)
        return 1
    print("Bestehenden Schlüssel lokal exportiert (Dateirechte 0600). Kein Gerät verändert.")
    print("Die Datei enthält ein Geheimnis. Nur lokal ans eigene iPhone übertragen, dort importieren und danach die temporäre Datei und den Capture entfernen.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
