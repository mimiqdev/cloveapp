# focusmeta for camera AF regions

Status: implemented, 2026-11-13. Task: [#238](https://github.com/mimiqdev/cloveapp/issues/238).

## Decision

Clove reads camera AF regions through the first-party
[mimiqdev/focusmeta](https://github.com/mimiqdev/focusmeta) library (MIT), vendored as a git
subtree at `Packages/CloveFocusMetadata` from `main` d670181. The integration is additive:
`AutofocusMetadataReader` keeps its proven ImageIO paths (`{ExifAux}.AFInfo` for Fuji and
Panasonic, `{Exif}.SubjectArea` for Apple) untouched, and consults focusmeta only after both
paths report missing — the Sony case, whose AF records live in private maker notes ImageIO
never exposes. focusmeta's `displayGeometry` (already rotated into display space) maps
directly into the display-space `NormalizedRegion`; Clove's orientation map is deliberately
not applied again, which synthetic orientation-agreement tests pin down for all eight EXIF
orientations. Any absence of geometry — including every vendor whose pixel semantics
focusmeta does not verify — surfaces through the existing `AutofocusMetadataEvidence` path
(#208 contract), never as silence and never as a guessed region.

## Why vendoring (a subtree) rather than a pinned remote dependency

- AGENTS.md admits third-party dependencies only with a decision record; focusmeta is
  first-party MIT, and this document is that record either way.
- The repository has no remote package dependencies today; every `Packages/` entry is local.
  A local path keeps Clove's builds offline-reproducible and keeps CI (which checks out the
  pull request head with `persist-credentials: false`) free of an external fetch.
- Both repositories move together: focusmeta's verified scope grows from Clove's sample
  handoffs, so a subtree pull (`git subtree pull --prefix Packages/CloveFocusMetadata
  focusmeta main --squash`) is the natural update path and preserves upstream history
  linkage through the squash commits.
- The vendored sources and tests are formatted to Clove's `.swift-format` on import (two
  mechanical diffs: wrapped one force-unwrap in `Geometry.swift`; reflowed long lines and
  added trailing commas in the vendored tests). The vendored test suite still runs green
  under `swift test --package-path Packages/CloveFocusMetadata`, and its private-sample
  integration suite skips when `CAMERA_FOCUS_METADATA_SAMPLES_DIR` is unset.

If focusmeta later gains releases used by other clients, revisit with a tagged
`from:` dependency; nothing in the bridge depends on the vendoring choice — only on
focusmeta's public API.

## Integration notes

- `CloveImaging` depends on the package by path; the app targets link it transitively and
  need no `project.yml` change.
- The fallback runs inside the analyzer's metadata stage on the image-work executor, so the
  bounded synchronous file read never lands on the main actor and shares the stage's
  admission slot with the ImageIO read (#216 budgets unchanged).
- focusmeta returns no region for geometry it cannot verify; the bridge reports the Sony
  read itself as an inspected path (e.g. `focusmeta.SonyMakerNote ILCE-1M2`) with the
  library's conclusion, or a vendor-named `focusmeta.<vendor>MakerNote` entry for other
  makers, so the evidence path stays meaningful for every camera.
- A located point with no recorded region extent is presented with a small box (3% of the
  frame edge) centered on the recorded point; the sharpness scorer reports `regionTooSmall`
  for such regions rather than hiding them.
- Verification: synthetic ARW/HIF/JPEG containers built in
  `SyntheticSonyContainers.swift` exercise the whole route (file read, Sony maker-note
  parse, display rotation, mapping) without any private sample entering the repository; the
  private ILCE-1M2 samples S01–S04 are validated on the Mac before merge and recorded as
  sanitized positions in the pull request.
