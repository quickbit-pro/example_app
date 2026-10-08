# Public example template

All shared UI components, file paths, test fixtures, browser bridges and cache
keys use neutral `Example` / `example` names. The full banking layout is selected
with `design.layout: "example"`. Existing sample configurations and customer
branding tools use this identifier consistently.

The template includes no proprietary logo geometry or logo-generation scripts.
Artwork uses the configured customer logo and app name; missing logos fall back
to customer initials. Loaders support customer logos or standard circular
progress indicators. Screenshots and the embedded offline guide were rebuilt.

This public snapshot starts a new, single-commit history. Clone the repository
afresh instead of merging a checkout based on its previous history.

## Validation

- Backend: 870 passed, 18 optional integration tests skipped.
- Admin/MOR production builds passed; 89 admin tests passed.
- Guide/browser checks: 87 Node tests and 41 Python tests passed.
- Flutter analysis: no errors or warnings; three pre-existing informational lints.
- Updated dashboard and activation screenshots: 18 tests passed.
- Flutter full-suite run identified the previously documented 27 remaining
  translation, assistant-expectation, transaction-layout and money-dialog failures.
  Two route-loader expectations were then adapted to the neutral artwork and
  verified with the focused branding suite (41 passed).
- Offline guide release build passed. Public file paths, source, binary assets,
  and the built preview were scanned for the removed product name.
- Bill-splitting and credential export checks passed.
