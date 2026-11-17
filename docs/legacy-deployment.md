# Legacy deployment boundary

These applications retain numeric platform card, user, card type, tier, and company IDs. Local identity/session IDs and provider-issued UUIDs are separate contracts. Never convert them indiscriminately.

NewPlatform and quickbit-pro/UserApp are excluded from every legacy deployment target. A directory name is not repository provenance.

Use `python3 scripts/deploy-legacy.py TARGET --deploy` from a committed checkout. Allowed targets are in `platform-contract.json`. Omit `--deploy` to build and verify only. The command checks the fetch/push origin, numeric contracts, and funding regression tests; builds a git archive of the exact revision; verifies brand/API pairing; and packages hashed release manifests.

The server stages and verifies all components before activation, preserves environment settings, retains previous releases, and rolls back on failed health checks. Each legacy systemd service requires a matching manifest and assembly digests before startup. `/health/contract` reports the running contract and revision. Missing manifests, NewPlatform provenance, wrong targets, and modified assemblies fail closed.

Old deployment entrypoints are retired because they could switch live symlinks before validation. Do not bypass the server gate or manufacture a manifest for an unverified artifact. Do not run database migrations for this release.

For rollback, use a previous verified release through the same activation process. Pre-boundary releases need explicit review; Cardeo's November 15 builds used the wrong source and must not be reused. Native app-store delivery is separate from these hosted targets.
