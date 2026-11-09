import Foundation

/// Static description of one M1 spike, so Clove Lab lists every spike without
/// duplicating the identifiers and questions from the plan.
public struct SpikeDescriptor: Sendable, Hashable, Identifiable {
    /// Spike identifier used in report file names, for example `S2`.
    public let id: String
    /// The spike's question, as written in `docs/DEV-PLAN.md`.
    public let question: String

    public init(id: String, question: String) {
        self.id = id
        self.question = question
    }
}
