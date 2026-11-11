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
| grid.batch.result | Saved {ok} · {failed} failed · Retry (accessibility only; failure bursts announce save.toast.failed) |
| tile.nopreview | No preview |
| a11y.moveRejects | Move rejects |
| a11y.filter | Filter |
| a11y.more | More |

## Detail
| Key | String |
|---|---|
| detail.subtitle | {i} / {n} · + JPG |
| detail.subtitle.rejected | Rejected (accessibility label only) |
| detail.subtitle.failed | Save failed. Double-tap to retry. (accessibility label only) |
| detail.zoom | 100% |
| info.section.capture | Capture |
| info.section.file | File |
| a11y.reject / a11y.rejected | Reject / Rejected |
| a11y.rating | {n} stars |
| a11y.label | Label, {color} |
| a11y.info / a11y.undo | Info / Undo |

## Save glyph accessibility (owner decision, 2026-11-11)

Save glyphs replace visible status words in grid and detail subtitles and in batch results.
The counts and companion text remain visible. V4's error banners retain their words.

| Key | Accessibility label only |
|---|---|
| a11y.save.saved | Saved |
| a11y.save.saving | Saving |
| a11y.save.failed | Save failed. Double-tap to retry. |
| a11y.save.disconnected | Not connected |
| a11y.save.viewOnly | View only |
| a11y.save.cloveOnly | Saved in Clove only |

The Saved in Clove only label retains G1 decision 6's distinction between confirmed app storage and an XMP write.

## Save-failure toast (owner decision, 2026-11-11)

| Key | String |
|---|---|
| save.toast.failed | Some marks weren't saved. |
| save.toast.retry | Retry |

Show one toast per failure burst, above the bottom edge in the Move rejects toast position. Hide it after about six seconds. Retry resends all failed photos through one ordered action. Announce `save.toast.failed` with VoiceOver, including for partial batch failures. Drive loss and lost access use the error banner instead. The marks, Failed glyph, and corner dots remain after the toast hides.

## Group review
| Key | String |
|---|---|
| group.title | Group · {n} photos |
| group.subtitle | {n} undecided |
| group.rejectRest | Reject {n} unmarked |
| group.continue | Continue → |
| group.more.undecided | Undecided only |

Follow the group subtitle with the save glyph described above. Keep the count visible; do not add visible status words.

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
| move.details.done / retry | Done / Try again |

## Settings
| Key | String |
|---|---|
| settings.appearance | Appearance |
| settings.matchSystem | Match system light/dark |
| settings.theme.* | Light, Dark, Darkroom, Night, Catppuccin Latte, Catppuccin Mocha, Nord, Gruvbox |
| settings.appearance.footer | Photos are never tinted. Only the app around them changes. |
| settings.culling | Culling |
| settings.groups | Similar groups |
| settings.autoAdvance | Auto-advance after marking |
| settings.ratingScale | Rating scale · 5 stars |
| settings.move | Move rejects |
| settings.move.toggle | Move Rejects |
| settings.move.folder | Folder name · _Rejected |
| settings.move.footer | Rejected photos are moved, never deleted. |

## Errors
| Key | String |
|---|---|
| error.disconnected.subtitle | Not connected (accessibility label only) |
| error.disconnected.banner | The drive disconnected. Reconnect it, then reopen this folder. |
| error.disconnected.action | Reopen |
| error.access.subtitle | View only (accessibility label only) |
| error.access.banner | Access to this folder is no longer available. |
| error.access.action | Open |
| error.unsaved.title | Some marks haven't finished saving. |
| error.unsaved.leave | Leave anyway |
| error.unsaved.wait | Wait |
