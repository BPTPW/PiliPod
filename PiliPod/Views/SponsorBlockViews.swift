import SwiftUI

enum SponsorBlockVoteSelection: Equatable {
    case none
    case upvoted
    case downvoted
}

struct SponsorBlockSubmitDrawer: View {
    @Binding var segments: [VideoDetailPage.SponsorBlockDraftSegment]

    let errorText: String?
    let isSubmitting: Bool
    let currentPlayerTime: TimeInterval
    let videoDuration: TimeInterval
    let onClose: () -> Void
    let onSubmit: () -> Void
    let onSetStartToCurrent: (VideoDetailPage.SponsorBlockDraftSegment.ID) -> Void
    let onSetEndToCurrent: (VideoDetailPage.SponsorBlockDraftSegment.ID) -> Void
    let onSetStartToBoundary: (VideoDetailPage.SponsorBlockDraftSegment.ID) -> Void
    let onSetEndToBoundary: (VideoDetailPage.SponsorBlockDraftSegment.ID) -> Void
    let onPreview: (VideoDetailPage.SponsorBlockDraftSegment.ID) -> Void
    let onDelete: (VideoDetailPage.SponsorBlockDraftSegment.ID) -> Void
    let onAddSegment: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .foregroundStyle(.primary)
                        .frame(width: 40, height: 40)
                }
                .tint(.primary)
                .glassEffect(
                    .regular.interactive(),
                    in: .circle
                )

                Spacer()

                Button(action: onSubmit) {
                    if isSubmitting {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.blue)
                            .frame(width: 40, height: 40)
                    } else {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                    }
                }
                .disabled(isSubmitting)
                .glassEffect(
                    .regular.interactive().tint(.blue),
                    in: .circle
                )
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            if let errorText, !errorText.isEmpty {
                Text(errorText)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }

            ScrollView {
                VStack(spacing: 12) {
                    ForEach($segments) { $segment in
                        SponsorBlockSubmitSegmentRow(
                            segment: $segment,
                            onSetStartToCurrent: { onSetStartToCurrent(segment.id) },
                            onSetEndToCurrent: { onSetEndToCurrent(segment.id) },
                            onSetStartToBoundary: { onSetStartToBoundary(segment.id) },
                            onSetEndToBoundary: { onSetEndToBoundary(segment.id) },
                            onPreview: { onPreview(segment.id) },
                            onDelete: { onDelete(segment.id) }
                        )
                    }

                    Button(action: onAddSegment) {
                        Label("新增片段", systemImage: "plus")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .glassEffect(
                        .regular.interactive(),
                        in: .capsule
                    )
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(.systemBackground))
    }
}

private struct SponsorBlockSubmitSegmentRow: View {
    @Binding var segment: VideoDetailPage.SponsorBlockDraftSegment

    let onSetStartToCurrent: () -> Void
    let onSetEndToCurrent: () -> Void
    let onSetStartToBoundary: () -> Void
    let onSetEndToBoundary: () -> Void
    let onPreview: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 10) {
                    timeRow(
                        title: "开始",
                        value: formatSegmentTimeWithMilliseconds(segment.start),
                        onLocate: onSetStartToCurrent,
                        onBoundary: onSetStartToBoundary,
                        boundaryIcon: "backward.end"
                    )

                    timeRow(
                        title: "结束",
                        value: formatSegmentTimeWithMilliseconds(segment.end),
                        onLocate: onSetEndToCurrent,
                        onBoundary: onSetEndToBoundary,
                        boundaryIcon: "forward.end"
                    )

                    HStack(spacing: 12) {
                        Menu {
                            ForEach(SponsorBlockCategory.allCases) { category in
                                Button(category.title) {
                                    segment.category = category
                                }
                            }
                        } label: {
                            labeledChip(title: "分类", value: segment.category.title)
                        }
                        .tint(.primary)

                        Menu {
                            ForEach(VideoDetailPage.SponsorBlockDraftActionType.allCases, id: \.self) { type in
                                Button(type.title) {
                                    segment.actionType = type
                                }
                            }
                        } label: {
                            labeledChip(title: "行为类别", value: segment.actionType.title)
                        }
                        .tint(.primary)
                    }
                }

                Spacer()

                HStack(spacing: 10) {
                    Button(action: onPreview) {
                        Image(systemName: "play.circle")
                    }
                    .buttonStyle(.plain)

                    Button(action: onDelete) {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.plain)
                }
                .font(.system(size: 18))
                .foregroundStyle(.primary)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private func timeRow(
        title: String,
        value: String,
        onLocate: @escaping () -> Void,
        onBoundary: @escaping () -> Void,
        boundaryIcon: String
    ) -> some View {
        HStack(spacing: 8) {
            Text("\(title): \(value)")
                .font(.system(size: 15, weight: .medium, design: .monospaced))

            Button(action: onLocate) {
                Image(systemName: "mappin.circle")
            }
            .buttonStyle(.plain)

            Button(action: onBoundary) {
                Image(systemName: boundaryIcon)
            }
            .buttonStyle(.plain)
        }
    }

    private func labeledChip(title: String, value: String) -> some View {
        HStack(spacing: 6) {
            Text("\(title):")
            Text(value)
                .fontWeight(.semibold)
        }
        .font(.system(size: 12, weight: .medium))
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(.tertiarySystemBackground))
        )
    }
}

struct SponsorBlockSegmentsSheet: View {
    let segments: [SkipSegment]
    let settings: SponsorBlockSettings
    let categoryOverrides: [String: SponsorBlockCategory]
    let voteSelections: [String: SponsorBlockVoteSelection]
    let onVote: (SkipSegment, SponsorBlockVoteSelection) -> Void
    let onChangeCategory: (SkipSegment, SponsorBlockCategory) -> Void
    let onSkipToSegmentEnd: (SkipSegment) -> Void

    var body: some View {
        List {
            if segments.isEmpty {
                ContentUnavailableView("暂无片段", systemImage: "list.bullet.rectangle")
            } else {
                ForEach(segments) { segment in
                    SponsorBlockSegmentRow(
                        segment: segment,
                        category: categoryOverrides[segment.segmentID] ?? SponsorBlockCategory(rawValue: segment.category),
                        behaviorTitle: behaviorTitle(for: segment),
                        voteSelection: voteSelections[segment.segmentID] ?? .none,
                        onVote: { vote in
                            onVote(segment, vote)
                        },
                        onChangeCategory: { category in
                            onChangeCategory(segment, category)
                        },
                        onSkip: {
                            onSkipToSegmentEnd(segment)
                        }
                    )
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .listRowBackground(Color.clear)
                }
            }
        }
        .navigationTitle("空降助手片段")
        .navigationBarTitleDisplayMode(.inline)
        .listStyle(.plain)
    }

    private func behaviorTitle(for segment: SkipSegment) -> String {
        guard let category = categoryOverrides[segment.segmentID] ?? SponsorBlockCategory(rawValue: segment.category) else {
            return "未知"
        }
        return settings.behavior(for: category).title
    }
}

private struct SponsorBlockSegmentRow: View {
    let segment: SkipSegment
    let category: SponsorBlockCategory?
    let behaviorTitle: String
    let voteSelection: SponsorBlockVoteSelection
    let onVote: (SponsorBlockVoteSelection) -> Void
    let onChangeCategory: (SponsorBlockCategory) -> Void
    let onSkip: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                if let category {
                    Text(category.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .glassEffect(
                            .regular.tint(category.color),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )
                } else {
                    Text(segment.category)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .glassEffect(
                            .regular.tint(.gray),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )
                }

                Text(segmentTimeText)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.primary.opacity(0.8))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(behaviorTitle)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary.opacity(0.85))

            Button {
                onVote(.upvoted)
            } label: {
                Image(systemName: voteSelection == .upvoted ? "hand.thumbsup.fill" : "hand.thumbsup")
                    .foregroundStyle(voteSelection == .upvoted ? Color("BiliPink") : .primary)
            }
            .buttonStyle(.plain)

            Button {
                onVote(.downvoted)
            } label: {
                Image(systemName: voteSelection == .downvoted ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                    .foregroundStyle(voteSelection == .downvoted ? Color("BiliPink") : .primary)
            }
            .buttonStyle(.plain)

            Menu {
                ForEach(SponsorBlockCategory.allCases) { category in
                    Button(category.title) {
                        onChangeCategory(category)
                    }
                }
            } label: {
                Image(systemName: "arrow.trianglehead.2.clockwise")
                    .foregroundStyle(.primary)
            }
            .tint(.primary)
            .buttonStyle(.plain)

            Button(action: onSkip) {
                Image(systemName: "forward.end")
                    .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var segmentTimeText: String {
        let start = segment.segment.first ?? 0
        let end = segment.segment.count >= 2 ? segment.segment[1] : start
        return "\(formatSegmentTime(start)) 至 \(formatSegmentTime(end))"
    }
}

func formatSegmentTimeWithMilliseconds(_ seconds: TimeInterval) -> String {
    let safe = max(0, seconds)
    let totalMilliseconds = Int((safe * 1000).rounded())
    let wholeSeconds = totalMilliseconds / 1000
    let milliseconds = totalMilliseconds % 1000
    let hours = wholeSeconds / 3600
    let minutes = (wholeSeconds % 3600) / 60
    let remainingSeconds = wholeSeconds % 60

    if hours > 0 {
        return String(format: "%02d:%02d:%02d.%03d", hours, minutes, remainingSeconds, milliseconds)
    }

    return String(format: "%02d:%02d.%03d", minutes, remainingSeconds, milliseconds)
}
