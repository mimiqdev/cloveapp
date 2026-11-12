import Foundation

/// Sidebar counts over the folder's photos and their shown marks. No filter is applied here.
public struct SidebarCounts: Equatable, Sendable {
    public let all: Int
    public let unmarked: Int
    public let rejected: Int
    /// Cumulative counts for each star minimum, including zero counts.
    public let ratings: [Rating: Int]
    public let labels: [LabelColour: Int]
    /// Exact containing paths. The empty path represents the opened folder itself.
    public let folders: [String: Int]

    /// The photo-bearing subfolders in Finder order. Empty parents are never invented.
    public var subfolders: [String] {
        folders.keys.filter { !$0.isEmpty }.sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
    }

    public init(photos: [GridPhoto]) {
        all = photos.count
        var unmarked = 0
        var rejected = 0
        var ratings: [Rating: Int] = [:]
        var labels: [LabelColour: Int] = [:]
        var folders: [String: Int] = [:]
        let levels = (1...5).compactMap { Rating(rawValue: $0) }
        for level in levels { ratings[level] = 0 }
        for photo in photos {
            if photo.marks.isUnmarked { unmarked += 1 }
            if photo.marks.isRejected { rejected += 1 }
            for level in levels where PhotoFilter.ratedAtLeast(level).matches(photo.marks) {
                ratings[level, default: 0] += 1
            }
            if let colour = photo.marks.label.colour { labels[colour, default: 0] += 1 }
            folders[photo.id.relativeFolderPath, default: 0] += 1
        }
        self.unmarked = unmarked
        self.rejected = rejected
        self.ratings = ratings
        self.labels = labels
        self.folders = folders
    }
}
