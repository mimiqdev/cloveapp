import CloveCore
import SwiftUI
import UniformTypeIdentifiers

struct BatchRenameOrderScreen: View {
    let flow: BatchRenameFlow
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var showsName = false
    @State private var checkedPhoto: GridPhoto?
    @State private var dragging: PhotoIdentity?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Cancel") { dismiss() }
                    .accessibilityIdentifier("clove.rename.cancel")
                Spacer(minLength: 4)
                VStack(spacing: 2) {
                    Text("Order \(flow.order.count) photos").font(.subheadline.bold())
                    Text("Drag to reorder · tap to check")
                        .font(.caption).foregroundStyle(Color.clove.text.secondary)
                }
                Spacer(minLength: 4)
                Button("Next") { showsName = true }
                    .disabled(flow.order.isEmpty)
                    .accessibilityIdentifier("clove.rename.next")
            }
            .padding(.horizontal, 16).frame(minHeight: 64)
            ScrollView {
                LazyVGrid(
                    columns: Array(
                        repeating: GridItem(.flexible(), spacing: 2),
                        count: sizeClass == .regular ? 6 : 3), spacing: 2
                ) {
                    ForEach(Array(flow.order.enumerated()), id: \.element.id) { index, photo in
                        tile(photo, position: index)
                    }
                }
            }
            Text("The order lives only here. Cancel drops it.")
                .font(.footnote).foregroundStyle(Color.clove.text.secondary)
                .padding(20)
        }
        .foregroundStyle(Color.clove.text.primary)
        .tint(Color.clove.accent)
        .background(Color.clove.bg.canvas)
        .interactiveDismissDisabled(flow.isRunning)
        .accessibilityIdentifier("clove.rename.order")
        .sheet(isPresented: $showsName) {
            BatchRenameNameSheet(flow: flow) { dismiss() }
                .presentationSizing(.form)
        }
        .fullScreenCover(item: $checkedPhoto) { photo in
            BatchRenameCheckViewer(flow: flow, initialPhoto: photo.id)
        }
    }

    private func tile(_ photo: GridPhoto, position: Int) -> some View {
        Button {
            checkedPhoto = photo
        } label: {
            MoveRejectsThumbnail(photo: photo.id, source: flow.browsing.thumbnails)
                .aspectRatio(1, contentMode: .fit)
                .overlay(alignment: .topLeading) {
                    Text("\(position + 1)")
                        .font(.caption.bold()).foregroundStyle(.white)
                        .frame(minWidth: 26, minHeight: 26)
                        .background(Color.clove.accent, in: Circle())
                        .padding(6)
                }
                .opacity(dragging == photo.id ? 0.2 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(photo.fileName)
        .accessibilityValue("Position \(position + 1) of \(flow.order.count)")
        .accessibilityIdentifier("clove.rename.tile.\(photo.id.stem)")
        .accessibilityAction(named: "Move earlier") { flow.move(photo.id, to: position - 1) }
        .accessibilityAction(named: "Move later") { flow.move(photo.id, to: position + 1) }
        .accessibilityAction(named: "Move to start") { flow.move(photo.id, to: 0) }
        .accessibilityAction(named: "Move to end") {
            flow.move(photo.id, to: flow.order.count - 1)
        }
        .onDrag {
            dragging = photo.id
            return NSItemProvider(object: photo.id.stem as NSString)
        }
        .onDrop(
            of: [.text],
            delegate: RenameTileDrop(
                flow: flow, target: photo.id, dragging: $dragging))
    }
}

private struct RenameTileDrop: DropDelegate {
    let flow: BatchRenameFlow
    let target: PhotoIdentity
    @Binding var dragging: PhotoIdentity?

    func dropEntered(info: DropInfo) {
        guard let dragging, dragging != target,
            let index = flow.order.firstIndex(where: { $0.id == target })
        else { return }
        withAnimation(.easeInOut(duration: 0.15)) { flow.move(dragging, to: index) }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }
}
