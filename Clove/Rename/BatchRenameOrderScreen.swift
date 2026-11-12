import CloveCore
import SwiftUI

struct BatchRenameOrderScreen: View {
    let flow: BatchRenameFlow
    @Environment(\.dismiss) private var dismiss
    @State private var showsName = false
    @State private var checkedPhoto: GridPhoto?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Cancel") { dismiss() }
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16).frame(height: 44)
                    .cloveGlass(in: Capsule())
                    .accessibilityIdentifier("clove.rename.cancel")
                Spacer(minLength: 4)
                VStack(spacing: 2) {
                    Text("Order \(flow.order.count) photos").font(.subheadline.bold())
                    Text("Drag to reorder · tap to check")
                        .font(.caption).foregroundStyle(Color.clove.text.secondary)
                }
                Spacer(minLength: 4)
                Button("Next") { showsName = true }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.clove.accent)
                    .padding(.horizontal, 16).frame(height: 44)
                    .cloveGlass(in: Capsule())
                    .disabled(flow.order.isEmpty)
                    .accessibilityIdentifier("clove.rename.next")
            }
            .padding(.horizontal, 16).frame(minHeight: 64)
            RenameOrderGrid(flow: flow) { checkedPhoto = $0 }
            Text("The order lives only here. Cancel drops it.")
                .font(.footnote).foregroundStyle(Color.clove.text.secondary)
                .padding(20)
        }
        .foregroundStyle(Color.clove.text.primary)
        .tint(Color.clove.accent)
        .background(Color.clove.bg.canvas)
        .interactiveDismissDisabled(flow.isRunning)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("clove.rename.order")
        .sheet(isPresented: $showsName) {
            BatchRenameNameSheet(flow: flow) { dismiss() }
                .presentationSizing(.form)
        }
        .fullScreenCover(item: $checkedPhoto) { photo in
            BatchRenameCheckViewer(flow: flow, initialPhoto: photo.id)
        }
    }
}
