import SwiftUI

/// Root of the Clove Lab debug app: the M1 spikes and the device report footer.
@MainActor
struct LabRootView: View {
    @State private var session = LabSession()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(Experiments.all) { experiment in
                        NavigationLink {
                            experiment.makeDestination()
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(experiment.id)
                                    .font(.headline)
                                Text(experiment.question)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } footer: {
                    DeviceReportFooter()
                }
            }
            .navigationTitle("Clove Lab")
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("clovelab.root")
        }
        .environment(session)
    }
}

#Preview {
    LabRootView()
}
