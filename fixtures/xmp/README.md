# XMP sidecar fixtures

Hand-written XMP sidecars, committed as text because they are ours. They are
copied into the `xmp-interop` set by `scripts/make-fixture-sets`, one RAW per
sidecar, so the XMP codec (C3) and the format decision (S3) can round-trip every
shape another app may leave on a card. See [docs/fixtures.md](../../docs/fixtures.md)
for the whole fixture story.

Every sidecar uses the standard sidecar name: the file name matches its RAW,
with `.XMP` instead of the RAW extension.

| Sidecar | What it tests |
| --- | --- |
| `lightroom-full.xmp` | Lightroom Classic output. `xmp:Rating="5"`, `xmp:Label="Purple"`, and a full `crs:` develop block: `ProcessVersion`, `Exposure2012` … `Blacks2012`, texture, clarity, dehaze, parametric shadows, sharpening, noise reduction, lens profile, three `crs:ToneCurvePV2012*` sequences, `dc:subject`, and a two-entry `xmpMM:History`. Writing a rating or label must not touch any of it. |
| `capture-one.xmp` | Capture One output. It reuses the `crs:` namespace with its own older tag names (`crs:HighlightRecovery`, `crs:ShadowRecovery`, `crs:FillLight`, `crs:Radius`), writes fractional values (`crs:Tint="3.5"`), and records `crs:RawFileName`. Tests that our reader does not assume Lightroom's tag set and that unknown `crs:` tags survive. |
| `photo-mechanic.xmp` | Photo Mechanic output. No develop settings at all: `xmp:Rating`, `xmp:Label`, `xmp:Urgency`, IPTC via `photoshop:`, `Iptc4xmpCore:` and `Iptc4xmpExt:`, plus language alternatives (`rdf:Alt` with `xml:lang`), `rdf:Seq` for `dc:creator`, `rdf:Bag` for keywords, and `xmpRights:`. Tests that a metadata-only sidecar keeps its IPTC block. |
| `custom-namespace-nested.xmp` | An unknown namespace (`acme:` under `https://example.com/ns/clove-fixture/acme/1.0/`) with nested structures: `rdf:parseType="Resource"` inside `rdf:parseType="Resource"`, a `rdf:Bag` of resources, a `rdf:Seq` of resources, and an `rdf:datatype` base64 value. This is the strongest "preserve what we do not understand" case: nothing here is ours, so a write must leave every byte of it in place. |
| `label-orange.xmp` | An extended colour label: `xmp:Label="Orange"`, one of the two colours Clove supports beyond the default five. |
| `label-pink.xmp` | The other extended colour label: `xmp:Label="Pink"`. |
| `rating-minus-one.xmp` | `xmp:Rating="-1"`, the XMP rejected value, together with `xmp:Label=""` (an explicitly empty label) and a small `crs:` block. Tests that −1 is read as rejected and not as "no rating", and that it survives a round trip. |
| `empty.xmp` | A zero-byte sidecar. Some apps leave one behind when a write is interrupted; the reader must treat it as "no metadata" rather than crash, and a write must replace it cleanly. |
| `empty-description.xmp` | A well-formed packet whose `rdf:Description` carries no properties. The reader must return empty metadata, and a write must add properties without duplicating the `rdf:Description`. |
| `malformed.xmp` | Truncated XML: the packet opens, `rdf:li` and everything after it is cut off mid-value, and there is no `<?xpacket end?>`. Tests that a broken sidecar is reported as a problem instead of being silently rewritten or crashing the scan, and that the file is left as it is. |

## Adding a sidecar

1. Add the `.xmp` file here, as UTF-8 text with LF line endings.
2. Add it to the `xmp-interop` set in `fixtures/sets.json` (pair it with a RAW
   whose base name matches).
3. Add a row to the table above.
4. Run `/usr/bin/python3 scripts/test_fixtures.py`; it checks that every
   sidecar in this folder is referenced by `fixtures/sets.json` and that the
   well-formed ones parse as XML.

The sidecars are fixtures, not samples of real user data. Names, places and
licence URLs inside them are invented.
