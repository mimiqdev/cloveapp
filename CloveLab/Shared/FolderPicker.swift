import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Presents the system document picker in folder mode and reports the picked
/// folder as a security-scoped URL. Read that URL through
/// ``SecurityScopedAccess/withAccess(to:_:)``.
struct FolderPicker: UIViewControllerRepresentable {
    /// Called with the picked folder; access is not held for the caller.
    var onPick: (URL) -> Void
    /// Called when the picker is dismissed without a selection.
    var onCancel: () -> Void = {}

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: [.folder], asCopy: false)
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick, onCancel: onCancel)
    }

    @MainActor
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private let onPick: (URL) -> Void
        private let onCancel: () -> Void

        init(onPick: @escaping (URL) -> Void, onCancel: @escaping () -> Void) {
            self.onPick = onPick
            self.onCancel = onCancel
        }

        func documentPicker(
            _ controller: UIDocumentPickerViewController,
            didPickDocumentsAt urls: [URL]
        ) {
            guard let url = urls.first else {
                onCancel()
                return
            }
            onPick(url)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onCancel()
        }
    }
}

/// A button that opens ``FolderPicker`` and reports the chosen folder.
struct FolderPickerButton: View {
    /// Button label.
    var title: String = "Choose folder"
    /// Called with the picked, security-scoped folder.
    var onPick: (URL) -> Void

    @State private var isPresenting = false

    var body: some View {
        Button {
            isPresenting = true
        } label: {
            Label(title, systemImage: "folder.badge.plus")
        }
        .sheet(isPresented: $isPresenting) {
            FolderPicker(
                onPick: { url in
                    isPresenting = false
                    onPick(url)
                },
                onCancel: { isPresenting = false }
            )
            .ignoresSafeArea()
        }
    }
}

#Preview {
    FolderPickerButton { _ in }
}
