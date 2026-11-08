import SpikeS1Access
import SpikeS2Previews
import SpikeS3XMP
import SpikeS4Metadata
import SpikeS5Grouping
import SpikeS6Scan
import SpikeS7Duo
import SpikeSupport
import SwiftUI

/// One M1 spike as Clove Lab lists it.
@MainActor
struct Experiment: Identifiable {
    /// Spike identifier, for example `S2`.
    let id: String
    /// The spike's question, as written in `docs/DEV-PLAN.md`.
    let question: String
    /// The screen the spike shows.
    let makeDestination: @MainActor () -> AnyView

    init(
        _ descriptor: SpikeDescriptor,
        @ViewBuilder destination: @escaping @MainActor () -> some View
    ) {
        self.id = descriptor.id
        self.question = descriptor.question
        self.makeDestination = { AnyView(destination()) }
    }
}

/// The M1 spike registry. All seven spikes are listed from the start, so a spike
/// never edits this file: it replaces its own screen under `CloveLab/Spikes/Sx/`.
@MainActor
enum Experiments {
    static let all: [Experiment] = [
        Experiment(SpikeS1Access.descriptor) { S1View() },
        Experiment(SpikeS2Previews.descriptor) { S2View() },
        Experiment(SpikeS3XMP.descriptor) { S3View() },
        Experiment(SpikeS4Metadata.descriptor) { S4View() },
        Experiment(SpikeS5Grouping.descriptor) { S5View() },
        Experiment(SpikeS6Scan.descriptor) { S6View() },
        Experiment(SpikeS7Duo.descriptor) { S7View() },
    ]
}
