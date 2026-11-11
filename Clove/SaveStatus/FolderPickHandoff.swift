import Foundation

/// Joins the picker delegate's choice and the sheet's dismissal, in either order.
struct FolderPickHandoff {
    struct Presentation: Hashable, Identifiable {
        let id: UInt64
    }

    private enum Phase {
        case waiting(picked: URL?, dismissed: Bool)
        case finished
    }

    private(set) var presentation: Presentation?
    private var nextID: UInt64 = 0
    private var phase: Phase = .finished

    mutating func beginPresentation() -> Presentation {
        nextID += 1
        let next = Presentation(id: nextID)
        presentation = next
        phase = .waiting(picked: nil, dismissed: false)
        return next
    }

    mutating func picked(_ url: URL, from source: Presentation) -> URL? {
        guard source == presentation, case .waiting(nil, let dismissed) = phase else { return nil }
        phase = .waiting(picked: url, dismissed: dismissed)
        return takeReadyPick()
    }

    mutating func dismissed(_ source: Presentation) -> URL? {
        guard source == presentation, case .waiting(let picked, _) = phase else { return nil }
        phase = .waiting(picked: picked, dismissed: true)
        return takeReadyPick()
    }

    mutating func cancel(_ source: Presentation) {
        guard source == presentation else { return }
        phase = .finished
    }

    private mutating func takeReadyPick() -> URL? {
        guard case .waiting(let url?, true) = phase else { return nil }
        phase = .finished
        return url
    }
}
