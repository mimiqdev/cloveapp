----------------------- MODULE BrowsingWorkflow -----------------------
EXTENDS Naturals, Sequences, FiniteSets

CONSTANTS MaxSteps, MaxPending

Folders == {"A", "B"}
Photos == {"a0", "a1", "aS", "b0", "b1", "bS"}
NoFolder == "none"
NoPhoto == "none"
NoAdvance == [kind |-> "none", target |-> "none", source |-> "none", secondPass |-> FALSE]
NoUndo == [folder |-> "none", generation |-> 0, photo |-> "none", before |-> "U", after |-> "U"]

FolderOf == [
    a0 |-> "A", a1 |-> "A", aS |-> "A",
    b0 |-> "B", b1 |-> "B", bS |-> "B"
]
Standalone(f) == IF f = "A" THEN "aS" ELSE "bS"
Member(f, i) ==
    IF f = "A" THEN (IF i = 1 THEN "a0" ELSE "a1")
    ELSE (IF i = 1 THEN "b0" ELSE "b1")
MemberSet(f) == {Member(f, 1), Member(f, 2)}
FolderPhotos(f) == MemberSet(f) \union {Standalone(f)}

Representative(f, m) ==
    IF m[Member(f, 1)] = "R" THEN Member(f, 1)
    ELSE IF m[Member(f, 2)] = "R" THEN Member(f, 2)
    ELSE IF m[Member(f, 1)] = "U" THEN Member(f, 1)
    ELSE IF m[Member(f, 2)] = "U" THEN Member(f, 2)
    ELSE Member(f, 1)

TimelineLength(grouped) == IF grouped THEN 2 ELSE 3
TimelineIndex(f, p, grouped) ==
    IF grouped THEN (IF p = Standalone(f) THEN 2 ELSE 1)
    ELSE IF p = Member(f, 1) THEN 1
    ELSE IF p = Member(f, 2) THEN 2
    ELSE 3
TimelinePhotoAt(f, i, grouped, m) ==
    IF grouped THEN
        IF i = 1 THEN Representative(f, m) ELSE Standalone(f)
    ELSE
        IF i = 1 THEN Member(f, 1)
        ELSE IF i = 2 THEN Member(f, 2)
        ELSE Standalone(f)

NextUnmarkedAfter(f, p, m) ==
    IF p = Member(f, 1) /\ m[Member(f, 2)] = "U" THEN Member(f, 2)
    ELSE IF p = Member(f, 2) /\ m[Member(f, 1)] = "U" THEN Member(f, 1)
    ELSE NoPhoto
NextGroupMember(f, p) ==
    IF p = Member(f, 1) THEN Member(f, 2) ELSE NoPhoto
HasUnmarked(f, m) ==
    m[Member(f, 1)] = "U" \/ m[Member(f, 2)] = "U"

TimelineAdvance(f, p, grouped, m) ==
    LET i == TimelineIndex(f, p, grouped)
    IN IF i < TimelineLength(grouped) THEN
        [kind |-> "timeline", target |-> TimelinePhotoAt(f, i + 1, grouped, m),
         source |-> f, secondPass |-> FALSE]
       ELSE NoAdvance

GroupAdvanceBeforeMark(f, p, m) ==
    IF ~HasUnmarked(f, m) THEN
        IF NextGroupMember(f, p) = NoPhoto THEN NoAdvance
        ELSE [kind |-> "group", target |-> NextGroupMember(f, p),
              source |-> f, secondPass |-> TRUE]
    ELSE IF NextUnmarkedAfter(f, p, m) /= NoPhoto THEN
        [kind |-> "group", target |-> NextUnmarkedAfter(f, p, m),
         source |-> f, secondPass |-> FALSE]
    ELSE
        [kind |-> "exit", target |-> Standalone(f),
         source |-> f, secondPass |-> FALSE]

VARIABLES
    route,
    activeFolder,
    generation,
    scanning,
    grouped,
    connected,
    expandedGroup,
    currentPhoto,
    scale,
    anchor,
    diskMarks,
    marks,
    sourceGeneration,
    writeQueue,
    writePhase,
    desired,
    confirmedMarks,
    libraryMarks,
    retiredGeneration,
    undo,
    advance,
    event,
    steps

vars == <<
    route, activeFolder, generation, scanning, grouped, connected, expandedGroup,
    currentPhoto, scale, anchor, diskMarks, marks, sourceGeneration, writeQueue,
    writePhase, desired, confirmedMarks, libraryMarks, retiredGeneration, undo, advance, event, steps
>>

BaseEvent(a, oldScale, oldAnchor, oldPhoto, oldRoute, oldExpanded) == [
    action |-> a,
    writeApplied |-> FALSE,
    writeGeneration |-> 0,
    writeFolder |-> NoFolder,
    writePhoto |-> NoPhoto,
    firedKind |-> "none",
    firedSecondPass |-> FALSE,
    firedSource |-> NoFolder,
    oldScale |-> oldScale,
    oldAnchor |-> oldAnchor,
    oldPhoto |-> oldPhoto,
    oldRoute |-> oldRoute,
    oldExpanded |-> oldExpanded,
    undoPhoto |-> NoPhoto,
    undoBefore |-> "U",
    completedValue |-> "U",
    oldShown |-> "U",
    lastPendingValue |-> "none",
    oldQueueLength |-> 0,
    oldWritePhase |-> "idle",
    oldActiveValue |-> "none"
]
Event(a) == [BaseEvent(a, scale, anchor, currentPhoto, route, expandedGroup) EXCEPT
    !.oldShown = IF currentPhoto \in Photos THEN marks[currentPhoto] ELSE "U",
    !.lastPendingValue = IF writeQueue /= <<>> THEN writeQueue[Len(writeQueue)].value ELSE "none",
    !.oldQueueLength = Len(writeQueue), !.oldWritePhase = writePhase,
    !.oldActiveValue = IF writeQueue /= <<>> THEN Head(writeQueue).value ELSE "none"]

Init ==
    /\ route = "Entry"
    /\ activeFolder = NoFolder
    /\ generation = 0
    /\ scanning = FALSE
    /\ grouped = TRUE
    /\ connected = TRUE
    /\ expandedGroup = NoFolder
    /\ currentPhoto = NoPhoto
    /\ scale = "fit"
    /\ anchor = "centre"
    /\ diskMarks = [p \in Photos |-> "U"]
    /\ marks = diskMarks
    /\ sourceGeneration = [p \in Photos |-> 0]
    /\ writeQueue = <<>>
    /\ writePhase = "idle"
    /\ desired = [p \in Photos |-> "none"]
    /\ confirmedMarks = diskMarks
    /\ libraryMarks = diskMarks
    /\ retiredGeneration = 0
    /\ undo = NoUndo
    /\ advance = NoAdvance
    /\ event = BaseEvent("Init", "fit", "centre", NoPhoto, "Entry", NoFolder)
    /\ steps = 0

OpenFolder(f) ==
    /\ route = "Entry"
    /\ f \in Folders
    /\ writeQueue = <<>>
    /\ writePhase = "idle"
    /\ steps < MaxSteps
    /\ generation' = generation + 1
    /\ retiredGeneration' = generation
    /\ activeFolder' = f
    /\ route' = "Grid"
    /\ scanning' = TRUE
    /\ connected' = TRUE
    /\ expandedGroup' = NoFolder
    /\ currentPhoto' = NoPhoto
    /\ scale' = "fit"
    /\ anchor' = "centre"
    /\ undo' = NoUndo
    /\ advance' = NoAdvance
    /\ event' = Event("OpenFolder")
    /\ steps' = steps + 1
    /\ UNCHANGED <<grouped, diskMarks, marks, sourceGeneration, writeQueue,
                   writePhase, desired, confirmedMarks, libraryMarks>>

CloseFolder ==
    /\ route = "Grid"
    /\ writeQueue = <<>>
    /\ writePhase = "idle"
    /\ steps < MaxSteps
    /\ generation' = generation + 1
    /\ retiredGeneration' = generation
    /\ activeFolder' = NoFolder
    /\ route' = "Entry"
    /\ scanning' = FALSE
    /\ connected' = TRUE
    /\ expandedGroup' = NoFolder
    /\ currentPhoto' = NoPhoto
    /\ scale' = "fit"
    /\ anchor' = "centre"
    /\ undo' = NoUndo
    /\ advance' = NoAdvance
    /\ event' = Event("CloseFolder")
    /\ steps' = steps + 1
    /\ UNCHANGED <<grouped, diskMarks, marks, sourceGeneration, writeQueue,
                   writePhase, desired, confirmedMarks, libraryMarks>>

Reconnect ==
    /\ activeFolder \in Folders
    /\ ~connected
    /\ writeQueue = <<>>
    /\ writePhase = "idle"
    /\ steps < MaxSteps
    /\ generation' = generation + 1
    /\ retiredGeneration' = generation
    /\ route' = "Grid"
    /\ scanning' = TRUE
    /\ connected' = TRUE
    /\ expandedGroup' = NoFolder
    /\ currentPhoto' = NoPhoto
    /\ scale' = "fit"
    /\ anchor' = "centre"
    /\ undo' = NoUndo
    /\ advance' = NoAdvance
    /\ event' = Event("Reconnect")
    /\ steps' = steps + 1
    /\ UNCHANGED <<activeFolder, grouped, diskMarks, marks, sourceGeneration,
                   writeQueue, writePhase, desired, confirmedMarks, libraryMarks>>

ScanFinish ==
    /\ activeFolder \in Folders
    /\ scanning
    /\ steps < MaxSteps
    /\ scanning' = FALSE
    /\ confirmedMarks' = [p \in Photos |-> IF FolderOf[p] = activeFolder THEN diskMarks[p] ELSE confirmedMarks[p]]
    /\ libraryMarks' = [p \in Photos |-> IF FolderOf[p] = activeFolder THEN diskMarks[p] ELSE libraryMarks[p]]
    /\ marks' = [p \in Photos |->
        IF FolderOf[p] = activeFolder THEN diskMarks[p] ELSE marks[p]]
    /\ sourceGeneration' = [p \in Photos |->
        IF FolderOf[p] = activeFolder THEN generation ELSE sourceGeneration[p]]
    /\ event' = Event("ScanFinish")
    /\ steps' = steps + 1
    /\ UNCHANGED <<route, activeFolder, generation, grouped, connected, expandedGroup,
                   currentPhoto, scale, anchor, diskMarks, writeQueue,
                   writePhase, desired, retiredGeneration, undo, advance>>

SetGrouping(value) ==
    /\ route = "Grid"
    /\ activeFolder \in Folders
    /\ ~scanning
    /\ grouped /= value
    /\ steps < MaxSteps
    /\ grouped' = value
    /\ event' = Event("SetGrouping")
    /\ steps' = steps + 1
    /\ UNCHANGED <<route, activeFolder, generation, scanning, connected, expandedGroup,
                   currentPhoto, scale, anchor, diskMarks, marks, sourceGeneration,
                   writeQueue, writePhase, desired, confirmedMarks, libraryMarks, retiredGeneration, undo, advance>>

LoseLocation ==
    /\ activeFolder \in Folders
    /\ connected
    /\ steps < MaxSteps
    /\ connected' = FALSE
    /\ marks' = [p \in Photos |->
        IF FolderOf[p] = activeFolder THEN confirmedMarks[p] ELSE marks[p]]
    /\ desired' = [p \in Photos |-> "none"]
    /\ writeQueue' = IF writePhase = "idle" THEN <<>> ELSE <<Head(writeQueue)>>
    /\ undo' = NoUndo
    /\ event' = Event("LoseLocation")
    /\ steps' = steps + 1
    /\ UNCHANGED <<route, activeFolder, generation, scanning, grouped, expandedGroup,
                   currentPhoto, scale, anchor, diskMarks, sourceGeneration,
                   writePhase, confirmedMarks, libraryMarks, retiredGeneration, advance>>

OpenPhoto(p) ==
    /\ route = "Grid"
    /\ activeFolder \in Folders
    /\ ~scanning
    /\ p \in FolderPhotos(activeFolder)
    /\ (~grouped \/ p = Standalone(activeFolder))
    /\ steps < MaxSteps
    /\ route' = "Timeline"
    /\ expandedGroup' = NoFolder
    /\ currentPhoto' = p
    /\ scale' = "fit"
    /\ anchor' = "centre"
    /\ advance' = NoAdvance
    /\ event' = Event("OpenPhoto")
    /\ steps' = steps + 1
    /\ UNCHANGED <<activeFolder, generation, scanning, grouped, connected, diskMarks,
                   marks, sourceGeneration, writeQueue, writePhase, desired, confirmedMarks, libraryMarks, retiredGeneration, undo>>

OpenBurst ==
    /\ route = "Grid"
    /\ activeFolder \in Folders
    /\ ~scanning
    /\ grouped
    /\ steps < MaxSteps
    /\ route' = "GroupFocus"
    /\ expandedGroup' = activeFolder
    /\ currentPhoto' = Representative(activeFolder, marks)
    /\ scale' = "fit"
    /\ anchor' = "centre"
    /\ advance' = NoAdvance
    /\ event' = Event("OpenBurst")
    /\ steps' = steps + 1
    /\ UNCHANGED <<activeFolder, generation, scanning, grouped, connected, diskMarks,
                   marks, sourceGeneration, writeQueue, writePhase, desired, confirmedMarks, libraryMarks, retiredGeneration, undo>>

ExpandGroup ==
    /\ route = "Timeline"
    /\ activeFolder \in Folders
    /\ grouped
    /\ currentPhoto \in MemberSet(activeFolder)
    /\ steps < MaxSteps
    /\ route' = "GroupFocus"
    /\ expandedGroup' = activeFolder
    /\ advance' = NoAdvance
    /\ event' = Event("ExpandGroup")
    /\ steps' = steps + 1
    /\ UNCHANGED <<activeFolder, generation, scanning, grouped, connected, currentPhoto,
                   scale, anchor, diskMarks, marks, sourceGeneration, writeQueue,
                   writePhase, desired, confirmedMarks, libraryMarks, retiredGeneration, undo>>

CollapseGroup ==
    /\ route = "GroupFocus"
    /\ activeFolder \in Folders
    /\ expandedGroup = activeFolder
    /\ steps < MaxSteps
    /\ route' = "Timeline"
    /\ expandedGroup' = NoFolder
    /\ currentPhoto' = Representative(activeFolder, marks)
    /\ scale' = IF currentPhoto = Representative(activeFolder, marks) THEN scale ELSE "fit"
    /\ anchor' = IF currentPhoto = Representative(activeFolder, marks) THEN anchor ELSE "centre"
    /\ advance' = NoAdvance
    /\ event' = Event("CollapseGroup")
    /\ steps' = steps + 1
    /\ UNCHANGED <<activeFolder, generation, scanning, grouped, connected, diskMarks,
                   marks, sourceGeneration, writeQueue, writePhase, desired, confirmedMarks, libraryMarks, retiredGeneration, undo>>

Back ==
    /\ route \in {"Timeline", "GroupFocus"}
    /\ steps < MaxSteps
    /\ route' = "Grid"
    /\ expandedGroup' = NoFolder
    /\ scale' = "fit"
    /\ anchor' = "centre"
    /\ advance' = NoAdvance
    /\ event' = Event("Back")
    /\ steps' = steps + 1
    /\ UNCHANGED <<activeFolder, generation, scanning, grouped, connected, currentPhoto,
                   diskMarks, marks, sourceGeneration, writeQueue,
                   writePhase, desired, confirmedMarks, libraryMarks, retiredGeneration, undo>>

StepTimeline(offset) ==
    /\ route = "Timeline"
    /\ activeFolder \in Folders
    /\ offset \in {0 - 1, 1}
    /\ TimelineIndex(activeFolder, currentPhoto, grouped) + offset \in
        1..TimelineLength(grouped)
    /\ steps < MaxSteps
    /\ currentPhoto' = TimelinePhotoAt(
        activeFolder, TimelineIndex(activeFolder, currentPhoto, grouped) + offset,
        grouped, marks)
    /\ expandedGroup' = NoFolder
    /\ scale' = "fit"
    /\ anchor' = "centre"
    /\ advance' = NoAdvance
    /\ event' = Event("StepTimeline")
    /\ steps' = steps + 1
    /\ UNCHANGED <<route, activeFolder, generation, scanning, grouped, connected,
                   diskMarks, marks, sourceGeneration, writeQueue,
                   writePhase, desired, confirmedMarks, libraryMarks, retiredGeneration, undo>>

StepGroup(offset) ==
    /\ route = "GroupFocus"
    /\ activeFolder \in Folders
    /\ expandedGroup = activeFolder
    /\ currentPhoto \in MemberSet(activeFolder)
    /\ offset \in {0 - 1, 1}
    /\ (currentPhoto = Member(activeFolder, 1) /\ offset = 1)
        \/ (currentPhoto = Member(activeFolder, 2) /\ offset = 0 - 1)
    /\ steps < MaxSteps
    /\ currentPhoto' = IF offset = 1 THEN Member(activeFolder, 2) ELSE Member(activeFolder, 1)
    /\ advance' = NoAdvance
    /\ event' = Event("StepGroup")
    /\ steps' = steps + 1
    /\ UNCHANGED <<route, activeFolder, generation, scanning, grouped, connected,
                   expandedGroup, scale, anchor, diskMarks, marks, sourceGeneration,
                   writeQueue, writePhase, desired, confirmedMarks, libraryMarks, retiredGeneration, undo>>

Inspect100 ==
    /\ route \in {"Timeline", "GroupFocus"}
    /\ scale = "fit"
    /\ steps < MaxSteps
    /\ scale' = "100"
    /\ anchor' = "eye"
    /\ event' = Event("Inspect100")
    /\ steps' = steps + 1
    /\ UNCHANGED <<route, activeFolder, generation, scanning, grouped, connected,
                   expandedGroup, currentPhoto, diskMarks, marks, sourceGeneration,
                   writeQueue, writePhase, desired, confirmedMarks, libraryMarks, retiredGeneration, undo, advance>>

ReturnFit ==
    /\ route \in {"Timeline", "GroupFocus"}
    /\ scale /= "fit"
    /\ steps < MaxSteps
    /\ scale' = "fit"
    /\ anchor' = "centre"
    /\ event' = Event("ReturnFit")
    /\ steps' = steps + 1
    /\ UNCHANGED <<route, activeFolder, generation, scanning, grouped, connected,
                   expandedGroup, currentPhoto, diskMarks, marks, sourceGeneration,
                   writeQueue, writePhase, desired, confirmedMarks, libraryMarks, retiredGeneration, undo, advance>>

CanMarkCurrent ==
    /\ activeFolder \in Folders
    /\ connected
    /\ ~scanning
    /\ route \in {"Timeline", "GroupFocus"}
    /\ currentPhoto \in FolderPhotos(activeFolder)
    /\ (route = "GroupFocus" \/ ~grouped \/ currentPhoto = Standalone(activeFolder))

Mark(p, value) ==
    /\ CanMarkCurrent
    /\ p = currentPhoto
    /\ value \in {"R", "X"}
    /\ marks[p] /= value
    /\ Len(writeQueue) < MaxPending
    /\ steps < MaxSteps
    /\ marks' = [marks EXCEPT ![p] = value]
    /\ sourceGeneration' = [sourceGeneration EXCEPT ![p] = generation]
    /\ writeQueue' = Append(writeQueue, [photo |-> p, value |-> value, generation |-> generation])
    /\ desired' = [desired EXCEPT ![p] = value]
    /\ undo' = [folder |-> activeFolder, generation |-> generation,
                photo |-> p, before |-> marks[p], after |-> value]
    /\ advance' =
        IF route = "GroupFocus" THEN GroupAdvanceBeforeMark(activeFolder, p, marks)
        ELSE TimelineAdvance(activeFolder, p, grouped, marks)
    /\ event' = Event("Mark")
    /\ steps' = steps + 1
    /\ UNCHANGED <<route, activeFolder, generation, scanning, grouped, connected,
                   expandedGroup, currentPhoto, scale, anchor, diskMarks, writePhase, confirmedMarks, libraryMarks, retiredGeneration>>

UndoLastMark ==
    /\ (undo /= NoUndo)
    /\ activeFolder \in Folders
    /\ connected
    /\ ~scanning
    /\ undo.folder = activeFolder
    /\ undo.generation = generation
    /\ marks[undo.photo] = undo.after
    /\ Len(writeQueue) < MaxPending
    /\ steps < MaxSteps
    /\ marks' = [marks EXCEPT ![undo.photo] = undo.before]
    /\ sourceGeneration' = [sourceGeneration EXCEPT ![undo.photo] = generation]
    /\ writeQueue' = Append(writeQueue, [photo |-> undo.photo, value |-> undo.before, generation |-> generation])
    /\ desired' = [desired EXCEPT ![undo.photo] = undo.before]
    /\ route' = IF grouped /\ undo.photo \in MemberSet(activeFolder)
        THEN "GroupFocus" ELSE "Timeline"
    /\ expandedGroup' = IF grouped /\ undo.photo \in MemberSet(activeFolder)
        THEN activeFolder ELSE NoFolder
    /\ currentPhoto' = undo.photo
    /\ scale' = IF route = "GroupFocus" /\ expandedGroup = activeFolder
        /\ undo.photo \in MemberSet(activeFolder) THEN scale ELSE "fit"
    /\ anchor' = IF route = "GroupFocus" /\ expandedGroup = activeFolder
        /\ undo.photo \in MemberSet(activeFolder) THEN anchor ELSE "centre"
    /\ undo' = NoUndo
    /\ advance' = NoAdvance
    /\ event' = [Event("UndoLastMark") EXCEPT !.undoPhoto = undo.photo, !.undoBefore = undo.before]
    /\ steps' = steps + 1
    /\ UNCHANGED <<activeFolder, generation, scanning, grouped, connected, diskMarks, writePhase, confirmedMarks, libraryMarks, retiredGeneration>>

HasQueuedPhoto(p) == \E i \in 2..Len(writeQueue): writeQueue[i].photo = p
CanPublish ==
    /\ connected
    /\ activeFolder = FolderOf[Head(writeQueue).photo]
    /\ generation = Head(writeQueue).generation

BeginWrite ==
    /\ writeQueue /= <<>>
    /\ writePhase = "idle"
    /\ CanPublish
    /\ steps < MaxSteps
    /\ writePhase' = "writing"
    /\ event' = Event("BeginWrite")
    /\ steps' = steps + 1
    /\ UNCHANGED <<route, activeFolder, generation, scanning, grouped, connected,
                   expandedGroup, currentPhoto, scale, anchor, diskMarks, marks,
                   sourceGeneration, writeQueue, desired, confirmedMarks, libraryMarks,
                   retiredGeneration, undo, advance>>

CompleteDisk ==
    /\ writeQueue /= <<>>
    /\ writePhase = "writing"
    /\ steps < MaxSteps
    /\ diskMarks' = [diskMarks EXCEPT ![Head(writeQueue).photo] = Head(writeQueue).value]
    /\ writePhase' = "diskDone"
    /\ event' = [Event("CompleteDisk") EXCEPT
        !.writePhoto = Head(writeQueue).photo, !.completedValue = Head(writeQueue).value]
    /\ steps' = steps + 1
    /\ UNCHANGED <<route, activeFolder, generation, scanning, grouped, connected,
                   expandedGroup, currentPhoto, scale, anchor, marks, sourceGeneration,
                   writeQueue, desired, confirmedMarks, libraryMarks, retiredGeneration,
                   undo, advance>>

RecordWrite ==
    /\ writeQueue /= <<>>
    /\ writePhase = "diskDone"
    /\ steps < MaxSteps
    /\ libraryMarks' = [libraryMarks EXCEPT ![Head(writeQueue).photo] = Head(writeQueue).value]
    /\ writePhase' = "recorded"
    /\ event' = Event("RecordWrite")
    /\ steps' = steps + 1
    /\ UNCHANGED <<route, activeFolder, generation, scanning, grouped, connected,
                   expandedGroup, currentPhoto, scale, anchor, diskMarks, marks,
                   sourceGeneration, writeQueue, desired, confirmedMarks, retiredGeneration,
                   undo, advance>>

ReadConfirmation ==
    /\ activeFolder \in Folders
    /\ ~scanning
    /\ \E p \in FolderPhotos(activeFolder): libraryMarks[p] /= confirmedMarks[p]
    /\ steps < MaxSteps
    /\ confirmedMarks' = libraryMarks
    /\ marks' = [p \in Photos |-> IF desired[p] /= "none" THEN desired[p] ELSE libraryMarks[p]]
    /\ event' = Event("ReadConfirmation")
    /\ steps' = steps + 1
    /\ UNCHANGED <<route, activeFolder, generation, scanning, grouped, connected,
                   expandedGroup, currentPhoto, scale, anchor, diskMarks, sourceGeneration,
                   writeQueue, writePhase, desired, libraryMarks, retiredGeneration, undo, advance>>

FinishWrite ==
    /\ writeQueue /= <<>>
    /\ writePhase = "recorded"
    /\ steps < MaxSteps
    /\ writeQueue' = Tail(writeQueue)
    \* The consumer loops to beginNext without suspension after persist returns.
    /\ writePhase' = IF Len(writeQueue) > 1 /\ connected THEN "writing" ELSE "idle"
    /\ desired' = IF CanPublish /\ ~HasQueuedPhoto(Head(writeQueue).photo)
        THEN [desired EXCEPT ![Head(writeQueue).photo] = "none"] ELSE desired
    /\ confirmedMarks' = IF CanPublish THEN libraryMarks ELSE confirmedMarks
    /\ marks' = IF CanPublish THEN
        [p \in Photos |-> IF desired'[p] /= "none" THEN desired'[p] ELSE libraryMarks[p]] ELSE marks
    /\ event' = [Event("FinishWrite") EXCEPT
        !.writeApplied = CanPublish,
        !.writeGeneration = Head(writeQueue).generation,
        !.writeFolder = FolderOf[Head(writeQueue).photo], !.writePhoto = Head(writeQueue).photo]
    /\ steps' = steps + 1
    /\ UNCHANGED <<route, activeFolder, generation, scanning, grouped, connected,
                   expandedGroup, currentPhoto, scale, anchor, diskMarks,
                   sourceGeneration, libraryMarks, retiredGeneration, undo, advance>>

\* A buffered old-generation callback. Writes drain before replacement; they cannot supply
\* a realistic stale-write witness. This deliberately hostile callback probes the boundary
\* shared by generation-checked scan/preparation publications instead.
StaleResult ==
    /\ activeFolder \in Folders
    /\ retiredGeneration > 0
    /\ steps < MaxSteps
    /\ sourceGeneration' = IF retiredGeneration = generation
        THEN [p \in Photos |-> retiredGeneration] ELSE sourceGeneration
    /\ event' = Event("StaleResult")
    /\ steps' = steps + 1
    /\ UNCHANGED <<route, activeFolder, generation, scanning, grouped, connected,
                   expandedGroup, currentPhoto, scale, anchor, diskMarks, marks,
                   writeQueue, writePhase, desired, confirmedMarks, libraryMarks,
                   retiredGeneration, undo, advance>>

FireAdvance ==
    /\ advance /= NoAdvance
    /\ steps < MaxSteps
    /\ route' = IF advance.kind = "group" THEN "GroupFocus" ELSE "Timeline"
    /\ expandedGroup' = IF advance.kind = "group" THEN advance.source ELSE NoFolder
    /\ currentPhoto' = advance.target
    /\ scale' = IF advance.kind = "group" THEN scale ELSE "fit"
    /\ anchor' = IF advance.kind = "group" THEN anchor ELSE "centre"
    /\ advance' = NoAdvance
    /\ event' = [Event("FireAdvance") EXCEPT
        !.firedKind = advance.kind,
        !.firedSecondPass = advance.secondPass,
        !.firedSource = advance.source]
    /\ steps' = steps + 1
    /\ UNCHANGED <<activeFolder, generation, scanning, grouped, connected, diskMarks,
                   marks, sourceGeneration, writeQueue, writePhase, desired, confirmedMarks, libraryMarks, retiredGeneration, undo>>

Next ==
    \/ \E f \in Folders: OpenFolder(f)
    \/ CloseFolder
    \/ Reconnect
    \/ ScanFinish
    \/ \E value \in BOOLEAN: SetGrouping(value)
    \/ LoseLocation
    \/ \E p \in Photos: OpenPhoto(p)
    \/ OpenBurst
    \/ ExpandGroup
    \/ CollapseGroup
    \/ Back
    \/ \E offset \in {0 - 1, 1}: StepTimeline(offset) \/ StepGroup(offset)
    \/ Inspect100
    \/ ReturnFit
    \/ \E p \in Photos, value \in {"R", "X"}: Mark(p, value)
    \/ UndoLastMark
    \/ BeginWrite
    \/ CompleteDisk
    \/ RecordWrite
    \/ ReadConfirmation
    \/ FinishWrite
    \/ StaleResult
    \/ FireAdvance

TypeOK ==
    /\ route \in {"Entry", "Grid", "Timeline", "GroupFocus"}
    /\ activeFolder \in Folders \union {NoFolder}
    /\ generation \in Nat
    /\ scanning \in BOOLEAN
    /\ grouped \in BOOLEAN
    /\ connected \in BOOLEAN
    /\ expandedGroup \in Folders \union {NoFolder}
    /\ currentPhoto \in Photos \union {NoPhoto}
    /\ scale \in {"fit", "100"}
    /\ anchor \in {"centre", "eye"}
    /\ Len(writeQueue) <= MaxPending
    /\ writePhase \in {"idle", "writing", "diskDone", "recorded"}
    /\ (writePhase /= "idle" => Len(writeQueue) > 0)
    /\ steps \in 0..MaxSteps

BackReturnsToGrid ==
    event.action = "Back" => route = "Grid" /\ expandedGroup = NoFolder

StandaloneOpensTimeline ==
    event.action = "OpenPhoto" => route = "Timeline" /\ expandedGroup = NoFolder

BurstOpensRepresentativeGroupFocus ==
    event.action = "OpenBurst" =>
        /\ route = "GroupFocus"
        /\ expandedGroup = activeFolder
        /\ currentPhoto = Representative(activeFolder, marks)

CollapsedStackIsReadOnly ==
    ~(event.action = "Mark" /\ event.oldRoute = "Timeline" /\ grouped
      /\ event.oldPhoto \in MemberSet(activeFolder))

GroupFocusStaysWithinVisibleMembers ==
    route = "GroupFocus" =>
        /\ grouped
        /\ activeFolder \in Folders
        /\ expandedGroup = activeFolder
        /\ currentPhoto \in MemberSet(activeFolder)

GroupNavigationKeepsZoom ==
    (event.action = "StepGroup"
     \/ (event.action = "FireAdvance" /\ event.firedKind = "group")) =>
        scale = event.oldScale /\ anchor = event.oldAnchor

OutsideGroupNavigationReturnsFit ==
    event.action \in {"OpenPhoto", "StepTimeline", "Back"} =>
        scale = "fit" /\ anchor = "centre"

CollapseZoomFollowsRepresentative ==
    event.action = "CollapseGroup" =>
        IF event.oldPhoto = Representative(activeFolder, marks)
        THEN scale = event.oldScale /\ anchor = event.oldAnchor
        ELSE scale = "fit" /\ anchor = "centre"

CollapseUsesRepresentative ==
    event.action = "CollapseGroup" =>
        /\ route = "Timeline"
        /\ expandedGroup = NoFolder
        /\ currentPhoto = Representative(activeFolder, marks)

OnlyLastUnmarkedPlansGroupExit ==
    event.action = "Mark" /\ advance.kind = "exit" =>
        ~HasUnmarked(advance.source, marks)

LastUnmarkedAdvanceLeavesGroup ==
    event.action = "FireAdvance" /\ event.firedKind = "exit" =>
        route = "Timeline" /\ expandedGroup = NoFolder

SecondPassNeverPlansGroupExit ==
    event.action = "Mark" /\ advance.secondPass => advance.kind = "group"

SecondPassAdvanceStaysInGroup ==
    event.action = "FireAdvance" /\ event.firedSecondPass =>
        route = "GroupFocus" /\ expandedGroup = event.firedSource

FlatGridHasNoGroupFocus ==
    ~grouped => route /= "GroupFocus" /\ expandedGroup = NoFolder

WriteResultsRequireConnection ==
    event.writeApplied => connected

LostLocationRefusesNewMarks ==
    event.action = "Mark" => connected

WriteResultsUseCurrentGeneration ==
    event.writeApplied =>
        event.writeGeneration = generation /\ event.writeFolder = activeFolder

FreshFolderMarksUseCurrentGeneration ==
    activeFolder \in Folders /\ ~scanning =>
        \A p \in FolderPhotos(activeFolder): sourceGeneration[p] = generation

ReconnectHidesOldState ==
    event.action = "Reconnect" =>
        /\ route = "Grid"
        /\ scanning
        /\ currentPhoto = NoPhoto
        /\ expandedGroup = NoFolder

ScanningNeverShowsOldDetail ==
    scanning => route = "Grid" /\ currentPhoto = NoPhoto /\ expandedGroup = NoFolder

UndoRestoresPriorMark ==
    event.action = "UndoLastMark" => marks[event.undoPhoto] = event.undoBefore

UndoReturnsToTarget ==
    event.action = "UndoLastMark" =>
        /\ currentPhoto = event.undoPhoto
        /\ IF grouped /\ event.undoPhoto \in MemberSet(activeFolder)
           THEN route = "GroupFocus" /\ expandedGroup = activeFolder
           ELSE route = "Timeline" /\ expandedGroup = NoFolder

UndoCancelsAutoAdvance ==
    event.action = "UndoLastMark" => advance = NoAdvance

LatestQueuedValue(p) ==
    LET indices == {i \in DOMAIN writeQueue: writeQueue[i].photo = p}
        latest == CHOOSE i \in indices: \A j \in indices: i >= j
    IN writeQueue[latest].value

NewerDesiredInputWins ==
    /\ \A p \in Photos: desired[p] /= "none" => marks[p] = desired[p]
    /\ connected => \A i \in DOMAIN writeQueue:
        LET p == writeQueue[i].photo IN
            desired[p] = LatestQueuedValue(p) /\ marks[p] = LatestQueuedValue(p)

LocationLossShowsLatestConfirmed ==
    event.action = "LoseLocation" =>
        \A p \in FolderPhotos(activeFolder): marks[p] = confirmedMarks[p] /\ desired[p] = "none"

DiskCompletionIsFIFO ==
    event.action = "CompleteDisk" => diskMarks[event.writePhoto] = event.completedValue

\* Reachability query only. The runner expects this predicate to fail, proving the
\* rated -> rejected -> older rated confirmation -> loss rollback state exists.
NoRatedRollbackWitness ==
    ~(event.action = "LoseLocation" /\ event.oldPhoto = "aS"
      /\ event.oldShown = "X" /\ event.lastPendingValue = "X"
      /\ event.oldQueueLength = 2 /\ event.oldWritePhase = "recorded"
      /\ event.oldActiveValue = "R"
      /\ confirmedMarks["aS"] = "R" /\ marks["aS"] = "R"
      /\ diskMarks["aS"] = "R")

=============================================================================
