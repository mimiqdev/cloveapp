import CloveCore
import SwiftUI

struct BatchRenameOrderScreen: View {
    let flow: BatchRenameFlow
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var language
    @State private var showsName = false
    @State private var checkedPhoto: GridPhoto?
    @State private var containerWidth: CGFloat = 0

    private var usesTwoLineCompactHeader: Bool {
        containerWidth > 0 && containerWidth < 500
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 4) {
                HStack(spacing: 8) {
                    Button {
                        dismiss()
                    } label: {
                        Text(AppLocalization.string("Cancel", language: language))
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .foregroundStyle(Color.clove.text.primary)
                            .padding(.horizontal, usesTwoLineCompactHeader ? 14 : 16)
                            .frame(height: 44)
                            .contentShape(Capsule())
                            .cloveGlass(in: Capsule())
                    }
                    .buttonStyle(.cloveGlassPress)
                    .layoutPriority(1)
                    .accessibilityIdentifier("clove.rename.cancel")
                    .reportHeaderControlFrame("clove.rename.cancel")

                    Spacer(minLength: 4)

                    VStack(spacing: 2) {
                        Text(
                            AppLocalization.format(
                                "Order %lld photos", language: language, Int64(flow.order.count))
                        )
                        .font(.subheadline.bold())
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .accessibilityAddTraits(.isHeader)
                        .reportHeaderControlFrame("clove.rename.order.title")
                        if !usesTwoLineCompactHeader {
                            Text(
                                AppLocalization.string(
                                    "Drag to reorder · tap to check", language: language)
                            )
                            .font(.caption)
                            .foregroundStyle(Color.clove.text.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                        }
                    }

                    Spacer(minLength: 4)

                    HStack(spacing: usesTwoLineCompactHeader ? 6 : 8) {
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
                        .reportHeaderControlFrame("clove.rename.sort")

                        Button {
                            showsName = true
                        } label: {
                            Text(AppLocalization.string("Next", language: language))
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                                .foregroundStyle(
                                    flow.order.isEmpty
                                        ? Color.clove.text.secondary : Color.clove.accent
                                )
                                .opacity(flow.order.isEmpty ? 0.45 : 1)
                                .padding(.horizontal, usesTwoLineCompactHeader ? 14 : 16)
                                .frame(height: 44)
                                .contentShape(Capsule())
                                .cloveGlass(in: Capsule())
                        }
                        .buttonStyle(.cloveGlassPress)
                        .disabled(flow.order.isEmpty)
                        .accessibilityIdentifier("clove.rename.next")
                        .reportHeaderControlFrame("clove.rename.next")
                    }
                    .layoutPriority(1)
                }
                .padding(.horizontal, 16)
                .frame(minHeight: usesTwoLineCompactHeader ? 56 : 64)

                if usesTwoLineCompactHeader {
                    Text(
                        AppLocalization.string(
                            "Drag to reorder · tap to check", language: language)
                    )
                    .font(.caption)
                    .foregroundStyle(Color.clove.text.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                }
            }

            RenameOrderGrid(flow: flow, order: flow.order) { checkedPhoto = $0 }
            Text(Self.footerText(language: language))
                .font(.footnote)
                .foregroundStyle(Color.clove.text.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .accessibilityIdentifier("clove.rename.order.footer")
                .reportHeaderControlFrame("clove.rename.order.footer")
        }
        .onGeometryChange(for: CGFloat.self) {
            $0.size.width
        } action: { width in
            containerWidth = width
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

    static func footerText(language: ResolvedAppLanguage = .english) -> String {
        AppLocalization.string("Cancel discards changes to the order.", language: language)
    }
}
