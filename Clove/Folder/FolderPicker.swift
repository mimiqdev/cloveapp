import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// The system folder picker entry uses (PRD P0-01).
///
/// PRD P0-01 opens any folder Files can access, so the picker works in folder mode with
/// `asCopy: false`: Clove reads the folder where it is and never copies photos into an app
/// library. The picked URL is handed to C11's `pick`, which starts and stops the security scope
/// itself (G1 folder access), so the picker holds nothing after it reports the URL.
///
/// Entry and recovery actions present this system picker as a sheet.
struct FolderPicker: UIViewControllerRepresentable {
    /// Called with the folder the user chose.
    var onPick: (URL) -> Void

    /// Called when the picker closes without a choice, so entry stays as it was.
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

    /// Forwards the picker's one choice to the screen that presented it.
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
