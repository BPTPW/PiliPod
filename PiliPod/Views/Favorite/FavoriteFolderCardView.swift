import SwiftUI

/// 我的页面中的“我的收藏”卡片
struct FavoriteFolderCardView: View {
    @StateObject private var viewModel = FavoriteFolderListViewModel()
    @ObservedObject private var loginSession = LoginSession.shared
    let onOpenList: () -> Void
    let onSelectFolder: (FavoriteFolderItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: onOpenList) {
                HStack(spacing: 8) {
                    Text("我的收藏")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text("\(viewModel.totalCount)")
                        .font(.caption)
                        .foregroundStyle(Color("BiliPink"))

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if !viewModel.folders.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(viewModel.folders) { folder in
                            Button {
                                onSelectFolder(folder)
                            } label: {
                                FavoriteFolderCardItem(folder: folder)
                            }
                            .buttonStyle(.plain)
                            .task { await viewModel.loadMoreIfNeeded(current: folder) }
                        }
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onTapGesture(perform: onOpenList)
        .task(id: loginSession.isLogin) {
            await viewModel.refresh()
        }
    }
}

private struct FavoriteFolderCardItem: View {
    let folder: FavoriteFolderItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            FavoriteFolderCover(urlString: folder.cover)
                .frame(height: 80)
                .aspectRatio(16 / 9, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            Text(folder.title)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(1)

            Text(favoriteFolderSubtitle(folder))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: 80 / 9 * 16, alignment: .leading)
    }
}

func favoriteFolderSubtitle(_ folder: FavoriteFolderItem) -> String {
    let visibility = L10n.string(folder.isPrivate ? "permission.private" : "permission.public")
    return L10n.format("共%lld个内容", folder.mediaCount) + " · " + visibility
}

struct FavoriteFolderCover: View {
    let urlString: String?

    var body: some View {
        CachedAsyncImage(url: urlString.flatMap { URL(string: $0.replacingOccurrences(of: "http://", with: "https://")) }) { phase in
            if case .success(let image) = phase {
                image
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle().fill(Color(.secondarySystemFill))
            }
        }
        .clipped()
    }
}
