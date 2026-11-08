# Spikes

Spikes S1–S7 answer the questions in the M1 table of
[DEV-PLAN.md](../DEV-PLAN.md#m1-spikes). A spike does not ship product features:
its output is a report in this folder plus reusable verification code in Clove
Lab and the `CloveSpikes` package.

S0 built the harness every spike uses. A spike adds files only in its own
folders:

```text
CloveLab/Spikes/Sx/                       the spike's screens
Packages/CloveSpikes/Sources/SpikeSxName/ the spike's verification code
Packages/CloveSpikes/Tests/SpikeSxNameTests/
docs/spikes/Sx-name.md                    the report
```

Shared files — `CloveLab/LabRootView.swift`, `CloveLab/Experiments.swift`,
`CloveLab/Shared/`, `Packages/CloveSpikes/Sources/SpikeSupport/`,
`project.yml`, `mise.toml` — are not edited by a spike. If a spike needs a
shared change, open an issue for it instead.

## The harness

Clove Lab lists all seven spikes; each opens its own screen. The shared pieces:

- `SpikeSupport.LabReport` and `LabDevice` / `LabApp` / `LabMeasurement`: the
  report a spike writes.
- `SpikeSupport.Stopwatch`: timing on `ContinuousClock`, never the wall clock.
- `SpikeSupport.Fixtures`: resolves the fixture sets in the shared cache; tests
  skip when a set is missing.
- `CloveLab/Shared/FolderPicker.swift`: the system folder picker, plus
  `FolderPickerButton`.
- `CloveLab/Shared/SecurityScopedAccess.swift`: holds access to a picked folder
  for the duration of a closure.
- `CloveLab/Shared/ReportExporter.swift`: writes
  `clove-lab-<spike>-<UTC timestamp>.json` into the tested folder and into the
  app's Documents folder.
- `CloveLab/Shared/LabSession.swift`: the last exported report, shared with the
  footer.
- `CloveLab/Shared/DeviceReportFooter.swift`: names the last report and offers it
  through the share sheet. On a fresh install it writes a device report
  (`S0`) so the export path can be checked before a spike exists.

Clove Lab sets `UIFileSharingEnabled` and `LSSupportsOpeningDocumentsInPlace`, so
the Documents copies appear in Files under "On My iPhone › Clove Lab", and the
share sheet can send them back.

Clove Lab writes its reports on device; the tests in
`Packages/CloveSpikes/Tests/` run on the Mac with `mise run test-spikes`.

## Report schema

Every spike writes one JSON file per run. The file name is
`clove-lab-<spike>-<UTC timestamp>.json`, for example
`clove-lab-S2-20261113T101530Z.json`.

```json
{
  "app" : {
    "build" : "1",
    "bundleIdentifier" : "com.mimiqdev.clove.lab",
    "version" : "0.1.0"
  },
  "context" : {
    "fileSystem" : "exFAT",
    "volume" : "EOS_DIGITAL"
  },
  "createdAt" : "2026-11-13T10:15:30Z",
  "device" : {
    "modelIdentifier" : "iPhone18,2",
    "systemName" : "iOS",
    "systemVersion" : "27.2"
  },
  "measurements" : [
    {
      "name" : "embedded-preview-extraction",
      "tags" : {
        "format" : "CR3"
      },
      "unit" : "ms",
      "value" : 128.4
    }
  ],
  "notes" : [
    "Reported from Clove Lab."
  ],
  "schemaVersion" : 1,
  "spike" : "S2"
}
```

| Key | Type | Meaning |
| --- | --- | --- |
| `schemaVersion` | number | `1` for this schema; changes when a field does. |
| `spike` | string | Spike identifier, `S1`–`S7`. |
| `createdAt` | string | ISO 8601 UTC instant the report was produced. |
| `device.modelIdentifier` | string | Hardware model, for example `iPhone18,2`. |
| `device.systemName` | string | `iOS`. |
| `device.systemVersion` | string | `27.2`. |
| `app.bundleIdentifier` | string | `com.mimiqdev.clove.lab`. |
| `app.version` | string | `CFBundleShortVersionString`. |
| `app.build` | string | `CFBundleVersion`. |
| `context` | object of strings | What was tested, for example the volume's file system. |
| `measurements` | array | One entry per measurement; may be empty. |
| `measurements[].name` | string | What was measured. |
| `measurements[].value` | number | The value, in `unit`. |
| `measurements[].unit` | string | `ms`, `bytes`, `count`, … |
| `measurements[].tags` | object of strings | Extra labels, for example the format or the file. |
| `notes` | array of strings | Free-form observations; may be empty. |

The encoder is in `LabReport.makeEncoder()`: pretty printed, sorted keys, ISO
8601 UTC dates. `mise run test-spikes` checks the key names against this table,
so the two change together.

## The spike report

Write `docs/spikes/Sx-name.md`, in the same order as this template:

```markdown
# Sx — <question from the plan>

## Question

<The spike's question, as written in DEV-PLAN.md.>

## What was tested

<Devices (model, iOS version), what volume or fixture set, and the files.
Name the fixture sets from docs/fixtures.md and the report file names.>

## Data

<Tables of the measurements from the JSON reports. One table per question, with
the device and conditions in the caption. Note anything that failed.>

## Conclusion

<What the data shows, in a sentence or two. Say when the data is inconclusive.>

## Recommendation and options for G1

<The recommended approach, then the alternatives and what each would cost.
State performance targets when the spike sets them. This is the part the
product owner decides on at G1.>

## Open questions

<Anything the spike could not settle, and what would settle it.>
```

Keep the JSON reports out of git: attach them to the issue instead, and quote
the numbers in the report.

## Device checklists

Tasks labeled `device` end with a checklist the product owner runs on hardware
the agents do not have. Write it into the pull request's "Device checklist"
section, and keep it in the spike report:

- Numbered steps naming the screen and the fixture or volume.
- What to expect after each step, so a mismatch is recognizable without the
  code.
- The last step: the on-screen report file name, and "attach the JSON file to
  the issue". Reports also appear in Files under "On My iPhone › Clove Lab", or
  go through the footer's Export button.
- The devices and OS versions to repeat the checklist on.

The supervisor uploads a Clove Lab build to TestFlight after the pull request
merges; the product owner runs the checklist and puts the JSON back on the
issue.
