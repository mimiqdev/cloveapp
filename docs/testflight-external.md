# External TestFlight materials

App Store Connect metadata and localized tester copy for Clove's Public Beta
(`com.mimiqdev.clove`). `scripts/public-beta-testflight.py` reads the fenced
`text` blocks below directly so the documentation and App Store Connect stay in
sync.

## Group and feedback settings

- External beta group: `Clove Public Beta`
- Documented default feedback email: `mrtoniliu@gmail.com` (override with `--feedback-email`)

## Beta description

### en-US

```text
Clove is a fast, native photo culling app for iPhone and iPad. Open folders directly on SD cards, external SSDs, or in Files—with no importing and no duplicated storage.

- Swipe to rate, color-label, and reject, with instant 100% zoom and face / camera AF inspection
- Compare bursts effortlessly with on-device grouping and synchronized zoom
- Save standard XMP sidecars ready for Lightroom, Capture One, and Photo Mechanic
```

### zh-Hans

```text
Clove 是一款专为 iPhone 与 iPad 打造的原生选片工具。直接打开存储卡、移动硬盘或「文件」中的文件夹原位选片，无需导入、不占额外空间。

- 单手滑动快速评星、标色与淘汰，双击 100% 放大配合人脸与相机对焦点精准查焦
- 自动聚合相似连拍并支持同步缩放对比，快速挑出最佳一张
- RAW 标记直接写入标准 XMP，无缝衔接 Lightroom、Capture One 与 Photo Mechanic
```

### zh-Hant

```text
Clove 是一款專為 iPhone 與 iPad 打造的原生選片工具。直接開啟記憶卡、外接硬碟或「檔案」中的資料夾原位選片，無需匯入、不佔額外空間。

- 單手滑動快速評星、標色與淘汰，點兩下 100% 放大搭配人臉與相機對焦點精準查焦
- 自動聚合相似連拍並支援同步縮放對比，快速挑出最佳一張
- RAW 標記直接寫入標準 XMP，無縫銜接 Lightroom、Capture One 與 Photo Mechanic
```

## What to test

### en-US

```text
Welcome to the Clove Public Beta! Try culling a real shoot from an SD card, external SSD, or local folder in Files:
- Test swipe rating/rejecting, 100% focus inspection, and burst comparison at your normal culling pace
- Check XMP sidecar round-tripping with your desktop editor (Lightroom, Capture One, Photo Mechanic)
- Share anything via TestFlight feedback that feels slow, awkward, or gets in your way
```

### zh-Hans

```text
欢迎参与 Clove 公开测试！建议直接用你日常拍摄的存储卡、外接 SSD 或本地照片文件夹体验完整选片流程：
- 体验滑动评星/淘汰、100% 放大查焦与连拍对比的手感与速度
- 验证 RAW 的 XMP 标记与桌面后期软件（Lightroom / Capture One 等）的衔接是否顺畅
- 任何卡顿、误触或不顺手的细节，欢迎随时通过 TestFlight 截屏反馈
```

### zh-Hant

```text
歡迎參與 Clove 公開測試！建議直接用你日常拍攝的記憶卡、外接 SSD 或本機相片資料夾體驗完整選片流程：
- 體驗滑動評星／淘汰、100% 放大查焦與連拍對比的手感與速度
- 驗證 RAW 的 XMP 標記與桌面後製軟體（Lightroom / Capture One 等）的銜接是否順暢
- 任何卡頓、誤觸或不順手的細節，歡迎隨時透過 TestFlight 截圖回饋
```

## Beta App Review notes

```text
No account, sign-in, subscription, or external drive is required to review Clove.

To test the app:
1. Tap "Open folder" on the home screen and select any writable local folder in Files ("On My iPhone" or "On My iPad") containing a few JPEG or camera RAW photos.
2. Browse the photo grid, open any photo to inspect 100% zoom and face/AF focus indicators, and swipe or use the toolbar to apply star ratings, color labels, or Reject.
3. Open similar-shot groups (when multiple similar photos are present), test drag-to-select Batch Rename from the grid toolbar, and test "Move rejects" (moves rejected sets into a `_Rejected` subfolder after confirmation and supports Undo; no files are ever deleted).

Privacy note: Photo Library permission is intentionally not requested because Clove operates strictly on user-selected folders via the Files document picker. All similar-shot grouping runs on-device, and RAW marks are written to XMP sidecar files while standalone JPEG/HIF marks are stored inside Clove.
```
