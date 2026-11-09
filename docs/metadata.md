# Metadata reading

`CloveImaging.MetadataReader` reads the primary file chosen by its caller. Pass
RAW for a RAW+companion set; the reader does not discover or read companions.
It has no dependency on CloveCore or CloveLabKit.

```swift
let reader = MetadataReader(maximumConcurrentReads: 4)
let results = await reader.read(urls: primaryURLs)
for result in results {
    switch result.outcome {
    case .success(let metadata):
        // Map metadata.time into the domain's sorting input.
        // Only .captureMetadata is eligible for grouping.
        consume(metadata)
    case .failure(let reason):
        recordUnavailable(result.url, reason)
    }
}
```

The single-file `read(url:)` performs synchronous I/O and should run in a
background task. Batch reads bound simultaneous I/O, preserve input order and
duplicates, and return one outcome per input. Cancellation stops admission,
drains the current ImageIO property calls, and marks unfinished inputs
`.cancelled`. A property call cannot be interrupted mid-read. Callers retain
folder access until the batch returns.

Each read creates one ImageIO source with caching disabled and copies the first
image's properties once. It never creates an image, requests a thumbnail, or
opens a second metadata/XMP enumeration path. Capture fields come from
`{Exif}.DateTimeOriginal`, `SubsecTimeOriginal` and `OffsetTimeOriginal`; model
comes from `{TIFF}.Model`. Body serial preference is `{Exif}.BodySerialNumber`,
`{ExifAux}.SerialNumber`, then the known maker dictionary serial keys. Lens
serials are excluded. Values are trimmed and each selected field reports its
ImageIO property path. Missing and malformed fields have distinct states.
XMP-only capture/identity values are outside this property-only reader.

`CaptureTime.wallTime` encodes the camera's Gregorian wall clock against a fixed
UTC surrogate, including fractional seconds. It is not itself an absolute
instant. `CaptureTime.timestamp` returns `.utc` only with an explicit offset;
otherwise it returns `.cameraWallTime`. The original subsecond digits remain
available so precision and zeroes are preserved beyond `Date`'s precision.
A valid `DateTimeOriginal` remains usable when subseconds or offsets are unusable.
An unusable subsecond contributes no fraction; an unusable offset leaves camera
wall time with no UTC offset. Empty optional fields after trimming, or fields
containing only spaces and colons (such as the EXIF unknown offset `"   :  "`),
are `.missing`. Space-padded digits are trimmed and parsed normally. Other
malformed text stays `.invalid` on the subsecond or offset field so callers can
inspect it, without losing capture order or grouping eligibility. A malformed
`DateTimeOriginal` still makes capture time invalid and selects a file-time
fallback when available.

`ImageMetadata.time` selects usable capture metadata, then file creation time,
then file modification time, or `.unavailable`. TIFF `DateTime` is never used
as capture time. Only the capture case can be grouped. The file date fields and
invalid capture state remain available even when a fallback is selected.
Unreadable files and unavailable ImageIO properties have per-file failures;
missing filesystem dates do not discard valid capture metadata.

The tests in `Packages/CloveImaging/Tests/CloveImagingTests/Metadata/` require the
standard `formats` set (`mise run fixtures-sets`). They check the availability
and selected property paths documented by S5 for all ten samples. Generated
JPEGs exercise capture metadata and controlled file dates. Since APFS always
supplies birth time, the modification-only case uses the real generated file's
modification date through a file-date provider seam that omits creation time.
The serial timing test reports 30 reads across three passes; it has no speed
threshold, cache flush, or device-performance claim.
