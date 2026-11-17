# TLA+ for browsing workflow verification

Status: implemented, 2026-11-17.

## Decision

Clove uses TLA+ tools 1.7.4 as a development-only model checker for the browsing workflow. The
project-local `browsing-workflow` skill downloads the tool into the gitignored
`.build/formal-verification/tools/` directory. TLA+ is not an app, Swift package, or CI dependency.
No third-party source or binary is committed.

The runner uses Python's standard library and Java 11 or later. It selects `JAVA` when set, then
`java@temurin-25.0.5+8.0.LTS` through mise, then `java` on `PATH`. The verification machine used
Temurin 25.0.5 and TLC2 2.19 revision 5a47802. The optional `statechart` skill reads the same model
and counterexamples on hosts that provide it; it is not required by the runner.

## Why a model checker

The workflow's risk comes from action order. Navigation, marking, delayed auto-advance, folder
replacement, and location loss share state, but unit tests exercise selected sequences. TLC checks
every enabled sequence in a stated small world and returns the shortest path to a violated rule.
The existing Swift tests remain the checks of the implementation. The TLA+ model checks its design
at a bounded depth and does not prove that SwiftUI executes the model.

## Reproduce the tool and the check

Run this command from the repository root:

```sh
.agents/skills/browsing-workflow/scripts/check
```

On the first run, the script downloads:

```text
https://github.com/tlaplus/tlaplus/releases/download/v1.7.4/tla2tools.jar
SHA-256: 936a262061c914694dfd669a543be24573c45d5aa0ff20a8b96b23d01e050e88
```

The checksum identifies the pinned upstream release. The script also runs TLC, which verifies that
the downloaded tool works. TLC runs with one worker, fingerprint seed 0, and `-lncheck final`. The
configuration declares safety invariants only and disables deadlock checking because the depth
bound creates terminal states. Generated specifications, logs, and state queues stay under
`.build/formal-verification/`.
