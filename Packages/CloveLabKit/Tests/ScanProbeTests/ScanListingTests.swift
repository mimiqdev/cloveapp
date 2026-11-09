import Foundation
import Testing

@testable import ScanProbe

@Suite(.serialized)
struct ScanListingTests {
    @Test func everyMethodFindsTheSamePhotoFiles() async throws {
        let container = try ScanTestTree.container()
        defer { try? FileManager.default.removeItem(at: container) }
        let summary = try await ScanTestTree.generated(in: container)
        let folder = summary.root
        let expected = try ScanTestTree.expectedPhotoFiles(in: folder)
        #expect(expected.count == summary.photoFiles)
        for method in ScanMethod.allCases {
            let listing = try ScanLister.list(folder: folder, method: method, keySet: .all)
            #expect(
                listing.entries.map(\.relativePath).sorted() == expected,
                "\(method.displayName) found a different file set")
            #expect(listing.entries.allSatisfy { $0.isRegularFile == true })
            #expect(listing.entries.allSatisfy { $0.byteCount != nil })
            #expect(listing.entries.allSatisfy { $0.modificationDate != nil })
            #expect(listing.entries.allSatisfy { $0.contentTypeIdentifier != nil })
            #expect(listing.entries.allSatisfy { !$0.relativePath.contains("_Rejected") })
            #expect(listing.directories >= summary.folders)
        }
    }

    @Test func listingSkipsRejectsHiddenAndUnsupportedEntries() async throws {
        let container = try ScanTestTree.container()
        defer { try? FileManager.default.removeItem(at: container) }
        let summary = try await ScanTestTree.generated(in: container)
        for method in ScanMethod.allCases {
            let listing = try ScanLister.list(folder: summary.root, method: method, keySet: .names)
            #expect(listing.rejectedSkipped > 0)
            #expect(listing.unsupportedSkipped > 0)
            #expect(listing.entries.count == summary.photoFiles)
            #expect(!listing.entries.contains { $0.relativePath.contains("_Rejected") })
            // The FileManager options skip hidden entries before the walk sees
            // them, so only the POSIX walk can count them.
            if method == .posixReaddir {
                #expect(listing.hiddenSkipped > 0)
            }
            #expect(
                !listing.entries.contains { ScanRule.isHidden($0.relativePath.lastPathComponent) })
        }
    }

    @Test func keysRequestedAreTheOnlyKeysFilled() async throws {
        let container = try ScanTestTree.container()
        defer { try? FileManager.default.removeItem(at: container) }
        let summary = try await ScanTestTree.generated(in: container, fileTarget: 40)
        let names = try ScanLister.list(folder: summary.root, method: .posixReaddir, keySet: .names)
        #expect(names.entries.allSatisfy { $0.resourceName == nil })
        #expect(names.entries.allSatisfy { $0.isRegularFile == nil })
        #expect(names.entries.allSatisfy { $0.byteCount == nil })
        #expect(names.entries.allSatisfy { $0.modificationDate == nil })
        #expect(names.entries.allSatisfy { $0.contentTypeIdentifier == nil })
        #expect(names.entries.allSatisfy { $0.baseName.hasPrefix("IMG_") })

        let sized = try ScanLister.list(
            folder: summary.root, method: .contentsOfDirectory, keySet: .nameTypeSize)
        #expect(sized.entries.allSatisfy { $0.resourceName != nil })
        #expect(sized.entries.allSatisfy { $0.isRegularFile == true })
        #expect(sized.entries.allSatisfy { ($0.byteCount ?? 0) > 0 })
        #expect(sized.entries.allSatisfy { $0.modificationDate == nil })
    }

    @Test func rejectsFolderCanBeWalkedAndFilteredAfterwards() async throws {
        let container = try ScanTestTree.container()
        defer { try? FileManager.default.removeItem(at: container) }
        let summary = try await ScanTestTree.generated(in: container)
        var options = ScanOptions()
        options.includeRejected = true
        for method in ScanMethod.allCases {
            let listing = try ScanLister.list(
                folder: summary.root, method: method, keySet: .names, options: options)
            #expect(listing.entries.count == summary.photoFiles + summary.rejectedFiles)
            #expect(listing.entries.contains { $0.relativePath.contains("_Rejected") })
            let kept = ScanPairing.removingRejected(listing.entries)
            #expect(kept.count == summary.photoFiles)
        }
    }

    @Test func customRejectsFolderNameIsHonoured() async throws {
        let container = try ScanTestTree.container()
        defer { try? FileManager.default.removeItem(at: container) }
        let tree = try await ScanTree.makeTree(
            in: container,
            plan: ScanTreePlan(
                fileTarget: 20, folders: ["100CANON"], rejectsFolderName: "_Trash",
                rejectsFileCount: 5))
        var options = ScanOptions()
        options.rejectsFolderName = "_Trash"
        for method in ScanMethod.allCases {
            let listing = try ScanLister.list(
                folder: tree.root, method: method, keySet: .names, options: options)
            #expect(listing.entries.count == tree.photoFiles)
            #expect(!listing.entries.contains { $0.relativePath.contains("_Trash") })
        }
    }

    @Test func hiddenEntriesCanBeIncludedWhenAsked() async throws {
        let container = try ScanTestTree.container()
        defer { try? FileManager.default.removeItem(at: container) }
        let tree = try await ScanTestTree.generated(in: container)
        var options = ScanOptions()
        options.includeHidden = true
        for method in ScanMethod.allCases {
            let listing = try ScanLister.list(
                folder: tree.root, method: method, keySet: .names, options: options)
            // The hidden `.Trashes` folder holds one JPEG, and each folder has two
            // AppleDouble `._…CR3` files that look like photos until the hidden
            // filter runs. FileManager never yields AppleDouble files, even without
            // `.skipsHiddenFiles`; only the POSIX walk sees them.
            #expect(listing.hiddenSkipped == 0)
            #expect(listing.entries.contains { $0.relativePath.hasSuffix(".Trashes/IMG_0105.JPG") })
            if method == .posixReaddir {
                #expect(listing.entries.count == tree.photoFiles + 1 + 2 * tree.folders)
                #expect(listing.entries.contains { $0.relativePath.hasSuffix("._IMG_1001.CR3") })
            } else {
                #expect(listing.entries.count == tree.photoFiles + 1)
                #expect(!listing.entries.contains { $0.relativePath.contains("/._") })
            }
        }
    }

    @Test func batchesCoverEveryEntryOnce() async throws {
        let container = try ScanTestTree.container()
        defer { try? FileManager.default.removeItem(at: container) }
        let tree = try await ScanTestTree.generated(in: container, fileTarget: 150)
        let expected = try ScanTestTree.expectedPhotoFiles(in: tree.root)
        for method in ScanMethod.allCases {
            final class Collected: @unchecked Sendable {
                var entries: [ScanEntry] = []
                var numbers: [Int] = []
            }
            let collected = Collected()
            var options = ScanOptions()
            options.batchSize = 32
            let listing = try ScanLister.list(
                folder: tree.root, method: method, keySet: .names, options: options
            ) { batch in
                collected.entries += batch.entries
                collected.numbers.append(batch.number)
            }
            #expect(collected.entries.map(\.relativePath).sorted() == expected)
            #expect(collected.numbers == Array(1...listing.batches))
            #expect(listing.batches == (expected.count + 31) / 32)
            #expect(listing.firstBatchMilliseconds != nil)
            #expect(listing.entries.count == expected.count)
        }
    }

    @Test func scanCanBeCancelledBeforeItStarts() async throws {
        let container = try ScanTestTree.container()
        defer { try? FileManager.default.removeItem(at: container) }
        let tree = try await ScanTestTree.generated(in: container, fileTarget: 40)
        for method in ScanMethod.allCases {
            let task = Task {
                withUnsafeCurrentTask { $0?.cancel() }
                return try ScanLister.list(folder: tree.root, method: method)
            }
            do {
                _ = try await task.value
                Issue.record("\(method.displayName) ignored cancellation")
            } catch is CancellationError {
            } catch {
                Issue.record(error)
            }
        }
    }
}
