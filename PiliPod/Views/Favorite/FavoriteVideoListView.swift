import SwiftUI

/// 收藏夹内的视频列表（待实现）
struct FavoriteVideoListView: View {
    let folder: FavoriteFolderItem

    var body: some View {
        Color.clear
            .navigationTitle(folder.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .tabBar)
    }
}
