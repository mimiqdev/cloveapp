import CloveCore
import SwiftUI

struct BatchRenameOrderScreen: View {
    let flow: BatchRenameFlow
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var language
    @State private var showsName = false
    @State private var checkedPhoto: GridPhoto?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(AppLocalization.string("Cancel", language: language)) { dismiss() }
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16).frame(height: 44)
                    .cloveGlass(in: Capsule())
                    .accessibilityIdentifier("clove.rename.cancel")
                Spacer(minLength: 4)
                VStack(spacing: 2) {
                    Text(
                        AppLocalization.format(
                            "Order %lld photos", language: language, Int64(flow.order.count))
                    )
                    .font(.subheadline.bold())
                    Text(
                        AppLocalization.string(
                            "Drag to reorder · tap to check", language: language)
                    )
                    .font(.caption).foregroundStyle(Color.clove.text.secondary)
                }
                Spacer(minLength: 4)
                HStack(spacing: 8) {
                    Menu {
                        Button(AppLocalization.string("Capture time", language: language)) {
                            flow.sort(by: .captureTime)
                        }
                        .accessibilityIdentifier("clove.rename.sort.captureTime")
                        Button(AppLocalization.string("Filename", language: language)) {
                            flow.sort(by: .fileName)
                        }
                        .accessibilityIdentifier("clove.rename.sort.fileName")
                        Button(AppLocalization.string("Reverse order", language: language)) {
                            flow.sort(by: .reverse)
                        }
                        .accessibilityIdentifier("clove.rename.sort.reverse")
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.clove.text.primary)
                            .frame(width: 44, height: 44)
                            .cloveGlass(in: Circle())
                    }
                    .accessibilityLabel(AppLocalization.string("Sort by", language: language))
                    .accessibilityIdentifier("clove.rename.sort")
                    Button(AppLocalization.string("Next", language: language)) { showsName = true }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.clove.accent)
                        .padding(.horizontal, 16).frame(height: 44)
                        .cloveGlass(in: Capsule())
                        .disabled(flow.order.isEmpty)
                        .accessibilityIdentifier("clove.rename.next")
                }
            }
            .padding(.horizontal, 16).frame(minHeight: 64)
            RenameOrderGrid(flow: flow, order: flow.order) { checkedPhoto = $0 }
            Text(
                AppLocalization.string(
                    "The order lives only here. Cancel drops it.", language: language)
            )
            .font(.footnote).foregroundStyle(Color.clove.text.secondary)
            .padding(20)
        }
        .foregroundStyle(Color.clove.text.primary)
        .background(Color.clove.bg.canvas)
        .interactiveDismissDisabled(flow.isRunning)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("clove.rename.order")
        .onChange(of: flow.order.isEmpty) { _, isEmpty in
            if isEmpty { dismiss() }
        }
        .sheet(isPresented: $showsName) {
            BatchRenameNameSheet(flow: flow) { dismiss() }
                .presentationSizing(.form)
        }
        .fullScreenCover(item: $checkedPhoto) { photo in
            BatchRenameCheckViewer(flow: flow, initialPhoto: photo.id)
        }
    }
}
