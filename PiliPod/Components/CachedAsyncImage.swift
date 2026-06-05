import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct CachedAsyncImage<Content: View>: View {
    let url: URL?
    private let content: (AsyncImagePhase) -> Content

    @State private var phase: AsyncImagePhase = .empty

    init(
        url: URL?,
        @ViewBuilder content: @escaping (AsyncImagePhase) -> Content
    ) {
        self.url = url
        self.content = content
    }

    var body: some View {
        content(phase)
            .task(id: url) {
                await load()
            }
    }

    @MainActor
    private func load() async {
        guard let url else {
            phase = .empty
            return
        }

        if case .success = phase {
            return
        }

        phase = .empty

#if canImport(UIKit)
        if let image = await SharedRemoteImageStore.shared.image(for: url) {
            phase = .success(Image(uiImage: image))
        } else {
            phase = .failure(CachedAsyncImageError.loadFailed)
        }
#else
        phase = .failure(CachedAsyncImageError.loadFailed)
#endif
    }
}

enum CachedAsyncImageError: Error {
    case loadFailed
}

#if canImport(UIKit)
@MainActor
final class SharedRemoteImageStore {
    static let shared = SharedRemoteImageStore()

    private let memoryCache = NSCache<NSURL, UIImage>()
    private var tasks: [NSURL: Task<UIImage?, Never>] = [:]

    private init() {
        memoryCache.countLimit = 512
    }

    func image(for url: URL) async -> UIImage? {
        let key = url as NSURL
        if let cachedImage = memoryCache.object(forKey: key) {
            return cachedImage
        }

        let request = URLRequest(
            url: url,
            cachePolicy: .returnCacheDataElseLoad,
            timeoutInterval: 60
        )

        if let cachedResponse = URLCache.shared.cachedResponse(for: request),
           let image = UIImage(data: cachedResponse.data)
        {
            memoryCache.setObject(image, forKey: key)
            return image
        }

        if let existingTask = tasks[key] {
            return await existingTask.value
        }

        let task = Task<UIImage?, Never> {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse,
                      (200 ... 299).contains(httpResponse.statusCode),
                      let image = UIImage(data: data)
                else {
                    return nil
                }
                return image
            } catch {
                return nil
            }
        }

        tasks[key] = task
        let image = await task.value
        tasks[key] = nil

        if let image {
            memoryCache.setObject(image, forKey: key)
        }

        return image
    }
}
#endif
