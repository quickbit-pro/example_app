#!/usr/bin/env python3
"""Reproduce the bundled airport index from a pinned public-domain source.

This is a maintenance command, never an application runtime dependency.
Pass --source-csv to reproduce offline from an already downloaded source file.
Updating the data requires reviewing and changing both the commit and checksum.
"""

import argparse
import csv
import hashlib
import io
import json
import math
from pathlib import Path
import re
import unicodedata
import urllib.request


SOURCE_COMMIT = "4f793127dcf3f6e6b4870862a4832c9dbef455e7"
SOURCE_DATE = "2026-09-23"
SOURCE_SHA256 = "afee98cc969c6564a76807bee54859e0727b7b4e68421c0ab05967cd0c5a76ea"
SOURCE_URL = (
    "https://raw.githubusercontent.com/davidmegginson/ourairports-data/"
    f"{SOURCE_COMMIT}/airports.csv"
)
MAX_SOURCE_BYTES = 20 * 1024 * 1024


def build_index(raw: bytes) -> list[list]:
    if len(raw) > MAX_SOURCE_BYTES:
        raise ValueError("Airport source exceeds the reviewed size limit")
    if hashlib.sha256(raw).hexdigest() != SOURCE_SHA256:
        raise ValueError("Airport source checksum does not match the reviewed pin")

    airports = []
    codes = set()
    for row in csv.DictReader(io.StringIO(raw.decode("utf-8-sig"))):
        if row["type"] not in {"medium_airport", "large_airport"}:
            continue
        if row["scheduled_service"] != "yes":
            continue
        city = unicodedata.normalize("NFC", row["municipality"].strip())
        # Reject markup and Unicode controls (including bidi/zero-width controls).
        # Store only plain text labels; no source HTML, links or descriptions.
        if not city or len(city) > 80 or any(
            unicodedata.category(char).startswith("C") or char in "<>"
            for char in city
        ):
            continue
        code, country = row["iata_code"], row["iso_country"]
        if not re.fullmatch(r"[A-Z]{3}", code):
            continue
        if not re.fullmatch(r"[A-Z]{2}", country):
            continue
        try:
            latitude = float(row["latitude_deg"])
            longitude = float(row["longitude_deg"])
        except ValueError:
            continue
        if not math.isfinite(latitude) or not math.isfinite(longitude):
            continue
        if not -90 <= latitude <= 90 or not -180 <= longitude <= 180:
            continue
        if code in codes:
            raise ValueError(f"Duplicate IATA code requires review: {code}")
        codes.add(code)
        airports.append([city, country, code, latitude, longitude])
    if not airports:
        raise ValueError("Airport index cannot be empty")
    return sorted(airports, key=lambda row: row[2])


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-csv", type=Path)
    args = parser.parse_args()
    if args.source_csv:
        raw = args.source_csv.read_bytes()
    else:
        with urllib.request.urlopen(SOURCE_URL, timeout=60) as response:
            raw = response.read(MAX_SOURCE_BYTES + 1)
    airports = build_index(raw)
    output = (json.dumps(airports, ensure_ascii=False, separators=(",", ":")) + "\n").encode("utf-8")
    checksum = hashlib.sha256(output).hexdigest()
    asset_dir = Path(__file__).resolve().parents[1] / "mobile_flutter/assets/assistant"
    asset_dir.mkdir(parents=True, exist_ok=True)
    (asset_dir / "airports.json").write_bytes(output)
    (asset_dir / "README.md").write_text(
        f"""# Bundled departure-airport index

`airports.json` contains {len(airports):,} records ({len(output):,} UTF-8 bytes), sorted by IATA code.
Schema: `[city, countryCode, airportCode, latitude, longitude]` per record.
Coordinates are airport coordinates used for an on-device nearest-airport lookup.
They are not the user's location. This file is bundled; no runtime data download
or external reverse-geocoding request is needed.

Source: [OurAirports public data](https://ourairports.com/data/).
The source explicitly releases all data to the public domain, without a guarantee
of accuracy or fitness for use. Airport details and scheduled services may change.

- Official repository: [davidmegginson/ourairports-data](https://github.com/davidmegginson/ourairports-data)
- Source commit: `{SOURCE_COMMIT}`
- Source dataset date: {SOURCE_DATE}; retrieved {SOURCE_DATE}
- Pinned CSV: [{SOURCE_URL}]({SOURCE_URL})
- Source CSV SHA-256: `{SOURCE_SHA256}`
- Bundled JSON SHA-256: `{checksum}`

The maintenance script keeps only `medium_airport` and `large_airport` rows with
`scheduled_service=yes`, a nonempty municipality, uppercase three-letter IATA and
two-letter country codes, and finite latitude/longitude within geographic bounds.
Municipalities are NFC-normalized and trimmed, at most 80 characters, and rejected
if they contain markup angle brackets or Unicode control/format/surrogate/private
use/unassigned characters. Duplicate IATA codes fail generation for review.
No source descriptions, URLs, airport frequencies, or user data are included.

Reproduce from the repository root with:

```sh
python3 scripts/update-assistant-airports.py
# Or without network access, using the exact pinned CSV:
python3 scripts/update-assistant-airports.py --source-csv /path/to/airports.csv
```

To refresh, explicitly review and update the source commit, date and SHA-256 in
the script, regenerate, and review the data diff. The application never runs this
script. An airport's inclusion indicates scheduled service in the source snapshot,
not guaranteed service, available seats or a particular route.
""",
        encoding="utf-8",
    )
    print(f"Wrote {len(airports)} airports, {len(output)} bytes, SHA-256 {checksum}")


if __name__ == "__main__":
    main()
