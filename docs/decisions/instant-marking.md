# Instant marking

Status: approved by the owner and supervisor, 2026-11-11. Implementation brief: [#121](https://github.com/mimiqdev/cloveapp/issues/121).

## Decision

A mark appears as soon as the user makes it. Saving follows in the order the user acted. The UI does not wait for storage, and Saved still means confirmed storage.

`DesiredPhotoMarks` is a synchronous CloveCore value. Each photo has desired marks and a revision until that revision or a newer one confirms. Applying a request returns the before and after marks immediately. Every screen, filter, count, and marking rule reads desired marks first, then confirmed marks. A second tap therefore toggles the mark already shown, even while the first write is pending.

A failed write keeps the desired marks visible with the existing Failed glyph and corner dot. Silent reversion would discard the user's decision and contradict PRD How marks reach disk, rule 8. Tapping Failed submits all failed photos as one retry entry. Partial batch failure also posts the accessibility announcement specified in the design handoff.

`PhotoActionPipeline` admits each action synchronously into one FIFO. One consumer finishes all work for an entry before it starts the next. Entries cover a mark, a batch, group finishing, a Move rejects keep, the move itself, move undo, and retries. The before and after records use desired marks. The full undo stack is a later task, and the toolbar Undo remains disabled.

Move rejects waits for earlier writes and then re-plans from the desired rejects and the files on disk. This includes a sidecar created after the confirmation preview. The result records changed counts, and the existing result reports actual moved sets. The move guard blocks marks during file movement. A later queued mark cannot write ahead of the move.

Restoring or retrying a keep or clear compares the complete current desired marks with what the earlier action left. If they differ, the photo stays as it is and the result reports changed since. Field replacement uses `MarkUndoRestorePlan`'s rule. For example, a kept photo rated 3 stars after the move stays at 3 stars when that move is undone.

Closing a folder drains the action pipeline before the session releases its access scope. The leave confirmation counts photos with desired marks not yet confirmed. A failed write is finished for draining and remains unsaved until retry or closing the folder.

## What this replaces

The previous path started a task for each input and showed marks only after `FolderLibrarySession.record` applied a confirmed write. Group culling used a separate overlay for pending marks. Move rejects cleared kept photos and retried clear failures outside the mark path. Those paths, their obsolete execution tests, and the old storage compatibility test are removed.

The new consumer uses C4's existing write queue. Its per-photo coalescing, preserving XMP editor, staging, synchronization, rename, and read-back rules remain the [G1 technical approach](G1-technical-approach.md). RAW marks still go to the shared sidecar, and standalone marks still go to Clove storage. The mover keeps its existing same-volume, exclusive-rename, confirmation, and rollback rules.

## Verification

Core tests cover immediate marks, rapid toggles, revision ordering, retained failures, FIFO barriers, and compare-and-set. Filesystem tests cover a failed keep clear followed by a newer rating, move undo after a newer rating, and a newly created sidecar moving and returning with its RAW. Short UI tests cover failure and recovery, drive loss with retained marks, and informational tap-to-shown timing while a write remains pending. External-drive checks remain on the PR's device checklist.
