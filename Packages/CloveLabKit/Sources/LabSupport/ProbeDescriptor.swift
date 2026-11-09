import Foundation

/// Static description of one lab probe, so Clove Lab lists every probe without
/// duplicating the identifiers and questions from the plan.
public struct ProbeDescriptor: Sendable, Hashable, Identifiable {
    /// Probe identifier used in report file names, for example `S2`.
    public let id: String
    /// The probe's question, as written in `docs/DEV-PLAN.md`.
    public let question: String

    public init(id: String, question: String) {
        self.id = id
        self.question = question
    }
}
