# Clove

A native iPhone and iPad photo culling app for RAW and JPEG files on SD cards
and external drives. Clove is built with SwiftUI and Swift 6, with the domain
engine in `CloveCore` and the imaging pipeline in `CloveImaging`.

This repository is at the skeleton stage: the apps show placeholders, and the
build, test, lint, and simulator smoke-test pipeline is in place.

## Quick start

```sh
mise install                 # installs the pinned XcodeGen
mise run check               # generate, lint, core and imaging tests, smoke test
```

Useful day-to-day commands:

```sh
mise run generate            # write Clove.xcodeproj, then open it in Xcode
mise run test-core           # CloveCore tests, on macOS
mise run test-imaging        # CloveImaging tests, on macOS
mise run build               # build Clove and CloveLab for the simulator
mise run smoke               # app unit tests and the UI smoke test on a throwaway simulator
mise run ui-flows            # the long UI flow tests on a throwaway simulator
mise run verify              # the full gate that CI runs on every pull request
```

Requirements: Xcode 27 or later on macOS, and [mise](https://mise.jdx.dev).
No signing setup is needed for any of these, or for CI (`.github/workflows/verify.yml`).

To run on a device, copy `Config/Local.xcconfig.example` to
`Config/Local.xcconfig` and set `DEVELOPMENT_TEAM` there. That file is
gitignored; never commit a team ID.

For conventions, the task table, and agent rules, see [AGENTS.md](AGENTS.md).
The development process is in [docs/AGENT-WORKFLOW.md](docs/AGENT-WORKFLOW.md),
and the plan and product requirements are in [docs/DEV-PLAN.md](docs/DEV-PLAN.md)
and [docs/PRD.en.md](docs/PRD.en.md).
