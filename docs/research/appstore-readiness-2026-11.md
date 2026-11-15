# Clove App Store Submission & In-App Purchase Readiness Report

- **Date:** 2026-11-15
- **Baseline revision:** `1b3a533` (`main` / `research/appstore-readiness`)
- **Scope:** Public App Store submission readiness for `Clove` (`com.mimiqdev.clove`) and technical/account/review analysis for enabling In-App Purchase (IAP) monetization (one-time unlock, subscription, or both).
- **Method:** Static audit of `project.yml`, `Config/`, `scripts/release-testflight.py`, `Clove/`, `CloveLab/`, `Packages/`, `design/`, and `docs/`, plus non-secret local signing presence checks on the Mac mini. Anything requiring live App Store Connect (ASC) portal access or secret inspection is explicitly marked **`UNVERIFIED`** with the exact verification step.

---

## Executive Summary

- **Technical & signing foundation is already strong:** `Clove` (`com.mimiqdev.clove`) builds for iOS 18.0+ (iPhone and iPad, `TARGETED_DEVICE_FAMILY: "1,2"`), guards iOS 26+ Liquid Glass and iOS 27.1+ iPhone Duo APIs behind `#available` checks, uses only public Apple frameworks plus the first-party MIT `CloveFocusMetadata` parser, declares `ITSAppUsesNonExemptEncryption = NO` (standard `CryptoKit.SHA256` hashing only), ships a valid `Clove/PrivacyInfo.xcprivacy`, and already has an automated Apple Distribution signing/validation/upload pipeline in `scripts/release-testflight.py`.
- **What blocks public App Store submission today (Part A):** Mostly **App Store Connect & Review assets**, not architecture—specifically: (1) ASC listing metadata, Privacy Policy URL, and Support URL (none exist in the app or repo); (2) App Store Connect screenshots for 6.9"/6.7" iPhone and 13" iPad; (3) verifying the live `com.mimiqdev.clove` ASC record and whether marketing version `0.1.0` should be bumped to `1.0.0`; and (4) optional/recommended polish such as an About/Privacy/Support/Licenses section in Settings (which also surfaces the `Packages/CloveFocusMetadata/LICENSE` MIT notice inside the distributed binary). Note: contrary to stale comments in `AGENTS.md` and `docs/release.md`, `Clove`'s real "Split print" app icons (`1024×1024`, no alpha, Default/Dark/Tinted) are **already landed** in `Clove/Assets.xcassets/AppIcon.appiconset/`.
- **What is required for IAP monetization (Part B):** Owner completion of the **Paid Applications Agreement** (banking & tax forms) in App Store Connect, creation of IAP product IDs / subscription group, adding the **In-App Purchase capability** to the `com.mimiqdev.clove` App ID (and regenerating the `clove` App Store provisioning profile), and **~3–5 engineering days** for an **on-device StoreKit 2** integration (`PurchaseStore`, paywall UI with mandatory Restore Purchases + auto-renewal/legal disclosures, and feature gating). StoreKit 2 on-device verification fits Clove's offline, zero-account architecture far better than a server-backed subscription stack (~7–12+ days).

---

## Part A — App Store Submission Readiness

### 1. App Identity & Metadata

| Item | Current Repo / Local State | Missing / Action Needed |
| --- | --- | --- |
| **Bundle ID** | Verified `com.mimiqdev.clove` in `project.yml` (`line 51`), `scripts/release-testflight.py` (`line 57`), and `docs/release.md` (`line 18`). `CloveLab` uses a separate bundle ID `com.mimiqdev.clove.lab` (`project.yml:81`). | None. |
| **App record in App Store Connect** | `docs/DEV-PLAN.md` (`line 35`) and `docs/release.md` (`line 76`) state `com.mimiqdev.clove` is registered with an App Store Connect app record. `scripts/release-testflight.py` (`lookup_app`, `lines 211–223`) requires an exact bundle ID match in ASC. | **`UNVERIFIED`** — Live ASC record state, app name availability, primary language, and whether any `Clove` (non-Lab) build has been uploaded to ASC/TestFlight require owner ASC login or running `mise run release -- --app clove` on the Mac mini. |
| **Version & build strategy** | `project.yml` (`lines 22–23`) sets `MARKETING_VERSION: "0.1.0"` and `CURRENT_PROJECT_VERSION: "1"`. At archive time, `scripts/release-testflight.py` (`next_build_number`, `lines 263–277`) passes `MARKETING_VERSION` and overrides `CURRENT_PROJECT_VERSION` with UTC `yymmddhh` (`%y%m%d%H`), refusing to build unless strictly greater than every ASC build visible for that marketing version. | Decide whether public v1 launches as `0.1.0` or bumps `MARKETING_VERSION` to `1.0.0` in `project.yml` (owner decision). Note: `next_build_number` restricts uploads to at most 1 build per UTC hour per marketing version. |
| **ASC store listing metadata** | Draft TestFlight beta description and reviewer notes exist in `docs/testflight-external.md`, and App Store display name is `Clove` (`project.yml:53`). | Missing in ASC (**`UNVERIFIED`**): App Store Subtitle (≤30 chars), Promotional Text, Description, Keywords (≤100 chars), Primary Category (e.g., *Photo & Video*), Copyright string, Age Rating questionnaire, Pricing & Territory availability, and App Privacy questionnaire responses. |

---

### 2. Review Assets

| Asset | Current State (Verified) | Missing / Action Needed |
| --- | --- | --- |
| **App Icon** | **Already replaced for `Clove`.** Commit `01d03ba` landed the designed "Split print" icon in `Clove/Assets.xcassets/AppIcon.appiconset/` (`AppIcon.png`, `AppIcon-Dark.png`, `AppIcon-Tinted.png`; verified `1024×1024` RGB PNGs with `hasAlpha: no` via `sips`). Note: `AGENTS.md` (`lines 204–205`) and `docs/release.md` (`line 93`) still inaccurately state `Clove` has a placeholder icon; only `CloveLab/Assets.xcassets/AppIcon.appiconset/AppIcon.png` is still a solid blue placeholder square. (`design/app-icon/layers/` also provides Icon Composer SVGs/PNGs if a layered `.icon` is desired later.) | None required for App Store validation (`Clove`'s catalog icons pass Xcode/ASC rules). Optionally update stale wording in `AGENTS.md` and `docs/release.md`. |
| **App Store Screenshots** | `project.yml` (`line 21`) sets `TARGETED_DEVICE_FAMILY: "1,2"` (Universal iPhone + iPad). `design/handoff/screens/` contains design handoff mockups, not App Store Connect submission screenshots. | **Missing.** ASC requires screenshots for **6.9" (or 6.7") iPhone** and **13" (or 12.9") iPad** displays (up to 10 per size class). ASC automatically scales these down to smaller iPhone/iPad sizes unless custom screenshots are supplied. Verify in ASC whether any iOS 27 Duo-specific screenshot slot exists when submitting. |
| **App Preview Video** | None in repo. | **Optional**, not required. Recommended for a gesture-driven photo culling app (demonstrating swipe-distance rating, double-tap 100% zoom, and in-group culling). |
| **Privacy Policy URL** | **Missing.** Grep across `Clove/` and `Packages/` found zero `http(s)` or `mailto:` URLs in app UI/code. | **Required** by ASC for all public App Store apps (App Review Guideline 5.1.1). Host a static Privacy Policy page and enter its URL in ASC (and optionally link it inside Settings). |
| **Support URL** | **Missing.** `docs/testflight-external.md` (`line 33`) still has `<FEEDBACK_EMAIL>`. | **Required** by ASC for public submission. Host a simple support page or contact form/mailto page and enter its URL in ASC. |
| **Marketing URL** | **Missing.** | **Optional** in ASC (can reuse the Clove landing page or repo/site URL if desired). |
| **Localized Metadata** | App UI copy is **English-only**: `design/handoff/copy.md` defines English sentence-case strings (with SwiftUI inflected plurals), strings in `Clove/` are hardcoded English literals, and zero `.xcstrings` or `.lproj` files exist in `Clove/`. (`docs/PRD.zh-CN.md` is internal product documentation only.) | Set ASC primary localization to `English (U.S.)` (or `en-GB`—note `Clove` code uses mixed US/UK spelling in a few comments/symbols while UI copy in `design/handoff/copy.md` uses US `"color"`). No `.xcstrings` work is required for an English-only launch, though extracting strings to String Catalogs will be needed if adding Simplified Chinese or other locales later. |

---

### 3. Technical Requirements

| Requirement | Verified Repo State | Gap / Risk |
| --- | --- | --- |
| **Minimum iOS & API guards** | `IPHONEOS_DEPLOYMENT_TARGET: "18.0"` in `project.yml` (`lines 8, 20, 39`) and `.iOS(.v18)` in all three local Swift packages (`CloveCore`, `CloveImaging`, `CloveFocusMetadata`). Newer OS APIs are guarded: `#available(iOS 26.0, *)` for Liquid Glass (`Clove/Design/GlassStyle.swift:15`, falling back to `.ultraThinMaterial`) and `#available(iOS 27.1, *)` for Duo system toolbars/division regions/split arrangements (`Clove/Browsing/DuoLayout.swift`, `Clove/Browsing/GridScreen.swift:172`, `Clove/Detail/DetailMarkingView.swift`, `Clove/Detail/DuoMarkControls.swift`). | None. Verify CI/release builds link against the Xcode 27.x SDK so `@available(iOS 27.1, *)` symbols compile cleanly (confirmed in `AGENTS.md:93` — Xcode 27.2). |
| **Device capabilities & Duo safety** | `project.yml` sets `TARGETED_DEVICE_FAMILY: "1,2"`, `SUPPORTS_MACCATALYST: "NO"`, and declares no `UIRequiredDeviceCapabilities` restrictions. On `< iOS 27.1`, `DuoLayout` leaves `isDuoExpanded = false`, `isDuoCover = false`, and `usesSystemBrowsingToolbar = false`. On `>= iOS 27.1`, `SystemBrowsingLayout` (`DuoLayout.swift:17–33`) activates Duo mode only when `toolbarVerticalEdge != nil` or `reservedRegions(kind: .division, options: .includeInactive)` is non-empty, and `BrowseShell` (`BrowseShell.swift:17–39`) falls back to normal compact iPhone (`GridScreen`) or regular iPad (`NavigationSplitView`) layouts. | Low risk: confirm in ASC **Pricing and Availability** whether "Make this app available on Mac (Apple Silicon)" should be unchecked if "Designed for iPad" has not been tested on macOS. Also smoke-test an archive on a non-Duo physical iPhone/iPad running iOS 18–27. |
| **Background modes** | No `UIBackgroundModes` declared in `project.yml` or any `Info.plist` for `Clove`. `RootView.swift:95–97` triggers `browsing.recordEntryProgress()` on `.background`. | None required. (If future releases need guaranteed completion of long XMP batch writes or Move Rejects when backgrounded, `UIApplication.beginBackgroundTask` can be added without a `UIBackgroundModes` key.) |
| **File access & entitlements** | No `.entitlements` file exists for `Clove`. `Clove/Folder/FolderPicker.swift:20–25` uses `UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)`. `Packages/CloveCore/Sources/CloveCore/FolderAccess/FolderBookmarks.swift` creates default iOS bookmarks (`options: []`) and resolves with `[.withoutUI, .withoutMounting, .withoutImplicitStartAccessing]`. `FolderAccessScope.swift:21–28` pairs `startAccessingSecurityScopedResource()` / `stopAccessingSecurityScopedResource()`. Note: `UIFileSharingEnabled` and `LSSupportsOpeningDocumentsInPlace` are set **only** on `CloveLab` (`project.yml:74–78`, `CloveLab/Info.plist`), not `Clove`. | None. Standard iOS sandboxed document-picker access requires no special entitlements. |
| **Photo Library usage** | Grep confirmed **zero** `PHPhotoLibrary`, `PhotosUI`, `NSPhotoLibraryUsageDescription`, or `NSPhotoLibraryAddUsageDescription` references in `Clove` or `Packages/`. | None. Confirm in App Review Notes that Clove accesses user-chosen folders via Files only and intentionally does not request Photo Library permission. |
| **Camera permission** | Grep confirmed **zero** `AVCapture*` or `NSCameraUsageDescription` references. | None. |
| **Privacy Manifest (`PrivacyInfo.xcprivacy`)** | `Clove/PrivacyInfo.xcprivacy` is included in `Clove`'s resources (`project.yml:44–45`) and documented in `docs/privacy-manifest.md`. It declares:<br>• `NSPrivacyTracking = false`, `NSPrivacyTrackingDomains = []`, `NSPrivacyCollectedDataTypes = []`<br>• `FileTimestamp`: `3B52.1` (user-selected files/folders) + `C617.1` (app container caches/stores)<br>• `UserDefaults`: `CA92.1` (`UserDefaultsSettingsStorage` + `@SceneStorage`)<br>• `SystemBootTime`: `35F9.1` (`ProcessInfo.processInfo.systemUptime` in `Clove/Detail/DetailZoomView.swift:658,683`)<br>Re-audit confirms `DiskSpace` (`statfs`/`volumeAvailableCapacity`) and `ActiveKeyboards` are **absent** from `Clove`, `CloveCore`, `CloveImaging`, and `CloveFocusMetadata` (disk-space APIs appear only in `CloveLabKit`, which `Clove` does not link). | **Vision framework check:** `VNGenerateImageFeaturePrintRequest` (`VisionFeaturePrintReader.swift`) and `VNDetectFaceLandmarksRequest` (`VisionFaceRegionDetector.swift`) run **100% on-device** with zero off-device transmission. Vision is **not** a Required Reason API, and strictly on-device inference does **not** require declaring `NSPrivacyCollectedDataTypes`.<br>**Third-party SDK check:** Zero third-party SDKs (`CloveFocusMetadata` is first-party MIT using only `Foundation.FileHandle`). No action needed unless IAP or analytics SDKs are added later. |
| **ATT (App Tracking Transparency)** | Zero `AdSupport` or `AppTrackingTransparency` imports; zero tracking domains; `NSPrivacyTracking = false`. | Not required. |

---

### 4. Export Compliance

- **Repo state:** `project.yml:56` sets `INFOPLIST_KEY_ITSAppUsesNonExemptEncryption: "NO"`. `scripts/release-testflight.py:470` explicitly verifies `info.get("ITSAppUsesNonExemptEncryption") is not False` on every exported IPA before validation/upload.
- **Crypto audit:** Repo-wide grep across `Clove/`, `Packages/CloveCore/`, `Packages/CloveImaging/`, and `Packages/CloveFocusMetadata/` confirms:
  - Zero `URLSession`, `Network`, `NWConnection`, `CFNetwork`, `CommonCrypto`, or `SecItem` usage.
  - The **only** cryptographic import is `CryptoKit`, used solely for non-encryption `CryptoKit.SHA256` hashing (deterministic cache keys and folder IDs in `EntryThumbnailStore.swift`, `GroupingInputFingerprint.swift`, `SimilarGroupsCache.swift`, `GroupingInputRevision+Scanned.swift`, `CloveMarkStore.swift`, `RegionSharpnessCache.swift`, `ImageFeatureCache.swift`, and `ThumbnailRequest.swift`).
- **Assessment:** Setting `ITSAppUsesNonExemptEncryption = NO` is accurate under Apple/BIS export-compliance rules (hashing/integrity digests and standard OS transport qualify as exempt/non-encryption), so ASC will not prompt for export compliance documentation on each upload or require annual BIS self-classification reporting.

---

### 5. Review Risk Analysis

| Area | Evidence in Repo | Risk Level & Mitigation |
| --- | --- | --- |
| **Outside-sandbox file access & moves** | `FolderPicker.swift` (`UIDocumentPickerViewController` `.folder`, `asCopy: false`), `FolderBookmarks.swift`, `PhotoFileSystem.swift` (`renamex_np(2)` with `RENAME_EXCL` inside the user-granted folder), `MarkWriteFileSystem.swift` (same-folder atomic staging + rename for `.xmp` sidecars). | **Low (Standard Practice).** Document-based utilities using security-scoped bookmarks and in-place moves/sidecar writes with user confirmation (`Move rejects`) and Undo are explicitly supported by iOS and routinely approved. |
| **RAW decoding & image/focus analysis** | Public frameworks only (`grep -rh "^import "` across `Clove` + linked packages): `SwiftUI`, `UIKit`, `Foundation`, `CoreGraphics`, `CoreImage` (`CIRAWFilter`), `ImageIO`, `Vision`, `UniformTypeIdentifiers`, `CryptoKit`, `Observation`, `QuartzCore`, `Synchronization`, `Dispatch`, `Darwin`, `os`, plus local `CloveCore`, `CloveImaging`, `CameraFocusMetadata` (pure-Swift binary EXIF/TIFF/BMFF/Sony maker-note parser over `Foundation.FileHandle`). | **None.** Zero private APIs, zero private frameworks, zero `dlopen`/`dlsym`/private selectors. |
| **Reviewer usability (Guideline 2.1)** | App opens to an empty state (`EntryScreen.swift`) requiring the user to pick a folder via Files. Debug/fixture helpers (`TestLibrary`, `DesignGalleryScreen`) are gated strictly behind `CLOVE_TEST_LIBRARY=1` / `CLOVE_DESIGN_GALLERY=1` environment variables (`FolderLibraryLaunch.swift:25`, `DesignGalleryScreen.swift:14–18`) and are unreachable by normal users. | **Medium if Review Notes are unclear.** Adapt `docs/testflight-external.md` ("Beta App Review notes") into **App Store Review Notes** instructing reviewers: no login/hardware drive is required; place a few JPEG/RAW photos into a folder in the Files app ("On My iPhone" / "On My iPad") and select it with **Open folder** to test rating, labeling, grouping, and Move rejects. |
| **Minimum functionality / UX (Guideline 4.2)** | Full native culling workflow: recursive RAW+JPEG+HIF pairing, XMP sidecar round-tripping, Vision burst grouping, AF/face focus inspection, batch rename, 8 themes, iPad sidebar/keyboard shortcuts, iPhone Duo split/cover layouts. | **None.** |
| **Privacy & user data (Guideline 5.1.1)** | All processing is on-device; no account, analytics, or network calls. | **Blocker until URL added.** Supply a clear Privacy Policy URL in ASC (and ideally accessible from Settings) confirming zero data collection. |

---

### 6. Operational Readiness

- **Build number uniqueness:** `scripts/release-testflight.py` (`next_build_number`, `lines 263–277`) queries ASC's `builds` API for the target app + marketing version and generates a strictly higher UTC `yymmddhh` integer.
- **Signing & archive path:** `scripts/release-testflight.py` already executes the full App Store release pipeline: `xcodegen` → unsigned `Release` `xcodebuild archive` → `xcodebuild -exportArchive` (`method: "app-store-connect"`, manual Apple Distribution cert + App Store profile in an ephemeral keychain) → IPA verification (`CFBundleIdentifier`, `CFBundleShortVersionString`, `CFBundleVersion`, `ITSAppUsesNonExemptEncryption == false`, `codesign --verify --deep --strict`, embedded profile team check) → `xcrun altool --validate-app` → `xcrun altool --upload-app`. **There is no signing/pipeline gap for shipping a free App Store build**—the same validated ASC build can be attached to an App Store release in ASC and submitted for App Review.
- **Non-secret local signing signals (Mac mini):** Without reading any secret file or printing any ID/token:
  - `~/.config/apple/` contains `.p8` key file(s), 2 `.p12` file(s), and 6 `.mobileprovision` file(s); the login/user keychain holds 4 `Apple Distribution` identities.
  - In this isolated worktree, gitignored `Config/TestFlight.local.json` and `Config/Local.xcconfig` are absent (per `docs/release.md:11`, release runs pass `--config ~/.config/apple/clove-testflight.json` or `$CLOVE_TESTFLIGHT_CONFIG`).
  - **`UNVERIFIED`** — Whether the specific `com.mimiqdev.clove` App Store profile and Apple Distribution cert are unexpired and match the current ASC record requires running `mise run release -- --config <path> --app clove` (validate-only) or checking ASC Certificates, Identifiers & Profiles.
- **`CloveLab` isolation:** Confirmed `CloveLab` (`com.mimiqdev.clove.lab`) is a separate target in `project.yml:62–90`; `Clove` does not depend on `CloveLabKit` (`project.yml:46–48`), and `scripts/release-testflight.py` selects targets independently via `--app clove|lab`. `CloveLab` remains internal-only (`Clove Lab Internal` TestFlight group).
- **Vendored MIT license attribution (`Packages/CloveFocusMetadata/LICENSE`):**
  - `Packages/CloveFocusMetadata/LICENSE` (`Copyright (c) 2026 mimiqdev`, MIT) and root `LICENSE` (`Copyright (c) 2026 Tony Liu`, MIT) are present in the repository.
  - **Gap found:** `Packages/CloveFocusMetadata/Package.swift` does not copy `LICENSE` as a bundle resource, and `Clove` currently has no in-app About/Licenses screen displaying the MIT copyright & permission notice inside the compiled `.app` binary. Because `mimiqdev` is first-party (same owner organization), there is zero third-party legal risk, but adding an **About / Acknowledgements** row in Settings (which can also host Privacy Policy and Support links) satisfies the MIT binary-distribution notice clause cleanly.

---

## Part B — In-App Purchase (IAP) Enablement

### 1. Account & App Store Connect Prerequisites

1. **Paid Applications Agreement (Owner action in ASC):**
   - Under *App Store Connect → Business (Agreements, Tax, and Banking)*, the **Paid Applications** agreement must be **Active**, with bank account and tax forms (e.g., W-8BEN / W-9) completed and verified.
   - Until this agreement is Active, Apple will not serve IAP products in Sandbox or Production (StoreKit `Product.products(for:)` returns empty / products show "Developer Action Needed").
2. **App monetization model (Free-with-IAP vs Paid Upfront):**
   - **Free-with-IAP (Recommended over Paid Upfront):** `com.mimiqdev.clove` stays Free to download, with StoreKit 2 unlocking Pro features via subscription and/or one-time purchase. Gives photographers a risk-free test on their own SD/CFexpress folders before paying.
   - **Paid Upfront alternative:** Requires Paid Apps agreement and selecting a price tier in ASC; requires **0 StoreKit code**, but lacks a try-before-you-buy funnel on the App Store and complicates any future shift to freemium (requires `AppTransaction.shared.originalAppVersion` grandfathering).
3. **Product IDs & Subscription Group to create in ASC:**
   - Reverse-DNS convention tied to `com.mimiqdev.clove`:
     - **Subscription Group:** e.g. `Clove Pro`
       - `com.mimiqdev.clove.pro.monthly` (Auto-Renewable Subscription, 1 month)
       - `com.mimiqdev.clove.pro.annual` (Auto-Renewable Subscription, 1 year, optional 7-day or 14-day introductory free trial)
     - **One-Time Unlock (Non-Consumable):**
       - `com.mimiqdev.clove.pro.lifetime` (can be offered alone OR alongside subscriptions as a "Lifetime" option)
4. **Pricing & regional storefronts:** Configure base currency price and Apple's automatic or custom regional pricing across storefronts; configure introductory offer eligibility if using a free trial.
5. **Testing setup:**
   - **Local Xcode `.storekit` configuration file:** Enables full UI, purchase, restore, expiration, revocation, and offer testing in the iOS Simulator **immediately**, with no ASC Paid Apps agreement needed.
   - **ASC Sandbox Tester accounts:** Required for end-to-end Sandbox testing in TestFlight / Ad-Hoc / Debug device builds once the Paid Apps agreement is Active and IAP products are created in ASC.

---

### 2. Technical Implementation Path (StoreKit 2)

- **Why StoreKit 2:** Clove's deployment target is **iOS 18.0** (`project.yml:8`). StoreKit 2 (`import StoreKit`) has been native since iOS 15, with SwiftUI `SubscriptionStoreView` / `ProductView` / `StoreView` available since iOS 17—meaning **100% native API coverage with zero legacy StoreKit 1 (`SKPaymentQueue`) fallback**. It also uses Swift `async`/`await` and `AsyncSequence`, aligning with Clove's `SWIFT_VERSION: "6.0"` and `SWIFT_STRICT_CONCURRENCY: complete` settings (`project.yml:18–19`).
- **Capability & Provisioning Profile update:**
  - Enable the **In-App Purchase** capability on the `com.mimiqdev.clove` App ID in Apple Developer Portal (and in `project.yml` target capabilities/entitlements if explicit, or via Xcode signing capabilities).
  - **Important operational step:** Regenerate and replace the `com.mimiqdev.clove` App Store provisioning profile in `~/.config/apple/` (`docs/release.md:72`) after enabling IAP on the App ID, otherwise `scripts/release-testflight.py` will export with the stale profile.
- **Core architecture (`PurchaseStore`, parallel to `SettingsStore`):**
  1. **Launch transaction listener:** Start a single `Task` on app launch (`CloveApp`) iterating `for await result in Transaction.updates`. Verify each JWS payload (`checkVerified`), update entitlement state, and **always call `await transaction.finish()`** (including for renewals, Family Sharing, Ask to Buy approvals, and revocations).
  2. **On-device JWS verification (no server needed):** StoreKit 2 validates Apple's cryptographic JWS signature locally on-device (`VerificationResult<Transaction>`). Reject `.unverified` results; accept `.verified` transactions where `revocationDate == nil` (and for subscriptions, check `expirationDate` or `Product.SubscriptionInfo.Status` for `.subscribed` / `.inGracePeriod`).
  3. **Startup entitlement refresh:** Query `Transaction.currentEntitlements` at launch (and on foreground return if needed) to compute `isPro: Bool` immediately from StoreKit's local signed cache—works **offline** on SD-card shoots with zero network dependency!
  4. **Restore purchases:** Provide an explicit **"Restore Purchases"** button calling `try await AppStore.sync()`, plus re-reading `Transaction.currentEntitlements`. (Never call `AppStore.sync()` automatically on launch, as it can prompt for Apple ID credentials.)
  5. **Entitlement caching & Swift 6:** Keep `PurchaseStore` `@MainActor @Observable`; persist no custom unencrypted "isPro = true" boolean in `UserDefaults` as sole truth—rely on StoreKit 2's local signed transaction cache (`Transaction.currentEntitlements` works offline).
- **Paywall UI & Feature-Gating Options (Owner Decision Required):**
  Clove's core value is fast, reliable culling with XMP writes. Below are the concrete gating boundaries available using features **already implemented** in `Clove/` (listed as options; **owner decides**):

  | Model / Boundary | What stays Free | What requires Pro (IAP) | Trade-offs |
  | --- | --- | --- | --- |
  | **Option A: Core Culling Free / Pro Workflow Tools Paid** | Open folders, grid & detail browsing, RAW/JPEG display, manual stars/labels/rejects + XMP writes, Move Rejects | Any subset of: **Similar Groups** (`FolderGrouping` / `Reject N unmarked`), **Focus Regions & Face/Eye overlays** (`DetailFocusRegionControl`), **Batch Rename** (`BatchRenameFlow`), **Extra Themes** (6 non-system themes) | Cleanest UX for photographers; zero mid-shoot frustration; easy to understand value prop. |
  | **Option B: Folder / Photo Quota (Metered Trial)** | Full feature set up to N folders or N photos per folder (e.g., 50 photos or 3 folder opens) | Unlimited folder size and folder count | Lets users try Focus Regions & Similar Groups before buying, but counting opens locally in `UserDefaults` resets on reinstall unless using Keychain, and hitting a wall mid-shoot can feel punitive. |
  | **Option C: Read-Only Preview Free / Writes Paid** | Browse, zoom, inspect focus regions, view groups | Saving XMP/Clove marks, Move Rejects, Batch Rename | High conversion pressure, but users cannot verify Lightroom/Capture One XMP round-tripping before paying unless paired with a free trial. |
  | **Option D: Free Trial → Full Unlock (Subscription w/ Intro Offer)** | 7- or 14-day free trial via StoreKit 2 intro offer (or limited free browse) | Full app unlocked via Annual/Monthly subscription (+ optional Lifetime unlock) | Simplest product surface (no split feature matrix), predictable recurring revenue, requires subscription disclosures. |

  - **Paywall placement:** Accessible from (1) a "Clove Pro" banner/row in `SettingsScreen` (plus Restore Purchases), (2) Entry screen if on a metered/trial model, and (3) contextual upgrade sheet when tapping a gated control (e.g., Focus Regions toggle, Similar Groups, Batch Rename, or locked theme tile).

---

### 3. App Store Review Requirements for IAP

- **Joint first-time submission:** The **first** set of IAP products for an app must be submitted **together with an app binary version** in App Store Connect (select the IAPs in the *In-App Purchases and Subscriptions* section of the App Store version page before submitting for review).
- **Per-product ASC metadata & review screenshot:** Every IAP product requires Reference Name, Localized Display Name, Description, and an **App Review Screenshot** showing the in-app purchase/paywall screen (captured from a device or Simulator), plus Review Notes explaining where to find the paywall.
- **Mandatory subscription disclosures (Guideline 3.1.2):** If offering auto-renewable subscriptions, the paywall UI **must** visibly display:
  - Subscription title, duration, and price (including clear billing interval, e.g., "$X.XX / year")
  - Free-trial duration and post-trial renewal price (if offering an intro offer)
  - Auto-renewal terms (e.g., payment charged to Apple Account at confirmation; renews automatically unless canceled ≥24h before period end; manage/cancel in Apple Account Settings)
  - Clickable **Terms of Use (EULA)** (Apple's Standard EULA URL or custom Terms URL) and **Privacy Policy** links directly on the paywall (SwiftUI's `SubscriptionStoreView` + `.subscriptionStorePolicyDestination` renders standard Apple compliance elements cleanly).
- **Mandatory "Restore Purchases" UI (Guideline 3.1.1):** Required on the paywall and/or Settings for all non-consumable and auto-renewable subscription apps.
- **Privacy & App Privacy labels:** Because StoreKit 2 verifies transactions on-device with no Clove user accounts or servers, no account/login is needed (note: Guideline 5.1.1(v) account-deletion rules do not apply when there are no accounts). Review ASC's **App Privacy → Purchase History** questionnaire item when enabling IAP.
- **Family Sharing:** Optional per-product toggle in ASC (supported for both non-consumables and auto-renewable subscriptions via `Transaction.currentEntitlements`). **Irreversible once enabled** for a product in ASC—decide before submitting.
- **Commission & Small Business Program:** Standard Apple fee is **30%** (15% after 12 months of continuous paid subscription). If the owner's annual App Store proceeds are **< $1M USD**, applying for the **App Store Small Business Program** in ASC reduces the commission to **15% from day 1** across paid apps, one-time IAPs, and subscriptions.

---

### 4. Effort Estimate & Recommendation

| Approach | Estimated Effort | Pros | Cons |
| --- | --- | --- | --- |
| **On-device StoreKit 2** (One-time Non-Consumable and/or Subscriptions, no server) | **~3–5 engineering days** (`1d` `PurchaseStore` + `Transaction.updates`/entitlements; `1.5–2d` themed Paywall UI + Restore + legal links + gating hooks; `1–2d` `.storekit` tests, Swift 6 `mise run check`, Sandbox verification, profile regen) | Zero backend/infra cost; works 100% offline in the field; zero third-party SDKs (fits `AGENTS.md`); zero account/login friction. | No cross-platform (Android/web) entitlement sync; relies on Apple's StoreKit analytics/reporting rather than custom server webhooks. |
| **Server-backed Subscriptions** (custom backend or RevenueCat + App Store Server Notifications v2) | **~7–12+ engineering days** (+ ongoing server/SDK maintenance) | Cross-platform entitlements, server-side cohort analytics, web billing hooks. | Violates Clove's zero-server/zero-third-party-SDK simplicity (`AGENTS.md`); adds privacy-policy data disclosures and backend operational burden. |

- **Recommendation:** **Use On-Device StoreKit 2 (no backend server)**, structured as **Free-with-IAP offering an Annual/Monthly Subscription (with introductory free trial) AND a One-Time Lifetime Unlock (Non-Consumable)**—or start with the **One-Time Lifetime Unlock** alone if simplicity is prioritized for v1. Both are supported identically through StoreKit 2's `Transaction.currentEntitlements` with no backend and fit Clove's offline, file-based, photographer-friendly positioning.

---

## Part C — Recommended Sequencing

### Track 1 — Can Start Now (No Apple Account / Monetization Decision Required)

| # | Owner | Task | Rough Effort | Notes |
| --- | --- | --- | --- | --- |
| 1 | **Code** | Add an **About / Legal** section in `SettingsScreen` (app version/build, Privacy Policy link placeholder, Support link placeholder, and `CloveFocusMetadata` + `Clove` MIT license notices). | 0.5 day | Also closes the MIT binary-notice gap (`Packages/CloveFocusMetadata/LICENSE`). |
| 2 | **Code** | Draft and host static **Privacy Policy** and **Support** web pages (or prepare markdown/HTML ready for owner's domain). | 0.5 day | Required URLs for ASC submission (and paywall links if IAP is enabled). |
| 3 | **Code** | Capture Simulator/device screenshots for **6.9"/6.7" iPhone** and **13" iPad** (plus optional App Preview clip) showcasing Entry, Grid, Detail 100% zoom + Focus Regions, Similar Groups, and Move Rejects. | 0.5–1 day | `project.yml` targets Universal (`1,2`); both iPhone and iPad screenshots are required. |
| 4 | **Code** | *(If IAP is likely)* Prototype `PurchaseStore` + `.storekit` local configuration file in Xcode against `iOS 18.0+` / Swift 6 strict concurrency. | 1–1.5 days | Local `.storekit` testing works completely offline without ASC setup. |
| 5 | **Code** | Clean up stale icon docs in `AGENTS.md` / `docs/release.md` and prepare App Store Review Notes (adapted from `docs/testflight-external.md`) + `MARKETING_VERSION` bump (`1.0.0` if desired). | 0.25 day | Quick hygiene before submission PR. |

### Track 2 — Requires Owner Apple Account & Product Decisions First

| # | Owner | Task | Rough Effort | Blocking Dependency |
| --- | --- | --- | --- | --- |
| 6 | **Owner** | Verify live `com.mimiqdev.clove` record in ASC, check **Apple Distribution** cert & `clove` provisioning profile expiration, and run a local validate-only build (`mise run release -- --config ... --app clove`). | 0.5 hour | Owner ASC login & local signing config. |
| 7 | **Owner** | Complete **Paid Applications Agreement** (banking + tax forms) in ASC and apply for the **App Store Small Business Program** (15% commission if eligible). | 1–2 hours setup (+ Apple review days) | Required before any IAP or paid app can go live or test in Sandbox. |
| 8 | **Owner** | Decide **monetization model & gating boundary**: (a) Free completely for v1 (ship fastest, add IAP in 1.1), (b) Paid Upfront, or (c) Free-with-IAP (Subscription +/or Lifetime, which features gated, Family Sharing yes/no, pricing). | Decision | Blocks final paywall copy, product IDs, and gating code. |
| 9 | **Owner** | Create ASC listing metadata (Subtitle, Description, Keywords, Category, Age Rating, App Privacy answers, Privacy Policy URL, Support URL, `1.0.0` decision). | 1–2 hours | Needed before submitting v1 to App Review. |
| 10 | **Owner** | *(If shipping IAP in v1)* Enable **In-App Purchase** capability on `com.mimiqdev.clove` App ID, regenerate the `clove` App Store `.mobileprovision` into `~/.config/apple/`, and create the IAP products / Subscription Group in ASC. | 1 hour | Blocks Sandbox testing and App Store export with IAP entitlement. |

### Track 3 — Integration, Verification & Submission (After Tracks 1 & 2)

| # | Owner | Task | Rough Effort | Notes |
| --- | --- | --- | --- | --- |
| 11 | **Code** | *(If shipping IAP in v1)* Wire owner's chosen gating rules, themed Paywall UI (`Restore Purchases`, trial/auto-renew disclosures, Terms/Privacy links), and real ASC product IDs; pass `mise run verify`. | 1.5–3 days | Plus capture IAP Paywall Review Screenshot for ASC product metadata. |
| 12 | **Owner** | Run `mise run release -- --app clove --upload`, test on physical iPhone / iPad / Duo via TestFlight (including Sandbox purchase + restore if IAP is enabled), attach IAP products + screenshots in ASC, and submit for **App Review**. | 0.5 day (+ Apple review 24–48h) | `CloveLab` remains strictly internal (`Clove Lab Internal`). |

> **Fastest path to public App Store:** If the owner wants `Clove` live on the App Store as soon as possible while banking/tax or pricing decisions are pending, ship **v1.0 as Free (no IAP)** first (Track 1 items #1–3, #5 + Track 2 items #6, #9 → Track 3 #12), and introduce StoreKit 2 IAP in **v1.1** once the Paid Applications Agreement and Small Business Program enrollment are active.
