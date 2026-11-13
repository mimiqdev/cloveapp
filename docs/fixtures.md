# Test fixtures

Real camera files, downloaded on demand into a shared cache outside the
repository, plus hand-written XMP sidecars. Every task tests against the same
known inputs, and no binary file is ever committed.

Two scripts do the work:

- `scripts/fetch-fixtures` downloads the pinned files and verifies each
  SHA-256. A second run downloads nothing.
- `scripts/make-fixture-sets` builds the standard test folders from that cache
  and from `fixtures/xmp/`. It never touches the network.

Both use only the Python standard library and run with `/usr/bin/python3`.

## Quick start

```sh
mise run fixtures-fetch   # scripts/fetch-fixtures: about 165 MB, once per machine
mise run fixtures-sets    # fetch, then scripts/make-fixture-sets; repeated files use hard links when possible
mise run test-fixtures    # scripts/test_fixtures.py: logic-only tests, no network
```

The scripts also run directly with `/usr/bin/python3`, and accept `--help`.

Then open any folder under `${CLOVE_FIXTURES_DIR:-/Volumes/T7/Projects/.clove-fixtures}/sets/`
in the app or in a test.

## The cache

The cache lives outside the repository so parallel checkouts share one
download:

```text
${CLOVE_FIXTURES_DIR:-/Volumes/T7/Projects/.clove-fixtures}/
  files/        downloaded files, named <id>.<extension>
  generated/    files built locally with sips, never downloaded
  sets/         the test folders, rebuilt by make-fixture-sets
```

`CLOVE_FIXTURES_DIR` overrides the whole thing. The default is on the T7 SSD,
next to the project.

`files/` holds only what `fixtures/manifest.json` lists. A file that fails its
checksum is deleted and downloaded again; if the new download still does not
match, the run fails with a message naming the file and nothing is kept.

Repeated entries use hard links when the cache and set filesystem support them,
with a copy fallback. The `browsing-2000` set uses about 35 MB of new disk space
in the shared APFS cache, but about 20 GiB when copied without links.

## What is downloaded, and why

One file per format the app must open, chosen so the interesting cases are
covered rather than the biggest files:

| ID | Format | Camera | Size | Why this one |
| --- | --- | --- | --- | --- |
| `canon-eos-r6-cr3` | CR3 | Canon EOS R6 | 22.9 MB | Full RAW (not CRAW), with a full-size embedded preview. The main CR3 case. |
| `nikon-d500-nef` | NEF | Nikon D500 | 19.1 MB | 12-bit lossless compressed, large size, full-size embedded preview. |
| `sony-ilce-7s-arw` | ARW | Sony ILCE-7S | 6.2 MB | 14-bit compressed, APS-C crop, and **no** full-size embedded preview (1616×1080 only). The small-preview case for S2. |
| `fujifilm-x-s10-raf` | RAF | Fujifilm X-S10 | 25.8 MB | X-Trans, 14-bit lossless compressed, only tiny embedded previews. The full-decode case. |
| `olympus-e-m1markii-orf` | ORF | Olympus E-M1MarkII | 17.3 MB | Standard 20 MP raw with a 3200×2400 preview, not full size. |
| `panasonic-dmc-gh4-rw2` | RW2 | Panasonic DMC-GH4 | 19.6 MB | 4:3 aspect, 1920×1440 embedded preview. |
| `pentax-k-5-ii-s-dng` | DNG | Pentax K-5 II s | 18.5 MB | A **camera-generated** DNG (DNG 1.1, not Adobe DNG Converter), full-size embedded preview. |
| `apple-iphone-12-pro-proraw-dng` | DNG (ProRAW) | Apple iPhone 12 Pro | 29.2 MB | Apple ProRAW: DNG 1.4, 12-bit LinearRaw in lossy JPEG, plus an Apple semantic segmentation matte. |
| `canon-eos-6d-jpeg` | JPEG | Canon EOS 6D | 4.4 MB | A JPEG converted from a Canon CR2 in Adobe Camera Raw, at native sensor size with EXIF intact. Its XMP records the conversion (`xmpMM:History`, `crs:` settings, ExifTool 10.27), so it is not out-of-camera. It is the other-app XMP preservation case. |

Total: 162.9 MB, well under the 1 GB budget. The per-file `notes` in
`fixtures/manifest.json` record the embedded-preview sizes, which S2 needs.

`raw.pixls.us` hosts no JPEG, so the one JPEG comes from Wikimedia
Commons. Everything else is from `raw.pixls.us`, which records the license and
SHA-256 for each file.

## Licenses

Each entry records its license exactly as the source states it, plus a
`licenseUrl`. Nothing here restricts use in tests, and nothing is redistributed
because no binary is committed.

| ID | License as stated at the source | License URL | Attribution |
| --- | --- | --- | --- |
| `canon-eos-r6-cr3` | Creative Commons 0 - Public Domain (CC0 1.0) | <https://creativecommons.org/publicdomain/zero/1.0/> | not required |
| `nikon-d500-nef` | Creative Commons 0 - Public Domain (CC0 1.0) | <https://creativecommons.org/publicdomain/zero/1.0/> | not required |
| `sony-ilce-7s-arw` | Creative Commons 0 - Public Domain (CC0 1.0) | <https://creativecommons.org/publicdomain/zero/1.0/> | not required |
| `fujifilm-x-s10-raf` | Creative Commons 0 - Public Domain (CC0 1.0) | <https://creativecommons.org/publicdomain/zero/1.0/> | not required |
| `olympus-e-m1markii-orf` | Creative Commons 0 - Public Domain (CC0 1.0) | <https://creativecommons.org/publicdomain/zero/1.0/> | not required |
| `panasonic-dmc-gh4-rw2` | Creative Commons 0 - Public Domain (CC0 1.0) | <https://creativecommons.org/publicdomain/zero/1.0/> | not required |
| `pentax-k-5-ii-s-dng` | Creative Commons 0 - Public Domain (CC0 1.0) | <https://creativecommons.org/publicdomain/zero/1.0/> | not required |
| `apple-iphone-12-pro-proraw-dng` | Creative Commons 0 - Public Domain (CC0 1.0) | <https://creativecommons.org/publicdomain/zero/1.0/> | not required |
| `canon-eos-6d-jpeg` | CC BY-SA 4.0 | <https://creativecommons.org/licenses/by-sa/4.0/> | Dmitry A. Mottl (User:Dmottl), Wikimedia Commons |

Source pages:

- `raw.pixls.us` repository: <https://raw.pixls.us/>. Each entry also records
  `sourceEntry`, the row it was taken from (make / model / mode / size / date).
- The JPEG: <https://commons.wikimedia.org/wiki/File:Teriberka.jpg>.

## Generated files

A few files in the sets are built locally with `sips` from a verified download,
because the camera wrote no such file and we do not commit binaries:
paired JPEGs (for RAW+JPG pairs) and HEIC. They are described in
`fixtures/generated.json` and marked generated, not downloaded:

- they have no pinned checksum, because the bytes depend on the macOS `sips`
  version;
- they are built once into `${CLOVE_FIXTURES_DIR}/generated/` and reused after
  that;
- deleting `generated/` rebuilds them on the next `make-fixture-sets`.

## The sets

`fixtures/sets.json` defines the folders. Each is deleted and recreated on
every run, so the file list is the same every time.

| Set | Contents | Main consumer |
| --- | --- | --- |
| `card-basic` | An SD-card layout with `DCIM/100CANON` and `DCIM/101CANON`: two RAW+JPG pairs with a shared base name, a standalone JPEG, HEIC and DNG, an XMP sidecar, AppleDouble `._` files, `.DS_Store` and `.Trashes/`, an unsupported `.MOV` and `.txt`, and an existing `_Rejected/` folder holding one photo. | C2 scanning and pairing, P0-01 |
| `xmp-interop` | One RAW per sidecar style, in a folder per style: Lightroom, Capture One, Photo Mechanic, unknown namespace, orange label, pink label, rating −1, empty, empty description, malformed, and a RAW+JPG pair sharing one sidecar. | C3, S3, P0-07 |
| `name-collision` | Active photos whose names already exist in `_Rejected`, including a RAW+JPG pair and its XMP, so Move rejects must add a suffix instead of overwriting. | C6, P0-10 |
| `browsing-2000` | Exactly 2,000 logical photos and 4,000 image files: ARW+JPEG, ARW+HIF, ARW+JPEG+HIF, and standalone DNG, JPEG, and HEIC. Repeated sources share capture metadata and pixels for a repeatable load set. Its hidden `.clove-fixture.json` records the definition digest, source hashes, and file count. | Q3 browsing performance |
| `formats` | One file per format, flat. | format detection, decode tests |

`fixtures/xmp/README.md` explains what each hand-written sidecar tests.

## Adding a downloaded file

1. Find a file whose license allows use in tests, on `raw.pixls.us` or another
   public source, and note its source page, its license as stated there, and
   the row you took it from.
2. Download it once and take the size and checksum:

   ```sh
   curl -L -o /tmp/new.cr3 'https://raw.pixls.us/getfile.php/1234/nice/Some%20File.CR3'
   stat -f %z /tmp/new.cr3
   shasum -a 256 /tmp/new.cr3
   ```

3. Add an entry to `fixtures/manifest.json` with `id`, `format`, `camera`,
   `url` (percent-encoded, no spaces), `bytes`, `sha256`, `source`,
   `license`, `notes`, and `licenseUrl` / `attribution` when they apply. Keep
   `id` lowercase with dashes; it becomes the cache file name.
4. Add the license row to the table above.
5. Add the file to a set in `fixtures/sets.json` if a set needs it.
6. Run `/usr/bin/python3 scripts/test_fixtures.py` (it validates the manifest
   and the set definitions), then `scripts/fetch-fixtures` and
   `scripts/make-fixture-sets`.

Keep the total under 1 GB. Prefer a smaller file that covers the case over a
larger one that does not.

## Adding a generated file

1. Add a recipe to `fixtures/generated.json` (a `sips` invocation: `args` run
   before the input path, `--out` is added by the script).
2. Reference it from `fixtures/sets.json` with `"from": "<manifest id>"` plus
   `"recipe": "<recipe id>"`.
3. Mention it in the generated-files section above and in the set's `comment`.

## Troubleshooting

- **`error: <id> still does not match the manifest`** — the source changed or
  the download was altered in transit. Re-download by hand, compare the
  checksum, and update the manifest if the source legitimately changed.
- **`missing source for ... (run scripts/fetch-fixtures first)`** — the set
  builder never downloads; run the fetch script first.
- **`recipe 'jpeg-from-raw' needs 'sips', which is not on PATH`** — generated
  files need macOS. Downloads and sets that copy files still work elsewhere.
- **The cache is on a disconnected drive** — point `CLOVE_FIXTURES_DIR` at a
  local folder and run both scripts again.

## Repeating files and recording identity

Set `"repeat": N` on a `from` entry and put `{index}` in its `to` path. The
builder replaces the placeholder with a four-digit number starting at `0001`.
Use the same index for companions so they form one logical photo. Repeated
entries use hard links when possible, then fall back to copies.

Set `"identity": true` on a set to write `.clove-fixture.json`. The hidden file
contains the canonical set-definition SHA-256, every referenced manifest
source's pinned SHA-256, recipe definitions, generated-file SHA-256 values, and
the expanded file count. Clove Lab reads this file for fixture identity and
validates the production scan's file count.

## Rules

- No binary file is committed. `git status --short` stays clean after both
  scripts run, because the cache is outside the checkout.
- The manifest is the only source of truth for a download: never edit a cached
  file by hand, and never add a file without a checksum.
- `fixtures/xmp/` is ours, so it is committed as text. Everything else is
  downloaded.
