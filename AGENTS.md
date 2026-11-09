# Agent notes (Clove)

This file is for coding agents working in this repository. The process — roles,
issue-to-PR handoff, report format, and who merges — lives in
[docs/AGENT-WORKFLOW.md](docs/AGENT-WORKFLOW.md). The plan and product scope live
in [docs/DEV-PLAN.md](docs/DEV-PLAN.md) and [docs/PRD.en.md](docs/PRD.en.md).

## Layout

```text
Clove/                    Clove app target (SwiftUI, placeholder UI for now)
CloveLab/                 CloveLab debug app target used for device verification
CloveLab/Shared/          Harness for the spikes: folder picker, report export, footer
CloveLab/Probes/<Topic>/  One folder per verification topic
CloveUITests/             UI smoke test for Clove
Packages/CloveCore/       Domain model, scanning, XMP, writes (local Swift package)
Packages/CloveImaging/    Previews, RAW decoding, image features (local Swift package)
Packages/CloveLabKit/     Lab report tooling plus one module per verification topic
Config/Shared.xcconfig    Shared build settings; includes Local.xcconfig if present
Config/Local.xcconfig     Local development team, gitignored, never committed
Config/TestFlight.local.json  Local signing config for the release script, gitignored
scripts/                  Project generation, simulator smoke test, fixture and release tooling
project.yml               XcodeGen definition; Clove.xcodeproj is generated, not committed
mise.toml / mise.lock     Pinned tools and project tasks
```

## Tasks

Run project commands with `mise run <task>`; `mise install` installs the pinned
XcodeGen. Every task is listed here.

| Task | What it does | When to run |
| --- | --- | --- |
| `mise run generate` | Runs `scripts/generate-xcodeproj.sh` (`xcodegen generate`) and writes `Clove.xcodeproj`. | After changing `project.yml`, adding sources, or changing packages. |
| `mise run lint` | `swift format lint --strict` over `Clove`, `CloveLab`, `CloveUITests`, and `Packages`. | Before every commit. |
| `mise run format` | The same swift-format rules, applied in place. | To fix lint findings. |
| `mise run test-fixtures` | `scripts/test_fixtures.py`: fixture tooling tests, logic only, no network. | After changing anything under `fixtures/` or the fixture scripts. |
| `mise run test-release` | `scripts/test_release_testflight.py`: TestFlight release script tests, logic only, no network, no signing. | After changing the release script or its config. |
| `mise run release` | `scripts/release-testflight.py`: archives, signs, validates, and with `--upload` uploads one app to TestFlight (`docs/release.md`). | To check a TestFlight build; the supervisor uploads after merge. |
| `mise run fixtures-fetch` | `scripts/fetch-fixtures`: downloads and verifies the pinned fixtures into the shared cache (`docs/fixtures.md`). | Once per machine, and after `fixtures/manifest.json` changes. |
| `mise run fixtures-sets` | Runs `fixtures-fetch`, then `scripts/make-fixture-sets` to rebuild the standard test folders in the cache. | Before tests that read the fixture sets. |
| `mise run test-core` | `swift test --package-path Packages/CloveCore`. | While editing `CloveCore`; runs on macOS, no simulator. |
| `mise run test-imaging` | `swift test --package-path Packages/CloveImaging`. | While editing `CloveImaging`; runs on macOS, no simulator. |
| `mise run test-lab` | `swift test --package-path Packages/CloveLabKit`: the lab harness and probe test targets. Fixture tests skip when a set is missing. | While editing `Packages/CloveLabKit`; runs on macOS, no simulator. |
| `mise run build` | `xcodebuild build` for the `Clove` and `CloveLab` schemes, iOS Simulator, no signing. | After project, app, or package changes. |
| `mise run smoke` | Creates a throwaway simulator, runs `CloveUITests` with `xcodebuild test`, deletes the simulator on exit. | After changing UI or the smoke test, and as part of verify. |
| `mise run verify` | `generate`, `lint`, `test-fixtures`, `test-release`, `test-core`, `test-imaging`, `test-lab`, `build`, `smoke`, in order, stopping at the first failure. | Before opening or updating a pull request; it is the acceptance gate. |

## Conventions

- Name code by what it does, never by a stage of the development plan. Plan IDs
  (S1–S7, M0–M6, G1–G3, C7, I2, T0.1) and words such as "wave", "part 1", or
  "spike" belong in docs, issues, branches, PR titles, and commit messages, not
  file or folder names, modules, types, test names, environment variables,
  compile flags, or accessibility identifiers. Keep the documented report IDs,
  export file names, checklist labels, and lab XMP namespace stable.
- Logic leaving the lab is rewritten into `CloveCore` or `CloveImaging` under a
  domain name with its own tests. `Clove` never depends on `CloveLabKit`.
- Swift 6 language mode with complete strict concurrency checking. Fix
  concurrency warnings rather than weakening the build settings.
- The packages use Swift Testing (`import Testing`, `#expect`). App targets use
  SwiftUI; the UI test target uses XCTest.
- No third-party dependencies without a decision record in `docs/decisions/`.
- Build UI with system components until the visual design arrives. Placeholders
  exist only to keep the skeleton verifiable.
- Keep the generated project out of git. Never edit `Clove.xcodeproj` by hand;
  change `project.yml` and regenerate.
- `Clove.xcodeproj` and build products are gitignored, so `git status` must stay
  clean after `mise run verify`.

## Build output and simulators

- Build output goes inside the checkout: `.build/DerivedData.noindex`, passed
  with `-derivedDataPath`. The `.noindex` suffix keeps Spotlight from indexing
  build products. Do not use the default DerivedData location or `/tmp`.
- Never reuse or boot an existing simulator for automation. `scripts/smoke.sh`
  creates its own `Clove smoke <tag>` device, tags it with `CLOVE_SIM_TAG` or the
  branch name plus PID, and always deletes it with `trap` — including on failure.
  `CLOVE_SIM_DEVICE_TYPE` and `CLOVE_SIM_RUNTIME` override the defaults
  (iPhone 17 Pro on the newest installed iOS runtime). If the UI test runner
  fails to attach before any test runs (an XCTest/simulator bootstrap failure),
  the script retries on a fresh simulator; `CLOVE_SMOKE_ATTEMPTS` changes the
  attempt count (default 4). Real assertion failures fail immediately.

## Secrets and signing

- Nothing from `~/.config/apple/` may be printed, copied, or committed — not in
  the repository, a log, an issue, or a pull request.
- The development team lives only in gitignored `Config/Local.xcconfig`, pulled
  in by the optional `#include? "Local.xcconfig"` in `Config/Shared.xcconfig`.
  Create it from `Config/Local.xcconfig.example`. Never write a team ID into a
  tracked file.
- Builds and simulator tests need no signing setup. `mise run build` passes
  `CODE_SIGNING_ALLOWED=NO`.

## TestFlight

- `mise run release -- --app clove|lab` archives, signs with the distribution
  certificate, exports, and validates an App Store build; add `--upload` to
  publish it to TestFlight. Full instructions, preconditions, and behavior are
  in [docs/release.md](docs/release.md).
- The config (`Config/TestFlight.local.json`, from the committed example) is
  gitignored and readable by this user only. It points at the signing files in
  `~/.config/apple/`; those never enter the checkout, a log, or a pull request.
  The script redacts key IDs, issuer IDs, passwords, and tokens from its output.
- Artifacts and logs stay in `.build/testflight/<app>/`; the temporary keychain
  and the temporary profile copy are removed on every exit path.
- Upload only when the task or the supervisor says so. Clove Lab builds go to
  the internal `Clove Lab Internal` group for device verification.
- Replace the placeholder app icons in `Clove/Assets.xcassets` and
  `CloveLab/Assets.xcassets` when the visual design lands; keep the icon setting
  and the App Store plist keys in `project.yml`.
