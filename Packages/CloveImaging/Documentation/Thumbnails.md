# Grid thumbnails

`ThumbnailPipeline` accepts the physical file selected by the caller. For a RAW
photo set, pass its RAW once, rather than submitting each companion. The caller
owns folder access. There is no dependency on CloveCore or CloveLabKit.

```swift
let cache = try ThumbnailCache(directory: appCaches.appendingPathComponent("thumbnails"))
let pipeline = ThumbnailPipeline(cache: cache) // four workers, 128 queued requests
let request = ThumbnailRequest(
    source: primaryFile,
    revision: try ThumbnailRevision.read(from: primaryFile),
    locationIdentity: folderIdentity
)
let result = try await pipeline.thumbnail(for: request, consumer: cellID)
```

Reuse a consumer UUID while a cell/view is reused: each new request supersedes
that consumer's previous request. Cancel its task when it leaves the viewport.
Cancelled/superseded requests throw `CancellationError`. A full queue throws
`queueFull`; visible requests can displace queued prefetch. Results distinguish
usable pixels (with actual dimensions and extraction route) from unavailable
previews. Returned pixels have orientation applied, including disk cache hits.

RAW and HEIF use ImageIO with both thumbnail-generation flags false. The actual
container type is checked as well as the extension. Other rasters use IfAbsent,
then at most one Always fallback for absent/undersized output. There is no RAW
render or detail-preview path. System camera/compression support still applies.

Use `setWorkerCount(2)` under contention, and `cancelPrefetch()` to stop speculative
work. Synchronous ImageIO calls cannot be interrupted. Cancelled work occupies its
worker until it drains, and cannot deliver a result. `await pipeline.close()`
stops admission, cancels all requests, and waits for native work to finish; release
the folder's security scope after that call. Use a new pipeline for the next
folder session.

The cache defaults to 64 MiB decoded memory and 256 MiB JPEG disk storage at
quality 0.8. Each instance exclusively owns its app-private cache directory; do
not share that directory between live instances. Both tiers use LRU eviction by
byte cost. Memory-pressure warnings clear decoded/failure entries; the app may
also call `releaseMemory()`. Disk failures are best-effort and cannot turn usable
source pixels into a failed request. Corrupt entries are discarded. Failed
extractions are cached in bounded memory only, so reopening a folder retries.

Keys include location identity, standardized path, the caller's exact size and
modification timestamp, target pixels, orientation transform, extraction route,
and pipeline version. Increment `pipelineVersion` when extraction policy changes.
Old versions become misses and age out within the disk budget. A provider that
changes bytes without changing either size or timestamp needs a refreshed
location identity; this cache cannot infer such a revision from the supplied
attributes. Sources are checked against the supplied revision before and after
work. Disk JPEGs are staged beside the destination and atomically renamed; stale
staging files are removed at the next cache open.

Run `mise run test-imaging` for functional tests. For a short informational macOS
measurement, use `CLOVE_THUMBNAIL_TIMINGS=1 mise run test-imaging`. It reports three
observations per format and twelve uncached jobs with four workers. HIF uses a
generated HEIF container with an embedded thumbnail; ARW and JPEG use the shared
`formats` fixture set. These measurements are not device performance acceptance.
