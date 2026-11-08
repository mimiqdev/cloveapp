# TestFlight release

`scripts/release-testflight.py` archives, signs, validates, and — with
`--upload` — uploads either app to TestFlight from the Mac mini. Run it through
mise so XcodeGen is on `PATH`:

```sh
mise run release -- --app lab                 # Clove Lab, validate only
mise run release -- --app clove               # Clove, validate only
mise run release -- --app lab --upload        # Clove Lab, publish
mise run release -- --config ~/.config/apple/clove-testflight.json --app clove
```

`--app clove|lab` selects the scheme, bundle ID, and App Store profile:

| App | Scheme | Bundle ID | TestFlight |
| --- | --- | --- | --- |
| `clove` | `Clove` | `com.mimiqdev.clove` | internal now, external after G3 |
| `lab` | `CloveLab` | `com.mimiqdev.clove.lab` | internal only |

The configuration is read from `--config`, then `$CLOVE_TESTFLIGHT_CONFIG`, then
`Config/TestFlight.local.json`. Copy
[`Config/TestFlight.local.json.example`](../Config/TestFlight.local.json.example),
point it at the signing files in `~/.config/apple/`, and keep it out of git (it
is already gitignored):

```sh
install -m 600 /dev/null Config/TestFlight.local.json   # then edit it
```

The config names the App Store Connect key (`apiKeyId`, `issuerId`,
`apiKeyPath`), the distribution certificate (`distributionP12Path`,
`distributionP12PasswordFile`), one App Store profile per app
(`appStoreProfiles`), and optionally the internal group to check for Clove Lab
(`betaGroup`, default `Clove Lab Internal`).

Never print, copy, or commit the config, the key ID, the issuer ID, the API key,
the distribution password, or the generated token. The script registers those
values and redacts them from its own output, including failing `xcodebuild` and
`altool` logs.

## What a run does

1. Refuses a dirty worktree when `--upload` is set, before anything is built.
2. Regenerates `Clove.xcodeproj` with `scripts/generate-xcodeproj.sh`.
3. Reads the marketing version from the Xcode build settings and computes the
   build number: UTC `yymmddhh`, which must be strictly greater than every build
   already visible in App Store Connect for that app and marketing version. One
   build per UTC hour; a second run in the same hour fails until the clock
   advances. The number is passed as `CURRENT_PROJECT_VERSION`.
4. Looks up the App Store Connect app, and for `--app lab` the
   `Clove Lab Internal` beta group (config key `betaGroup`). A missing group
   fails here, before archiving.
5. Imports the distribution certificate into a temporary keychain, installs the
   App Store profile for this run, and archives Release into
   `.build/testflight/<app>/` inside the checkout.
6. Exports a signed IPA with `ExportOptions.plist` (manual signing, Apple
   Distribution certificate, App Store profile) and verifies it: bundle ID,
   marketing version, build number, export-compliance declaration, the local
   Apple Distribution signature and team, and the embedded profile.
7. Runs `xcrun altool --validate-app`, and with `--upload` also
   `xcrun altool --upload-app`.

The temporary keychain is deleted and the user keychain search list restored on
every exit path, success or failure; the temporary profile copy is removed too.
Archive, IPA, and logs stay in `.build/testflight/<app>/` (`archive.log`,
`export.log`, `validate.log`, `upload.log`).

## Preconditions

- `~/.config/apple/` holds the App Store Connect API key, the distribution
  `.p12` and its password file, and one App Store profile per app. These are
  the only places signing material lives.
- The config and its secret files are readable by this user only
  (`chmod 600`); the script refuses anything else. Profiles may be `644`.
- Both bundle IDs exist in App Store Connect and have an App Store distribution
  profile that matches the distribution certificate.
- The `Clove Lab Internal` group exists on the Clove Lab app, is internal, and
  receives all builds. Clove Lab is used for the device-verification loop in
  [DEV-PLAN.md](DEV-PLAN.md#real-device-verification); internal builds need no
  review.

## Tests

`mise run test-release` runs `scripts/test_release_testflight.py`: build-number
arithmetic, config parsing and validation, app selection, the dirty-tree check,
IPA verification on a synthetic IPA, and beta-group and build lookups on canned
App Store Connect JSON. No network, no signing, no `xcodebuild`. It is part of
`mise run verify`.

## Placeholder release assets

The app icon is a plain 1024×1024 colored square in each app's
`Assets.xcassets`, and `project.yml` declares
`ITSAppUsesNonExemptEncryption = NO` plus all four iPad orientations, which App
Store validation requires. Replace the icons when the visual design lands; keep
the catalog and the build settings.
