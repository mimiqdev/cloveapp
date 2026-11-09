import SwiftUI

/// Footer that names the last exported report and offers it through the share
/// sheet. Probes write reports with ``LabSession/export(_:toTestedFolder:)``.
struct DeviceReportFooter: View {
    @Environment(LabSession.self) private var session

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Device report")
                .font(.footnote.weight(.semibold))
            Text(session.lastReportURL?.lastPathComponent ?? "No report yet")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            if let exportError = session.exportError {
                Text(exportError)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
            if let url = session.lastReportURL {
                ShareLink(item: url) {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("clovelab.footer.export")
            } else {
                Button("Export", systemImage: "square.and.arrow.up") {}
                    .buttonStyle(.bordered)
                    .disabled(true)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("clovelab.footer")
        .task {
            session.prepareDeviceReportIfNeeded()
        }
    }
}

#Preview {
    List {
        Section {
        } footer: {
            DeviceReportFooter()
        }
    }
    .environment(LabSession())
}
