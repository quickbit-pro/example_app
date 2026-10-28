> Brand profile: `scripts/evidence/example.json`. Set the staging host and confirm scope before recording; placeholders are not deployment targets.

# Repeatable Equals evidence capture

Use this scenario for each Flutter brand and release. The source is the supplied **Third-party Programme Manager Guidance, September 2026 v12**. Its fifteen Evidence boxes are indexed in `scripts/evidence/requirements.json`, with PDF page numbers, required paths and media. This workflow collects evidence; it does not certify the implementation or substitute a mocked screen for a real provider event.

For Hoppa, **Equals cards are out of scope**: 3.4 and 3.5 are excluded, as requested. Interlace crypto cards remain a separate product. For 4.2/4.3, this PDF says VoP evidence is deferred while sandbox support is unavailable. Confirm that with Equals for each certification run; never relabel a deferred requirement as passed. Confirm all null scope fields in the brand profile before capture.

## Reuse for a new app

1. Copy `scripts/evidence/example.json` to a new brand profile. Set the staging URL, platform, every marketing page URL, provider/card scope, supported payment rails, device approval, corporate scope and whether balances are derived. Do not put credentials, OTPs or customer records in the profile.
2. Supply the released commit/build number and the exact guidance PDF. Also obtain the current Financial Promotions Guidance, Data Retention Policy and CoP/VoP Name-Matching Scenarios referenced by that PDF. Their contents are not included in the supplied guidance, so disclosure wording and retention periods cannot be signed off from this PDF alone.
3. Use synthetic staging customers: a new signup, an existing customer needing re-acceptance, a verified payment customer, and separate maker/checker users if supported. Prepare approved sandbox recipients and provider-triggered test transactions/challenges. Keep production accounts out of the recording session.
4. Run the relevant Flutter/API regressions first. A failing implementation remains a gap in the report; do not alter screenshots, bypass a challenge or replace live responses to make a recording look successful.
5. Initialize a run, drive the actual UI, capture each case, inspect the files and hand off the inventory for review. Repeat for each shipped platform where behavior differs. Flutter Web evidence does not prove native biometrics, enrolment or lock-screen behavior.

## Codex task to reuse

> Read docs/equals-evidence-codex-scenario.md and the selected scripts/evidence profile. Confirm the staging build, requirement scope and test-account readiness from available context. Use the Playwright skill for Flutter Web: take fresh accessibility snapshots before actions and after navigation, use visible semantic controls, and stop a case with a clear gap when an expected control or provider response is absent. Use the current app's accessible semantics; never hard-code old snapshot references or disable security. Record every applicable case listed in requirements.json, including unhappy paths. For native device cases use an enrolled test device and its actual screen recording, then import the recording. Keep unknown scope, external dependencies, failed scenarios and deferred VoP evidence visible. Produce INDEX.md, manifest.json, a coverage/gap list, and review notes. Never send evidence to Equals or change production unless the user separately asks.

The Codex scenario provides adaptive navigation; the script handles naming, capture commands, media copying, timestamps, source URLs, source-document hash and file hashes. It deliberately does not auto-click through unknown payment or MFA screens. Once a brand's navigation is stable, persist its generated Playwright actions as a brand-specific adapter and rerun the same assertions. Changes in selectors should fail visibly and be repaired against a fresh snapshot.

## Browser capture commands

Use a supported installed `playwright-cli`, or set `EVIDENCE_PLAYWRIGHT_CLI` to the Playwright skill wrapper. If a pinned local CLI is used, set that variable to `node /absolute/path/to/playwright-cli.js`. Install/update dependencies separately before a capture; do not change tool versions mid-run.

```bash
python3 scripts/evidence/evidence.py init \
  --run output/playwright/equals-evidence/example-staging-release \
  --profile scripts/evidence/example.json \
  --guidance '/path/to/Third Party Programme Manager Guidance.pdf' \
  --build '<actual-release-commit>'
```

`manifest.json` records a unique browser session name. Open the staging URL using that exact session and take a snapshot. For example, the run above uses:

```bash
playwright-cli -s=evidence-example-staging-release open https://YOUR-STAGING-HOST --headed
playwright-cli -s=evidence-example-staging-release snapshot
python3 scripts/evidence/evidence.py video-start \
  --run output/playwright/equals-evidence/example-staging-release \
  --requirement 1.1 --case signup-happy --url https://YOUR-STAGING-HOST
# Perform the complete observed signup journey, using fresh snapshot references.
python3 scripts/evidence/evidence.py video-stop \
  --run output/playwright/equals-evidence/example-staging-release
```

Start recording before entering the flow and stop after the success or blocked outcome is visible. External terms tabs or system dialogs may require a second recording or whole-desktop capture; verify they appear in the final video. Do not use a prompt-only screenshot for a requirement demanding an actual completed factor or video.

```bash
python3 scripts/evidence/evidence.py screenshot \
  --run output/playwright/equals-evidence/example-staging-release \
  --requirement 1.4 --case app-complaints-route \
  --url https://YOUR-STAGING-HOST --note 'Equals complaints route visible in app'

python3 scripts/evidence/evidence.py add \
  --run output/playwright/equals-evidence/example-staging-release \
  --requirement 3.3 --case approval-happy --kind video \
  --file /path/to/enrolled-test-device-recording.mp4 \
  --note 'Actual enrolled staging device; biometric confirmation and result shown'

python3 scripts/evidence/evidence.py report \
  --run output/playwright/equals-evidence/example-staging-release
```

Use the requirement/case names from the catalogue. Add multiple files for a case when it spans messages, device and web surfaces. Each marketing footer needs its own screenshot and URL, even though grouped under one case. Cases ending in `if-supported` or similar require an explicit scope explanation when omitted. The inventory counts captures, not successful assertions, and every imported file starts with review pending.

## Required review before handoff

- **1.1:** independently test missing T&Cs, missing privacy agreement and attempting acceptance before opening T&Cs. For the Hoppa dialog, also show that closing early or failing to load leaves each checkbox locked; show the disabled review button at the top and enabled button at the bottom of both Terms and Privacy. Confirming review must not automatically tick consent. Complete the happy path. Verify server-retained separate consent records, document identity/version and timestamp. Test re-acceptance separately as supporting evidence. Electronic signing needs a retained signed document; the checkbox implementation does not.
- **1.2–1.4:** walk all balance screens, verify exact approved entity/safeguarding copy and terms link; capture every relevant marketing footer plus URL and marketing-review confirmation; show both complaints routes. Marketing evidence cannot be inferred from the Flutter app.
- **2.1–2.3:** show pre-signup tariff and corporate written schedule when applicable; record an actual fee/FX authorization and resulting activity; demonstrate a provider-side balance change. Attach reconciliation design for derived balances. Mocked balance changes are rehearsal only.
- **3.1–3.3:** enumerate every protected event and supported challenge scenario, capture actual correct and rejected factors, received messages/templates, and maker/checker where offered. Device enrolment, biometric/passcode and lock-screen cases need the actual enrolled device. Never show a real reusable password, production OTP, production PAN or CVV. Use sandbox data and inspect the video before sharing.
- **3.4–3.5:** excluded for Hoppa's current Equals scope. Re-enable if Equals cards are introduced.
- **4.1–4.3:** cover match, close match, no match and unavailable; show explicit acknowledgement and blocked paths for close/no match. Preserve acknowledgement records. Batch opt-out is corporate-only and reversible. Track the supplied VoP deferral separately from technical implementation readiness.

For each applicable row, a reviewer checks the recorded media against the catalogue and documents pass/fail, missing cases and supporting records. Check `manifest.json` hashes after copying the package. Raw captures remain local and ignored by Git; do not commit recordings, session state or credentials. Tests of this collector and local rehearsals are never provider evidence. Capture with staging/provider connectivity is intentionally deferred until the test environment and accounts are ready.
