import CloveCore
import SwiftUI

/// Resume-first Entry and first launch (handoff screens.md §01; PRD P0-02).
/// Reading Recents and app-private previews never opens or enumerates a remembered folder.
struct EntryScreen: View {
    let browsing: BrowsingModel
    @State private var isPickingFolder = false

    var body: some View {
        Group {
            if let hero = browsing.recents.first {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        heroCard(hero)
                        if browsing.recents.count > 1 {
                            Text("Earlier")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Color.clove.text.secondary)
                            VStack(spacing: 0) {
                                ForEach(Array(browsing.recents.dropFirst())) { recent in
                                    recentRow(recent)
                                    if recent.id != browsing.recents.last?.id {
                                        Rectangle().fill(Color.clove.separator).frame(height: 0.5)
                                    }
                                }
                            }
                        }
                        failureText
                    }
                    .frame(maxWidth: 560)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .frame(maxWidth: .infinity)
                }
                .safeAreaInset(edge: .bottom) {
                    Button {
                        isPickingFolder = true
                    } label: {
                        Label("Open folder", systemImage: "folder")
                            .font(.headline)
                            .foregroundStyle(Color.clove.accent)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 15)
                            .cloveGlass(in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("clove.entry.pickFolder")
                    .padding(.vertical, 12)
                }
            } else {
                VStack(spacing: 0) {
                    EntryEmptyState { isPickingFolder = true }
                    failureText.padding(.horizontal)
                }
                .accessibilityIdentifier("clove.entry.noRecents")
            }
        }
        .background(Color.clove.bg.canvas)
        .foregroundStyle(Color.clove.text.primary)
        .navigationTitle("Clove")
        .navigationBarTitleDisplayMode(.large)
        .folderPicker(isPresented: $isPickingFolder) { url in
            await browsing.openPickedFolder(url)
        }
        .task { await browsing.reloadRecents() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("clove.entry")
    }

    private func needsReconnect(_ recent: RecentFolder) -> Bool {
        recent.needsReconnect == true || browsing.recentFailure(for: recent.id) != nil
    }

    private func heroCard(_ recent: RecentFolder) -> some View {
        Button {
            if needsReconnect(recent) {
                isPickingFolder = true
            } else {
                Task { await browsing.resume(recent) }
            }
        } label: {
            ZStack(alignment: .bottomLeading) {
                EntryPhoto(
                    photo: recent.progress?.lastViewedPhoto ?? recent.progress?.previewPhotos.first,
                    browsing: browsing)
                LinearGradient(
                    colors: [
                        CloveTheme.dark.tokens.stage.color.opacity(0),
                        CloveTheme.dark.tokens.stage.color,
                    ],
                    startPoint: .center, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 6) {
                    Text(RecentFolderSummary.name(for: recent))
                        .font(.title.bold())
                        .lineLimit(2)
                    HStack(alignment: .bottom, spacing: 12) {
                        Text(RecentFolderSummary.location(for: recent))
                            .font(.subheadline)
                            .lineLimit(2)
                        Spacer(minLength: 0)
                        if needsReconnect(recent) {
                            Text("Reconnect").font(.subheadline.weight(.semibold))
                        } else if let progress = recent.progress {
                            Text("\(progress.left.formatted()) left")
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                    if let progress = recent.progress {
                        progressLine(progress).padding(.top, 10)
                    }
                }
                .foregroundStyle(CloveTheme.dark.tokens.primaryText.color)
                .padding(20)
            }
            .frame(height: 380)
            .overlay(alignment: .topLeading) {
                Text("Continue · \(RecentFolderSummary.relativeDate(recent.lastOpened))")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(CloveTheme.dark.tokens.primaryText.color)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(CloveTheme.dark.tokens.stage.color.opacity(0.45), in: Capsule())
                    .padding(16)
            }
            .clipShape(RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("clove.entry.openFolder")
        .accessibilityLabel("Continue · \(RecentFolderSummary.name(for: recent))")
    }

    private func progressLine(_ progress: FolderProgress) -> some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                Rectangle().fill(Color.clove.accent)
                    .frame(
                        width: geometry.size.width * Double(progress.marked)
                            / Double(max(1, progress.total)))
                Rectangle().fill(Color.clove.reject)
                    .frame(
                        width: geometry.size.width * Double(progress.rejected)
                            / Double(max(1, progress.total)))
                Rectangle().fill(Color.clove.rating.off)
            }
        }
        .frame(height: 3)
        .clipShape(Capsule())
        .accessibilityLabel(
            "\(progress.marked) marked, \(progress.rejected) rejected, \(progress.left) left")
    }

    private func recentRow(_ recent: RecentFolder) -> some View {
        let reconnect = needsReconnect(recent)
        return Button {
            if reconnect {
                isPickingFolder = true
            } else {
                Task { await browsing.reopen(recent) }
            }
        } label: {
            HStack(spacing: 12) {
                HStack(spacing: 1) {
                    ForEach(0..<3) { index in
                        let photos = recent.progress?.previewPhotos ?? []
                        EntryPhoto(
                            photo: index < photos.count ? photos[index] : nil, browsing: browsing)
                    }
                }
                .frame(width: 104, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                VStack(alignment: .leading, spacing: 3) {
                    Text(RecentFolderSummary.name(for: recent)).font(.subheadline.weight(.semibold))
                    Text(
                        reconnect
                            ? "Drive not connected" : RecentFolderSummary.location(for: recent)
                    )
                    .font(.caption).foregroundStyle(Color.clove.text.secondary)
                }
                .lineLimit(2)
                .opacity(reconnect ? 0.5 : 1)
                Spacer(minLength: 0)
                if reconnect {
                    Text("Reconnect")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.clove.accent)
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .cloveGlass(in: Capsule())
                        .accessibilityIdentifier("clove.entry.reconnect")
                } else {
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(RecentFolderSummary.count(for: recent)).font(.subheadline)
                        if recent.progress?.finished == true {
                            Text("Done").foregroundStyle(Color.clove.status.saved)
                                .accessibilityIdentifier("clove.entry.done")
                        } else {
                            Text(recent.lastOpened, format: .dateTime.month(.abbreviated).day())
                                .foregroundStyle(Color.clove.text.secondary)
                        }
                    }
                    .font(.caption)
                }
            }
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("clove.entry.recent.\(recent.id.uuidString)")
    }

    @ViewBuilder private var failureText: some View {
        if let failure = browsing.folderFailure {
            Text(FolderFailureExplanation.text(for: failure))
                .font(.footnote).foregroundStyle(Color.clove.text.secondary)
                .accessibilityIdentifier("clove.entry.folderFailure")
        } else if browsing.recentsFailure != nil {
            Text("Clove could not read its list of recent folders.")
                .font(.footnote).foregroundStyle(Color.clove.text.secondary)
                .accessibilityIdentifier("clove.entry.recentsFailure")
        }
    }
}
