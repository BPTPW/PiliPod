import Combine
import Foundation

@MainActor
final class WatchLaterViewModel: ObservableObject {
    @Published var videos: [VideoItem] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    func refresh() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let data = try await BiliAPI.shared.fetchWatchLaterList()
            videos = (data.list ?? []).map { VideoItem(from: $0) }
        } catch {
            videos = []
            errorMessage = error.localizedDescription
        }
    }
}
