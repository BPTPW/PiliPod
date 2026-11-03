import SwiftUI

/// 收藏夹列表页面
struct FavoriteFolderListView: View {
    @StateObject private var viewModel = FavoriteFolderListViewModel()
    @State private var selectedFolder: FavoriteFolderItem?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if viewModel.isLoading && viewModel.folders.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 240)
                } else if let error = viewModel.errorMessage, viewModel.folders.isEmpty {
                    Text(error)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 240)
                } else if viewModel.folders.isEmpty {
                    Text("还没有收藏夹")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 240)
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(viewModel.folders) { folder in
                            Button {
                                selectedFolder = folder
                            } label: {
                                FavoriteFolderRowView(folder: folder)
                            }
                            .buttonStyle(.plain)
                            .task { await viewModel.loadMoreIfNeeded(current: folder) }
                        }

                        if viewModel.isLoading {
                            ProgressView()
                                .padding(.vertical, 8)
                        }
                    }
                }
            }
            .padding(16)
        }
        .refreshable {
            await viewModel.refresh()
        }
        .background(Color(.systemBackground))
        .navigationTitle("我的收藏")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .navigationDestination(item: $selectedFolder) { folder in
            FavoriteVideoListView(folder: folder)
        }
        .task {
            if viewModel.folders.isEmpty {
                await viewModel.refresh()
            }
        }
    }
}

private struct FavoriteFolderRowView: View {
    let folder: FavoriteFolderItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            FavoriteFolderCover(urlString: folder.cover)
                .frame(height: 80)
                .aspectRatio(16 / 9, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(folder.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Text(L10n.format("共%lld个内容", folder.mediaCount))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)

                Text(L10n.string(folder.isPrivate ? "permission.private" : "permission.public"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
        }
        .padding(10)
        .glassEffect(.regular.interactive(),in: RoundedRectangle(cornerRadius: 15))
    }
}

#Preview {
    NavigationStack {
        FavoriteFolderListView()
    }
}
