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
Clove helps photographers cull photos directly where they live on iPhone and iPad. Open any folder in place through Files—on internal storage, an external drive, or an SD card—with no importing or copying.

Highlights in this beta:
- RAW + JPEG/HIF pairing managed as a single photo set.
- Fast swipe-to-rate and Reject gestures with an interactive gesture guide, toolbar controls, and external keyboard shortcuts.
- 100% zoom inspection with face detection and camera autofocus (AF) point indicators.
- On-device similar-shot grouping with synchronized zoom and quick "Reject unmarked" cleanup.
- Non-destructive XMP sidecars compatible with Lightroom, Capture One, and Photo Mechanic (standalone JPEG/HIF marks are stored inside Clove).
- Safe Move rejects that moves rejected sets into a `_Rejected` subfolder after confirmation with full Undo—never deleting files.
- Drag-to-select Batch Rename for organizing keepers directly in place.
```

### zh-Hans

```text
Clove 帮助摄影师在 iPhone 和 iPad 上直接于原文件夹中高效筛选照片。通过“文件”应用原地打开设备存储、外接硬盘或 SD 卡中的文件夹，无需导入或复制。

本测试版主要功能：
- RAW + JPEG/HIF 自动配对，作为同一组照片统一浏览与标记。
- 快速滑动评分与淘汰手势，配合交互式手势指南、底部工具栏及外接键盘快捷键。
- 100% 放大检视，支持人脸识别与相机自动对焦点（AF）框显示。
- 端侧相似照片分组，支持组内同步缩放与“淘汰未标记”一键清理。
- 兼容 Lightroom、Capture One 与 Photo Mechanic 的无损 XMP 附属文件（独立 JPEG/HIF 的标记保存在 Clove 内部）。
- 安全“整理淘汰片”流程：确认后将淘汰照片集移至 `_Rejected` 子文件夹并支持撤销，绝不删除原始文件。
- 拖选批量重命名，直接在原文件夹中整理保留照片。
```

### zh-Hant

```text
Clove 協助攝影師在 iPhone 與 iPad 上直接於原檔案夾中高效篩選相片。透過「檔案」App 原地開啟裝置儲存空間、外接硬碟或 SD 卡中的檔案夾，無需匯入或複製。

本測試版主要功能：
- RAW + JPEG/HIF 自動配對，作為同一組相片統一瀏覽與標記。
- 快速滑動評分與淘汰手勢，搭配互動式手勢指南、工具列按鈕與外接鍵盤快速鍵。
- 100% 放大檢視，支援人臉偵測與相機自動對焦點（AF）框顯示。
- 裝置端相似相片分組，支援組內同步縮放與「淘汰未標記」一鍵清理。
- 相容 Lightroom、Capture One 與 Photo Mechanic 的無損 XMP 附屬檔案（獨立 JPEG/HIF 的標記會儲存在 Clove 內部）。
- 安全「整理淘汰片」流程：確認後將淘汰相片組移至 `_Rejected` 子檔案夾並支援復原，絕不刪除原始檔案。
- 拖選批次重新命名，直接在原檔案夾中整理保留相片。
```

## What to test

### en-US

```text
- Open a folder with JPEG or RAW+JPEG/HIF photos via Files, then reopen it from Recents.
- Browse, sort, and filter the grid; tap into Detail View and double-tap or use 100% zoom to inspect focus and camera AF / face indicators.
- Rate, apply color labels, and Reject using swipe gestures (see the gesture guide in Settings), toolbar controls, or an external keyboard; try auto-advance and Undo.
- Review on-device similar-shot groups with synchronized zoom, try Reject unmarked, and Undo.
- Drag to multi-select photos in the grid and test Batch Rename in place.
- Run Move rejects to move rejected sets to `_Rejected`, confirm Undo restores them cleanly, and verify RAW XMP sidecars update as expected.
```

### zh-Hans

```text
- 通过“文件”打开包含 JPEG 或 RAW+JPEG/HIF 照片的文件夹，并尝试从“最近项目”重新打开。
- 在网格中浏览、排序与筛选照片；进入大图视图，双击或使用 100% 缩放检查对焦及人脸/相机 AF 对焦框。
- 使用滑动手势（可在“设置”中查看手势指南）、底部按钮或外接键盘进行星级评分、颜色标签与淘汰标记，并测试自动跳转与撤销。
- 体验端侧相似照片分组与组内同步缩放，测试“淘汰未标记”及撤销效果。
- 在网格中拖动多选照片，测试原地批量重命名功能。
- 使用“整理淘汰片”将淘汰照片移入 `_Rejected` 文件夹，验证撤销可完整还原，并检查 RAW 的 XMP 附属文件保存是否正常。
```

### zh-Hant

```text
- 透過「檔案」開啟包含 JPEG 或 RAW+JPEG/HIF 相片的檔案夾，並嘗試從「最近項目」重新開啟。
- 在格線中瀏覽、排序與篩選相片；進入大圖檢視，點兩下或使用 100% 縮放檢查對焦與人臉／相機 AF 對焦框。
- 使用滑動手勢（可在「設定」中查看手勢指南）、工具列按鈕或外接鍵盤進行星級評分、顏色標籤與淘汰標記，並測試自動跳轉與復原。
- 體驗裝置端相似相片分組與組內同步縮放，測試「淘汰未標記」及復原效果。
- 在格線中拖曳多選相片，測試原地批次重新命名功能。
- 使用「整理淘汰片」將淘汰相片移入 `_Rejected` 檔案夾，確認復原可完整還原，並檢查 RAW 的 XMP 附屬檔案寫入是否正常。
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
