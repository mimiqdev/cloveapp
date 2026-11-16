# Clove MVP: UI copy

Every user-facing string as it appears in the designs. Numbers are examples; use `Text` with plural rules (`^[\(n) photo](inflect: true)`) and locale number formatting. Sentence case throughout. The middle dot " · " separates subtitle segments.

## Entry
| Key | String |
|---|---|
| entry.title | Clove |
| entry.hero.kicker | Continue · {relative date} |
| entry.hero.left | {n} left |
| entry.earlier | Earlier |
| entry.row.done | Done |
| entry.row.reconnect | Reconnect |
| entry.open | Open folder |
| entry.empty.title | Cull where your photos live. |
| entry.empty.body | Open a folder on a card, drive or Files. Nothing is imported or copied. |

## Grid
| Key | String |
|---|---|
| grid.subtitle | {n} photos |
| grid.subtitle.filtered | {filter} · {n} |
| grid.subtitle.reading | {read} of {total} |
| grid.subtitle.grouping | Finding similar shots… |
| grid.filter.all / unmarked / rejected | All / Unmarked / Rejected |
| grid.filter.rating | Rating ≥ |
| grid.filter.label | Label |
| grid.more.sort | Sort by |
| grid.more.sort.time / name | Capture time / Filename |
| grid.more.select | Select |
| grid.more.regroup | Find similar shots again |
| grid.more.settings | Settings |
| grid.select.title | {n} selected |
| grid.select.done | Done |
| tile.nopreview | No preview |
| a11y.moveRejects | Move rejects |
| a11y.filter | Filter |
| a11y.more | More |

## Detail
| Key | String |
|---|---|
| detail.subtitle | {i} / {n} · + JPG (Timeline) / Group · {i} / {n} · + JPG (Group Focus) |
| detail.subtitle.rejected | Rejected (accessibility label only) |
| detail.zoom | 100% |
| info.section.capture | Capture |
| info.section.file | File |
| a11y.reject / a11y.rejected | Reject / Rejected (the marking toolbar's flag action; `flag.slash` / `flag.slash.fill`, owner decision 2026-11-13, #227) |
| a11y.rating | Rating / {n} stars / Unrated (the toolbar's rating action value) |
| a11y.clearRating | Clear rating (the swipe ladder's `star.slash` stage) |
| a11y.label | Label, {color} |
| a11y.info / a11y.undo | Info / Undo |
| a11y.gridToggle | Hide photo grid / Show photo grid (value: Photo Preview / Focus View) |
| a11y.focusToggle | Focus regions (value: On / Off) |
| a11y.focusRegion.* | Autofocus region / Face region / Eye region |
| a11y.collapseGroup | Collapse group (`chevron.down` in filmstrip, `chevron.up` in Photo Preview split grid) |
| detail.focus.status | Analyzing focus regions… / Analyzing faces… / No AF metadata / No faces / Tiny focus region unavailable / Focus region unavailable / Analysis unavailable |

## Folder access accessibility

Counts and companion text remain visible. Only access problems add a subtitle indicator.

| Key | Accessibility label only |
|---|---|
| a11y.save.disconnected | Not connected |
| a11y.save.viewOnly | View only |

## Failure toast (owner decision, 2026-11-11)

| Key | String |
|---|---|
| save.toast.failed | Couldn't save the mark. |
| read.toast.failed | Couldn't read some marks. |

Show one toast per failure burst, above the bottom edge in the Move rejects toast position. Hide it after about six seconds. Announce the toast's copy with VoiceOver, including for partial batch failures. Re-read failed photos and display their file's marks. A sidecar that cannot be read says `read.toast.failed` instead, because nothing was saved. Drive loss uses the error banner instead.

## Groups in detail
| Key | String |
|---|---|
| group.expand | Expand {n} photos |
| group.rejectRest | Reject {n} unmarked |

The active pill sits centred in its own row above the filmstrip (or at the bottom of the stage in Photo Preview when chrome is visible): `"Expand {n} photos"` when browsing an unexpanded multi-photo group stack in Timeline (marking disabled; vertical stage drags gently pulse the pill), and `"Reject {n} unmarked"` in Group Focus once the visible group has both a rated or labeled member and an unmarked member. Both hide with chrome; nothing replaces them.

## Move Rejects
| Key | String |
|---|---|
| move.sheet.title | Move {n} rejected photos |
| move.sheet.body | To _Rejected in this folder. Nothing is deleted. |
| move.sheet.partial | {k} of {n} will move |
| move.sheet.button | Move / Move {k} |
| move.toast.done | Moved {n} to _Rejected |
| move.toast.undo | Undo |
| move.toast.failed | {n} couldn't be moved |
| move.toast.details | Details |
| move.details.title | {n} photos couldn't be moved |
| move.details.subtitle | They stay rejected in place. Nothing was deleted. |
| move.details.done | Done |

## Settings
| Key | String |
|---|---|
| settings.title | Settings |
| settings.appearance | Appearance |
| settings.appearance.summary | {Mode} · {Family} (default: System · Default) |
| settings.appearance.mode | Light / Dark / System |
| settings.appearance.family.* | Default, Catppuccin, Darkroom, Night, Nord, Gruvbox |
| settings.appearance.footer | Photos are never tinted. Only the app around them changes. |
| settings.culling | Culling & marking |
| settings.gestures | Marking gestures |
| settings.zoomedGestures | While zoomed (Rate & switch / Pan) |
| settings.zoomedGestures.footer | Rate & switch keeps one-finger rating and photo switching at fit and while zoomed, and pans with two fingers. Pan pans with one finger and rates with two. |
| settings.ratingScale | Rating scale |
| settings.extendedColourLabels | Extended color labels |
| settings.autoAdvance.destination | After marking (Stay / Next photo / Next unmarked photo) |
| settings.autoAdvance.triggers | Ratings advance / Reject advances / Color labels advance |
| settings.browsing | Browsing & groups |
| settings.groups | Similar groups |
| settings.doubleTap | Double-tap (Zoom to focus / Zoom to tap point / Off) |
| settings.detailZoom.footer | Similar groups keep zoom and position between members. Leaving a group or switching standalone photos returns to fit. |
| settings.photoDisplay | Photo display |
| settings.photoDisplay.mode | Show photos as (RAW / Camera preview) |
| settings.move | Move rejects |
| settings.move.toggle | Move Rejects |
| settings.move.folder | Folder name |
| settings.move.footer | Rejected photos are moved, never deleted. You can still mark and filter Rejects when Move Rejects is off. |
| settings.reset | Reset to defaults |
| settings.reset.alert | Reset settings to defaults? (Cancel / Reset) |

## Errors
| Key | String |
|---|---|
| error.disconnected.subtitle | Not connected (accessibility label of the `externaldrive.badge.xmark` glyph) |
| error.disconnected.banner | The drive disconnected. Reconnect it, then reopen this folder. |
| error.disconnected.action | Reopen |
| error.access.subtitle | View only (accessibility label of the `lock.fill` glyph) |
| error.access.banner | Access to this folder is no longer available. |
| error.access.action | Open |

## Folder preparation (#293)
| Key | String |
|---|---|
| preparation.title | Folder preparation |
| preparation.summary.scanning | Scanning folder… |
| preparation.summary.ready | {ready} of {total} ready |
| preparation.summary.enumerating | Still counting photos in this folder. |
| preparation.summary.partial | Showing partial folder scan. |
| preparation.analysis.title | Focus analysis |
| preparation.analysis.count | {n} of {total} analyzed |
| preparation.previews.title | Previews |
| preparation.previews.count | {n} of {total} prepared |
| preparation.waiting.count | Waiting for photo count |
| preparation.waiting.memory.title | Paused for memory |
| preparation.waiting.memory.detail | Preparation paused while memory is low and will resume automatically. |
| preparation.waiting.disconnected.title | Paused · drive disconnected |
| preparation.waiting.disconnected.detail | Reconnect the drive to continue preparing this folder. |
| preparation.waiting.unavailable.title | Paused · folder unavailable |
| preparation.waiting.unavailable.detail | Reopen the folder to continue preparing photos. |
| preparation.issues.title | Issues |
| preparation.issues.truncated | Showing {shown} of {total} issues |
| a11y.preparation | Folder preparation (hint: Shows folder analysis and preview preparation details.) |
| a11y.preparation.value.complete | Complete, {ready} of {total} ready |
| a11y.preparation.value.issues | Finished with {n} issues, {ready} of {total} ready |

