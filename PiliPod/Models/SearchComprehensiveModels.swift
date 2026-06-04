import Foundation

struct SearchComprehensiveResponse: Decodable {
    let code: Int
    let message: String?
    let ttl: Int?
    let data: SearchComprehensiveData?
}

struct SearchComprehensiveData: Decodable {
    let result: [SearchComprehensiveModule]
}

struct SearchComprehensiveModule: Decodable, Identifiable {
    let resultType: String
    let users: [SearchComprehensiveUser]
    let videos: [SearchComprehensiveVideo]

    var id: String { resultType }

    var title: String {
        switch resultType {
        case "bili_user":
            return "用户"
        case "video":
            return "视频"
        default:
            return resultType
        }
    }

    var hasSupportedContent: Bool {
        !users.isEmpty || !videos.isEmpty
    }

    enum CodingKeys: String, CodingKey {
        case resultType = "result_type"
        case data
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        resultType = try container.decode(String.self, forKey: .resultType)

        switch resultType {
        case "bili_user":
            users = try container.decodeIfPresent([SearchComprehensiveUser].self, forKey: .data) ?? []
            videos = []
        case "video":
            videos = try container.decodeIfPresent([SearchComprehensiveVideo].self, forKey: .data) ?? []
            users = []
        default:
            users = []
            videos = []
        }
    }
}

struct SearchComprehensiveUser: Decodable, Identifiable {
    let mid: Int64
    let uname: String
    let fans: Int
    let videos: Int
    let upic: String
    let res: [SearchComprehensiveUserVideo]

    var id: Int64 { mid }

    var cardUser: SearchUserLargeCardUser {
        SearchUserLargeCardUser(
            id: String(mid),
            name: SearchResultFormatter.plainText(uname),
            avatarURL: SearchResultFormatter.normalizedURLString(upic),
            followerCount: fans,
            videoCount: videos
        )
    }

    var previewVideos: [SearchUserLargeCardVideo] {
        Array(res.prefix(3)).map { item in
            SearchUserLargeCardVideo(
                id: item.bvid,
                coverURL: SearchResultFormatter.normalizedURLString(item.pic),
                title: SearchResultFormatter.plainText(item.title),
                publishTimeText: VideoItem.formatTimestamp(item.pubdate)
            )
        }
    }
}

struct SearchComprehensiveUserVideo: Decodable, Identifiable {
    let bvid: String
    let title: String
    let pubdate: Int?
    let pic: String

    var id: String { bvid }

    func toVideoItem(uploader: String) -> VideoItem {
        VideoItem(
            bvid: bvid,
            cid: nil,
            cover: SearchResultFormatter.normalizedURLString(pic),
            title: SearchResultFormatter.plainText(title),
            playCount: "--",
            danmakuCount: "--",
            uploader: SearchResultFormatter.plainText(uploader),
            duration: 0,
            progressSeconds: nil,
            publishTimeText: VideoItem.formatTimestamp(pubdate),
            bottomRcmdReasonText: nil
        )
    }
}

struct SearchComprehensiveVideo: Decodable, Identifiable {
    let bvid: String
    let title: String
    let author: String
    let pic: String
    let pubdate: Int?
    let duration: String
    let play: FlexibleInt
    let videoReview: FlexibleInt?

    var id: String { bvid }

    enum CodingKeys: String, CodingKey {
        case bvid
        case title
        case author
        case pic
        case pubdate
        case duration
        case play
        case videoReview = "video_review"
    }

    func toVideoItem() -> VideoItem {
        VideoItem(
            bvid: bvid,
            cid: nil,
            cover: SearchResultFormatter.normalizedURLString(pic),
            title: SearchResultFormatter.plainText(title),
            playCount: VideoItem.formatCount(play.value ?? 0),
            danmakuCount: VideoItem.formatCount(videoReview?.value ?? 0),
            uploader: SearchResultFormatter.plainText(author),
            duration: SearchResultFormatter.durationSeconds(from: duration),
            progressSeconds: nil,
            publishTimeText: VideoItem.formatTimestamp(pubdate),
            bottomRcmdReasonText: nil
        )
    }
}

enum SearchResultFormatter {
    static func normalizedURLString(_ raw: String) -> String {
        if raw.hasPrefix("//") {
            return "https:\(raw)"
        }
        if raw.hasPrefix("http://") {
            return "https://" + raw.dropFirst("http://".count)
        }
        return raw
    }

    static func plainText(_ raw: String) -> String {
        let stripped = raw.replacingOccurrences(
            of: "<[^>]+>",
            with: "",
            options: .regularExpression
        )

        return stripped
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
    }

    static func durationSeconds(from duration: String) -> Int {
        let parts = duration.split(separator: ":").compactMap { Int($0) }
        switch parts.count {
        case 3:
            return parts[0] * 3600 + parts[1] * 60 + parts[2]
        case 2:
            return parts[0] * 60 + parts[1]
        case 1:
            return parts[0]
        default:
            return 0
        }
    }
}
