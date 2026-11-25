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
Clove is a fast, native photo culling app for iPhone and iPad. Open folders directly on SD cards, external SSDs, or in Files—no importing, no duplicated storage, and no touching your originals.

Key features:
- Non-destructive by design: RAW ratings, color labels, and keywords write standard XMP sidecars ready for Lightroom, Capture One, and Photo Mechanic. Standalone JPEG/HEIF marks stay local without modifying original files, and Move Rejects only moves files into a _Rejected subfolder with Undo—never deletes.
- Fast gestures & 100% focus check: Swipe horizontally to step photos, swipe vertically to rate or reject (plus iPad keyboard shortcuts), and double-tap anywhere to inspect native 100% pixels with automatic eye, face, and camera AF point overlays.
- Similar-shot groups & side-by-side Compare: On-device grouping clusters bursts so you can cull inside a group with synchronized 100% zoom and focus tracking, or compare A/B frames side by side on iPad and wide screens.
- Complete on-location tools: Filter by camera, lens, focal length, rating, or color label; batch mark, batch add keywords, batch rename, and save JPEG/HEIF copies to Photos.
- Six distraction-free themes (Light, Dark, System) that restyle only the app around your photos—images are never tinted.
```

### zh-Hans

```text
Clove 是一款专为 iPhone 与 iPad 打造的原生现场选片工具。无需导入、不复制原片，直接打开 SD 卡、外接 SSD 或「文件」中的文件夹即可开始极速挑片。

核心特性：
- 零导入、不删原片：RAW 评星/标色/关键词直接写入标准 XMP 旁车文件，无缝衔接 Lightroom、Capture One 与 Photo Mechanic；独立 JPEG/HEIF 标记保存在本地，不改写原图；「移动已淘汰」仅移入 _Rejected 子目录并支持撤销。
- 极速手势与精准查焦：单手左右滑切图、上下滑评星或淘汰，支持 iPad 键盘快捷键；双击直达 100% 原始像素，自动识别人眼、人脸与相机对焦点。
- 连拍分组与双图对比：端侧自动聚类相似连拍，组内切换自动保持 100% 缩放并对焦追踪；大屏支持 A/B 并排同步缩放对比，快速挑出最佳一张。
- 完备的现场整理工具：支持按机身/镜头/焦段/星级/颜色筛选，批量标记、批量添加关键词、批量重命名以及导出 JPEG/HEIF 到系统相册。
- 6 套专业暗房与配色主题，仅改变界面，绝不对照片偏色。
```

### zh-Hant

```text
Clove 是一款專為 iPhone 與 iPad 打造的原生現場選片工具。無需匯入、不複製原片，直接開啟 SD 卡、外接 SSD 或「檔案」中的資料夾即可開始極速挑片。

核心特色：
- 零匯入、不刪原片：RAW 評星／標色／關鍵字直接寫入標準 XMP 旁車檔，無縫銜接 Lightroom、Capture One 與 Photo Mechanic；獨立 JPEG／HEIF 標記保存在本機，不改寫原圖；「移動已淘汰」僅移入 _Rejected 子資料夾並支援還原。
- 極速手勢與精準查焦：單手左右滑切圖、上下滑評星或淘汰，支援 iPad 鍵盤快捷鍵；點兩下直達 100% 原始像素，自動辨識人眼、人臉與相機對焦點。
- 連拍分組與雙圖對比：裝置端自動聚類相似連拍，組內切換自動維持 100% 縮放並追蹤對焦點；大螢幕支援 A/B 並排同步縮放對比，快速挑出最佳一張。
- 完備的現場整理工具：支援依機身／鏡頭／焦段／星級／顏色篩選，批次標記、批次加入關鍵字、批次重新命名，以及儲存 JPEG／HEIF 至系統相簿。
- 6 套專業暗房與配色主題，僅改變介面，絕不對相片偏色。
```

## What to test

### en-US

```text
Welcome to the first Clove Public Beta (0.1.0)! Every action is non-destructive and never deletes or overwrites your original photos—feel free to test with a real shoot on an SD card, external SSD, or local folder in Files.

What to try:
1. Fast culling & 100% focus inspection: Try one-handed vertical swipe rating/rejecting, the bottom toolbar (or iPad shortcuts 1–5 / X / ⌘Z), and double-tapping to inspect 100% sharpness with camera AF, face, and eye overlays.
2. Burst grouping & Compare: With Similar groups on, tap or swipe down on a filmstrip stack to enter Group Focus (try stepping through shots at 100% zoom), and try side-by-side A/B Compare on iPad or wide screens.
3. Batch & organization tools: Try multi-select batch rating/keywords, Batch Rename, filtering by camera/lens/focal length, and Move Rejects into _Rejected (with Undo).
4. Desktop round-trip: Open your culled folder in Lightroom, Capture One, or Photo Mechanic to verify XMP star ratings, color labels, and keywords.

Feedback we'd love most:
- RAW decoding and camera AF point accuracy for your camera model (please mention body & format, e.g. ARW / CR3 / NEF / RAF / DNG)
- Responsiveness on real SD cards / external SSDs (opening, thumbnail scrolling, filmstrip scrubbing, 100% zoom)
- Any mis-taps, UI rough edges, or friction—please share a TestFlight screenshot anytime!
```

### zh-Hans

```text
欢迎参与 Clove 首个公开测试版（0.1.0）！所有操作均不会删除或覆盖你的原始照片，推荐直接插上常用 SD 卡、外接 SSD 或打开本地实拍文件夹体验：

建议重点体验：
1. 极速选片与查焦：尝试单手上下滑动评星/淘汰、底部工具栏（或 iPad 快捷键 1–5 / X / ⌘Z），以及双击 100% 放大查看相机对焦点与人脸/人眼框。
2. 相似连拍与对比：在开启「相似分组」后点击或下拉胶片条中的叠堆进入组内选片（感受组内 100% 同步查焦），并在 iPad / 大屏上体验并排 Compare 对比。
3. 批量与整理流程：试试多选批量评星/关键词、批量重命名、按相机/镜头/焦段筛选，以及「移动已淘汰」到 _Rejected 文件夹并撤销。
4. 桌面工作流衔接：用 Lightroom / Capture One / Photo Mechanic 打开选完片的目录，验证 XMP 星级、颜色标签与关键词是否正确识别。

最期待收到的反馈：
- 你所用相机型号的 RAW 解码与相机对焦点显示是否准确（欢迎附机型与格式，如 ARW / CR3 / NEF / RAF / DNG）
- 外接存储卡 / SSD 上的加载速度、切图与胶片条滑动是否流畅
- 任何误触、界面瑕疵或不顺手的地方，欢迎直接通过 TestFlight 截屏反馈！
```

### zh-Hant

```text
歡迎參與 Clove 首個公開測試版（0.1.0）！所有操作皆不會刪除或覆蓋你的原始相片，推薦直接插上常用 SD 卡、外接 SSD 或開啟本機實拍資料夾體驗：

建議重點體驗：
1. 極速選片與查焦：嘗試單手上下滑動評星／淘汰、底部工具列（或 iPad 快捷鍵 1–5 / X / ⌘Z），以及點兩下 100% 放大檢視相機對焦點與人臉／人眼框。
2. 相似連拍與對比：開啟「相似分組」後點擊或下拉膠片條中的疊堆進入組內選片（感受組內 100% 同步查焦），並在 iPad／大螢幕上體驗並排 Compare 對比。
3. 批次與整理流程：試試多選批次評星／關鍵字、批次重新命名、依相機／鏡頭／焦段篩選，以及「移動已淘汰」至 _Rejected 資料夾並還原。
4. 桌面工作流銜接：用 Lightroom／Capture One／Photo Mechanic 開啟選完片的資料夾，驗證 XMP 星級、顏色標籤與關鍵字是否正確辨識。

最期待收到的回饋：
- 你所用相機型號的 RAW 解碼與相機對焦點顯示是否準確（歡迎附機型與格式，如 ARW / CR3 / NEF / RAF / DNG）
- 外接記憶卡／SSD 上的載入速度、切圖與膠片條滑動是否流暢
- 任何誤觸、介面瑕疵或不順手的地方，歡迎直接透過 TestFlight 截圖回饋！
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
