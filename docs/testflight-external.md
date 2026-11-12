# External TestFlight materials (draft)

For Clove's App Store Connect beta fields. Replace the feedback email before
inviting external testers. The placeholder app icon stays for this build.

## Beta description

Clove helps photographers choose their keepers on iPhone and iPad. Open a photo
folder through Files, browse RAW and JPEG photos, zoom to check focus, and apply
stars, color labels, or Reject. Compare similar photos with on-device grouping.
RAW sets save marks in XMP sidecars; new standalone JPEG/HIF marks stay in Clove.
Move rejects puts rejected photo sets in a `_Rejected` subfolder after confirmation.
Original image contents stay unchanged.

## What to test

- Open a folder with subfolders and RAW+JPEG/HIF sets, then reopen it from Recents.
- Scroll, sort, and filter the grid; open detail, navigate, pinch, and double-tap
  to inspect focus. Try both iPhone and iPad, in light and dark appearance.
- Apply and clear stars, color labels, and Reject with buttons, swipes, an external
  keyboard, and multi-select. Try auto-advance, enabled star levels, and Undo.
- Compare a similar group with synchronized zoom, use Reject N unmarked, and Undo.
  Run grouping again and try browsing with grouping turned off.
- In Move rejects, keep an individual photo, confirm the move, and Undo. Check that
  companions and XMP move together, with no deleted or overwritten files.
- Quit and reopen to check saved marks. Check RAW ratings and labels in Lightroom,
  Capture One, or Photo Mechanic; standalone JPEG/HIF marks stay in Clove.
- Try an unavailable or read-only folder and reconnect/reopen after a disconnect.
  Report the device, iOS version, file types, and steps for any problem.

## Feedback email

`<FEEDBACK_EMAIL>` — replace with a monitored address before external testing.

## Beta App Review notes

No account, sign-in, or subscription is required. Tap Open folder and choose a
folder containing camera RAW or JPEG photos in Files; local storage is sufficient.
Clove reads only folders the tester selects and does not require Photo Library
access. A writable folder lets the reviewer test marks and Move rejects. RAW marks
write XMP sidecars; standalone JPEG/HIF marks are stored in Clove. Move rejects
requires confirmation, moves sets into `_Rejected`, and supports Undo. Grouping
runs on the device. No external drive is required. The app icon is a placeholder.
