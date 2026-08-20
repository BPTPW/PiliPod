import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct CachedAsyncImage<Content: View>: View {
    let url: URL?
    private let content: (AsyncImagePhase) -> Content

    @State private var phase: AsyncImagePhase = .empty
    @State private var showsLoadedImage = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        url: URL?,
        @ViewBuilder content: @escaping (AsyncImagePhase) -> Content
    ) {
        self.url = url
        self.content = content
    }

    var body: some View {
        Group {
            if showsLoadedImage {
                content(phase)
                    .transition(.opacity)
            } else {
                content(phase)
            }
        }
        .task(id: url) {
            await load()
        }
    }

    @MainActor
    private func load() async {
        guard let url else {
            phase = .empty
            showsLoadedImage = false
            return
        }

        if case .success = phase {
            return
        }

        phase = .empty
        showsLoadedImage = false

#if canImport(UIKit)
        if let image = await SharedRemoteImageStore.shared.image(for: url) {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                phase = .success(Image(uiImage: image))
                showsLoadedImage = true
            }
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
        // iOS App Transport Security blocks plain HTTP image requests. Image
        // URLs come from several API/model paths, so normalize at this shared
        // boundary instead of relying on every caller to do it correctly.
        let normalizedURL = Self.httpsURL(for: url)
        let key = normalizedURL as NSURL
        if let cachedImage = memoryCache.object(forKey: key) {
            return cachedImage
        }

        let request = URLRequest(
            url: normalizedURL,
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

    private static func httpsURL(for url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.caseInsensitiveCompare("http") == .orderedSame
        else {
            return url
        }

        components.scheme = "https"
        return components.url ?? url
    }
}
#endif
