export const title = "Clove browsing workflow";

const isBurst = (v) => {
  const photo = v.currentPhoto;
  return photo === `${String(v.activeFolder).toLowerCase()}0`
    || photo === `${String(v.activeFolder).toLowerCase()}1`;
};

export function state(v) {
  if (v.route === "Entry") return "Entry";
  if (v.route === "Grid") {
    if (v.scanning) return "Opening folder";
    return v.grouped ? "Grid · Grouped" : "Grid · Flat";
  }
  if (v.route === "Timeline") {
    if (v.grouped && isBurst(v)) return "Detail Timeline · collapsed burst";
    return "Detail Timeline · photo";
  }
  return v.scale === "100" ? "Group Focus · 100%" : "Group Focus · fit";
}

export function group(v) {
  if (!v.connected && v.activeFolder !== "none") return "Unavailable";
  if (v.route === "Entry" || v.scanning) return "Folder";
  if (v.route === "Grid") return "Grid";
  if (v.route === "Timeline") return "Timeline";
  return "Group Focus";
}

export const colors = {
  Folder: "blue",
  Grid: "teal",
  Timeline: "purple",
  "Group Focus": "orange",
  Unavailable: "pink",
};

export function step(action, from, to) {
  const labels = {
    OpenFolder: "you open a folder",
    CloseFolder: "you close the folder",
    Reconnect: "you reconnect the folder",
    ScanFinish: "the fresh scan finishes",
    SetGrouping: to.grouped ? "you show grouped stacks" : "you show a flat grid",
    LoseLocation: "the folder location is lost",
    OpenPhoto: "you open a standalone photo",
    OpenBurst: "you open the burst at its Representative",
    ExpandGroup: "you expand the collapsed burst",
    CollapseGroup: "you fold back to the Representative",
    Back: "you go back to Grid",
    StepTimeline: "you move across Timeline",
    StepGroup: "you move inside the burst",
    Inspect100: "you inspect at 100%",
    ReturnFit: "you return to fit",
    Mark: `you mark the photo ${to.marks?.[to.currentPhoto] === "R" ? "Rated" : "Rejected"}`,
    UndoLastMark: "you undo the last mark",
    FireAdvance: "auto-advance fires",
    BeginWrite: "the oldest action starts writing",
    CompleteDisk: "the active disk write completes",
    RecordWrite: "the library records the completed action",
    ReadConfirmation: "the scene reads the confirmation and preserves desired input",
    FinishWrite: "the consumer returns and starts the next queued action",
    StaleResult: "an old scan or preparation callback arrives",
  };
  return labels[action] ?? action;
}
