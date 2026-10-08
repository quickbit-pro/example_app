# Bundled departure-airport index

`airports.json` contains 3,194 records (150,727 UTF-8 bytes), sorted by IATA code.
Schema: `[city, countryCode, airportCode, latitude, longitude]` per record.
Coordinates are airport coordinates used for an on-device nearest-airport lookup.
They are not the user's location. This file is bundled; no runtime data download
or external reverse-geocoding request is needed.

Source: [OurAirports public data](https://ourairports.com/data/).
The source explicitly releases all data to the public domain, without a guarantee
of accuracy or fitness for use. Airport details and scheduled services may change.

- Official repository: [davidmegginson/ourairports-data](https://github.com/davidmegginson/ourairports-data)
- Source commit: `4f793127dcf3f6e6b4870862a4832c9dbef455e7`
- Source dataset date: 2026-09-23; retrieved 2026-09-23
- Pinned CSV: [https://raw.githubusercontent.com/davidmegginson/ourairports-data/4f793127dcf3f6e6b4870862a4832c9dbef455e7/airports.csv](https://raw.githubusercontent.com/davidmegginson/ourairports-data/4f793127dcf3f6e6b4870862a4832c9dbef455e7/airports.csv)
- Source CSV SHA-256: `afee98cc969c6564a76807bee54859e0727b7b4e68421c0ab05967cd0c5a76ea`
- Bundled JSON SHA-256: `e1a047eced22deb93533a4b99cd63259848cfdf21ce9d104a3c271ca6e16eb90`

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
