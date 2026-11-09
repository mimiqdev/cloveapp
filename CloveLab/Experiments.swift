import FolderAccessProbe
import PreviewProbe
import XMPProbe
import EmbeddedMetadataProbe
import GroupingProbe
import ScanProbe
import FoldStateProbe
import LabSupport
import SwiftUI

/// One lab probe as Clove Lab lists it.
@MainActor
struct Experiment: Identifiable {
    /// Probe identifier, for example `S2`.
    let id: String
    /// Checklist identifier shown together with the topic name.
    let title: String
    /// The probe's question, as written in `docs/DEV-PLAN.md`.
    let question: String
    /// The screen the probe shows.
    let makeDestination: @MainActor () -> AnyView

    init(
        _ descriptor: ProbeDescriptor, topic: String,
        @ViewBuilder destination: @escaping @MainActor () -> some View
    ) {
        self.id = descriptor.id
        self.title = "\(descriptor.id) · \(topic)"
        self.question = descriptor.question
        self.makeDestination = { AnyView(destination()) }
    }
}

/// The lab probe registry. All seven probes are listed from the start, so a probe
/// never edits this file: it replaces its own screen under `CloveLab/Probes/<Topic>/`.
@MainActor
enum Experiments {
    static let all: [Experiment] = [
        Experiment(FolderAccessProbe.descriptor, topic: "Folder access") { FolderAccessView() },
        Experiment(PreviewProbe.descriptor, topic: "Previews") { PreviewsView() },
        Experiment(XMPProbe.descriptor, topic: "XMP") { XMPView() },
        Experiment(EmbeddedMetadataProbe.descriptor, topic: "Embedded metadata") {
            EmbeddedMetadataView()
        },
        Experiment(GroupingProbe.descriptor, topic: "Grouping") { GroupingView() },
        Experiment(ScanProbe.descriptor, topic: "Scan") { ScanView() },
        Experiment(FoldStateProbe.descriptor, topic: "Fold state") { FoldStateView() },
    ]
}
