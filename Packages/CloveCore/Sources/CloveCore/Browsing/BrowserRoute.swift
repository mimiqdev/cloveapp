/// One destination in Clove's browsing flow (PRD P0-13, G1 fold-state row).
///
/// The route names where the browser is, never how a layout draws it. The photo a detail shows
/// lives in ``BrowsingState/currentPhoto``, so the route keeps no copy of that identity. G1's fold-state row puts navigation state outside the layout, so the compact
/// stack and the split layout read the same route and a fold, an unfold or a resize changes only
/// the layout, not the route (PRD P0-14).
public enum BrowserRoute: Hashable, Sendable {
    /// Entry: open a folder, or reopen one from Recents (PRD Entry).
    case entry
    /// The open folder's grid (PRD Grid).
    case grid
    /// Detail of the photo in ``BrowsingState/currentPhoto`` (PRD Detail and marking).
    case detail
    /// Clove's settings, which the same navigation structure reaches from any screen
    /// (PRD Gesture-related settings).
    case settings
}
