import SwiftUI

struct VideoPageSelectionDrawer: View {
    let pages: [VideoPageListItem]
    let currentCID: Int
    let onClose: () -> Void
    let onSelect: (VideoPageListItem) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("视频选集")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Spacer()

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .foregroundStyle(.primary)
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.plain)
                .glassEffect(
                    .regular.interactive(),
                    in: .circle
                )
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(pages) { page in
                        pageRow(page)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(.systemBackground))
    }

    private func pageRow(_ page: VideoPageListItem) -> some View {
        let isCurrent = page.cid == currentCID

        return Button {
            onSelect(page)
        } label: {
            HStack(spacing: 12) {
                ZStack(alignment: .bottomTrailing) {
                    CachedAsyncImage(url: normalizedPageCoverURL(for: page.firstFrame)) { phase in
                        if case .success(let image) = phase {
                            image
                                .resizable()
                                .scaledToFill()
                        } else {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color(.secondarySystemBackground))
                        }
                    }
                    .frame(width: 144, height: 82)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    Text(formatDuration(page.duration))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .glassEffect(
                            .regular.tint(.black.opacity(0.45)),
                            in: .capsule
                        )
                        .padding(8)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("P\(page.page)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isCurrent ? Color("BiliPink") : .secondary)

                    Text(page.part)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(isCurrent ? Color("BiliPink") : .primary)
                        .lineLimit(2)
                        .truncationMode(.tail)
                }

                Spacer(minLength: 8)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )
        }
        .buttonStyle(.plain)
    }

    private func formatDuration(_ duration: Int) -> String {
        let total = max(0, duration)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func normalizedPageCoverURL(for raw: String?) -> URL? {
        guard let raw, !raw.isEmpty else { return nil }
        if raw.hasPrefix("http://") {
            return URL(string: raw.replacingOccurrences(of: "http://", with: "https://"))
        }
        if raw.hasPrefix("//") {
            return URL(string: "https:" + raw)
        }
        return URL(string: raw)
    }
}
