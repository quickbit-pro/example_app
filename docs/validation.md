# Validation

See [the current release notes](releases/2026-10-07-sample-sync.md) for the
application validation baseline. Customer branding is validated with
`python3 -m unittest discover -s scripts/tests -p 'test_*.py'`.

Run `python3 scripts/validate-customer-export.py` before publishing this template.
The legacy scaffold checker under `tests/validation` predates the current app
structure; its string-matching failures are not a substitute for the Flutter,
backend and web application tests.
