import Foundation
import CoreGraphics

/// Web 动态接口的宽松 JSON 容器。动态模块会随着服务端类型增加而变化，先保留原始结构，
/// 再转换为页面只需要的稳定展示能力，避免未知模块导致整页解码失败。
indirect enum SpaceDynamicJSONValue: Decodable {
    case object([String: SpaceDynamicJSONValue])
    case array([SpaceDynamicJSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        if let container = try? decoder.container(keyedBy: SpaceDynamicCodingKey.self) {
            var object: [String: SpaceDynamicJSONValue] = [:]
            for key in container.allKeys {
                object[key.stringValue] = try container.decode(SpaceDynamicJSONValue.self, forKey: key)
            }
            self = .object(object)
        } else if var container = try? decoder.unkeyedContainer() {
            var values: [SpaceDynamicJSONValue] = []
            while !container.isAtEnd {
                values.append(try container.decode(SpaceDynamicJSONValue.self))
            }
            self = .array(values)
        } else if let container = try? decoder.singleValueContainer() {
            if container.decodeNil() { self = .null }
            else if let value = try? container.decode(Bool.self) { self = .bool(value) }
            else if let value = try? container.decode(Double.self) { self = .number(value) }
            else { self = .string(try container.decode(String.self)) }
        } else {
            self = .null
        }
    }
}

private struct SpaceDynamicCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?
    init?(stringValue: String) { self.stringValue = stringValue; intValue = nil }
    init?(intValue: Int) { stringValue = String(intValue); self.intValue = intValue }
}

struct UserSpaceDynamicPage: Decodable {
    let code: Int
    let message: String?
    let data: DataPayload?

    struct DataPayload: Decodable {
        let items: [SpaceDynamicJSONValue]?
        let hasMore: Bool?
        let offset: String?

        enum CodingKeys: String, CodingKey {
            case items
            case hasMore = "has_more"
            case offset
        }
    }
}

struct UserSpaceDynamicPageResult {
    let items: [UserSpaceDynamicItem]
    let hasMore: Bool
    let nextOffset: String?
}

struct UserSpaceDynamicItem: Identifiable, Hashable {
    struct ImageAsset: Hashable, Identifiable {
        let url: String
        let width: CGFloat?
        let height: CGFloat?
        var id: String { url }
    }
    struct Original: Hashable {
        let author: Author
        let text: String
        let images: [ImageAsset]
        let video: Video?
        let live: Live?
        let previewCard: PreviewCard?
    }
    struct Author: Hashable {
        let mid: Int?
        let name: String
        let faceURL: String?
        let publishTime: String?
        let publishTimestamp: Int?
    }

    struct Statistics: Hashable {
        let like: Int
        let reply: Int
        let forward: Int
        let likeActive: Bool
    }

    struct CommentTarget: Hashable {
        let commentID: String?
        let resourceID: String?
        let type: Int?
    }

    struct RichTextNode: Identifiable, Hashable {
        enum Kind: Hashable { case text, link, mention, topic, emoji }
        let id: UUID
        let kind: Kind
        let text: String
        let url: String?
        let emojiURL: String?
    }

    struct Video: Hashable {
        let bvid: String?
        let aid: Int?
        let title: String
        let coverURL: String?
        let description: String?
        let duration: Int
        let playCount: Int
        let danmakuCount: Int
        let likeCount: Int
    }

    struct Live: Hashable {
        let roomID: String
        let title: String
        let coverURL: String?
        let onlineCount: String
        let areaName: String
        let link: String?
    }

    struct PreviewCard: Hashable {
        let title: String
        let subtitle: String?
        let coverURL: String?
        let link: String?
    }

    let id: String
    let type: String
    let author: Author
    let richText: [RichTextNode]
    let images: [ImageAsset]
    let video: Video?
    let live: Live?
    let previewCard: PreviewCard?
    let statistics: Statistics
    let commentTarget: CommentTarget
    let original: Original?

    var text: String { richText.map(\.text).joined() }
    var isDisplayable: Bool {
        !author.name.isEmpty || !text.isEmpty || !images.isEmpty || video != nil || live != nil || previewCard != nil || original != nil
    }

    static func make(from raw: SpaceDynamicJSONValue, depth: Int = 0) -> UserSpaceDynamicItem? {
        guard let object = raw.objectValue else { return nil }
        let modules = object["modules"]?.objectValue ?? [:]
        let authorValue = modules["module_author"]?.objectValue ?? [:]
        let dynamic = modules["module_dynamic"]?.objectValue ?? [:]
        let basic = object["basic"]?.objectValue ?? [:]
        let identifier = object.string("id_str", "id") ?? basic.string("id_str", "id")
        guard let id = identifier, !id.isEmpty else { return nil }

        let desc = dynamic["desc"]?.objectValue ?? [:]
        let major = dynamic["major"]?.objectValue ?? [:]
        let additional = dynamic["additional"]?.objectValue ?? [:]
        let richText = richNodes(from: desc)
        let fallbackText = firstText(in: [desc, dynamic, major, additional])
        let nodes = richText.isEmpty ? plainNodes(fallbackText) : richText
        let stat = modules["module_stat"]?.objectValue ?? [:]
        let item = UserSpaceDynamicItem(
            id: id,
            type: object.string("type") ?? "DYNAMIC_TYPE_UNKNOWN",
            author: Author(
                mid: authorValue.int("mid"),
                name: authorValue.string("name", "uname", "nickname") ?? "",
                faceURL: normalizedURL(authorValue.string("face", "avatar")),
                publishTime: authorValue.string("pub_time", "pubTime"),
                publishTimestamp: authorValue.int("pub_ts", "pubTs")
            ),
            richText: nodes,
            images: uniqueImages(in: [dynamic["major"], dynamic["desc"], dynamic["additional"]]),
            video: videoFrom(major),
            live: liveFrom(major),
            previewCard: preview(from: major, additional: additional),
            statistics: Statistics(
                like: stat.nestedCount("like", "likes") ?? stat.int("like", "likes") ?? object.int("like", "likes") ?? 0,
                reply: stat.nestedCount("reply", "comment", "comments") ?? stat.int("reply", "comment", "comments") ?? object.int("reply", "comment", "comments") ?? 0,
                forward: stat.nestedCount("forward", "repost", "share") ?? stat.int("forward", "repost", "share") ?? object.int("forward", "repost", "share") ?? 0,
                likeActive: stat.nestedBool("like", "likes") ?? false
            ),
            commentTarget: CommentTarget(
                commentID: basic.string("comment_id_str"),
                resourceID: basic.string("rid_str"),
                type: basic.int("comment_type")
            ),
            original: depth == 0 ? object["orig"].flatMap { make(from: $0, depth: 1).map { Original(author: $0.author, text: $0.text, images: $0.images, video: $0.video, live: $0.live, previewCard: $0.previewCard) } } : nil
        )
        return item.isDisplayable ? item : nil
    }
}

private extension SpaceDynamicJSONValue {
    var objectValue: [String: SpaceDynamicJSONValue]? {
        if case let .object(value) = self { return value }; return nil
    }
    var arrayValue: [SpaceDynamicJSONValue]? {
        if case let .array(value) = self { return value }; return nil
    }
    var stringValue: String? {
        switch self {
        case let .string(value): return value
        case let .number(value): return value.rounded() == value ? String(Int(value)) : String(value)
        case let .bool(value): return String(value)
        default: return nil
        }
    }
    var intValue: Int? {
        switch self {
        case let .number(value): return Int(value)
        case let .string(value): return Int(value) ?? Double(value).map(Int.init)
        case let .bool(value): return value ? 1 : 0
        default: return nil
        }
    }
}

private extension Dictionary where Key == String, Value == SpaceDynamicJSONValue {
    func string(_ keys: String...) -> String? { keys.lazy.compactMap { self[$0]?.stringValue?.trimmedDynamicText }.first }
    func int(_ keys: String...) -> Int? { keys.lazy.compactMap { self[$0]?.intValue }.first }
    func nestedCount(_ keys: String...) -> Int? { keys.lazy.compactMap { self[$0]?.objectValue?.int("count") }.first }
    func nestedBool(_ keys: String...) -> Bool? {
        keys.lazy.compactMap { key in
            guard let value = self[key]?.objectValue?["status"] else { return nil }
            if case let .bool(flag) = value { return flag }
            return value.intValue.map { $0 != 0 }
        }.first
    }
}

private func richNodes(from desc: [String: SpaceDynamicJSONValue]) -> [UserSpaceDynamicItem.RichTextNode] {
    guard let nodes = desc["rich_text_nodes"]?.arrayValue else { return [] }
    return nodes.compactMap { raw in
        guard let value = raw.objectValue else { return nil }
        let text = value.string("text", "orig_text", "raw_text") ?? ""
        guard !text.isEmpty else { return nil }
        let type = (value.string("type") ?? "").uppercased()
        let kind: UserSpaceDynamicItem.RichTextNode.Kind = type.contains("EMOJI") ? .emoji : type.contains("AT") ? .mention : type.contains("TOPIC") ? .topic : value.string("jump_url", "url") != nil ? .link : .text
        return .init(id: UUID(), kind: kind, text: text, url: normalizedURL(value.string("jump_url", "url")), emojiURL: normalizedURL(value["emoji"]?.objectValue?.string("icon_url", "url")))
    }
}

private func plainNodes(_ text: String?) -> [UserSpaceDynamicItem.RichTextNode] {
    guard let text = text?.trimmedDynamicText, !text.isEmpty else { return [] }
    return [.init(id: UUID(), kind: .text, text: text, url: nil, emojiURL: nil)]
}

private func firstText(in objects: [[String: SpaceDynamicJSONValue]]) -> String? {
    let keys = ["text", "orig_text", "raw_text", "content", "summary", "desc", "title"]
    return objects.lazy.compactMap { $0.string(keys[0], keys[1], keys[2], keys[3], keys[4], keys[5], keys[6]) }.first
}

private func videoFrom(_ major: [String: SpaceDynamicJSONValue]) -> UserSpaceDynamicItem.Video? {
    guard let archive = (major["archive"] ?? major["ugc_season"] ?? major["pgc"])?.objectValue else { return nil }
    return .init(bvid: archive.string("bvid"), aid: archive.int("aid"), title: archive.string("title") ?? "视频", coverURL: normalizedURL(archive.string("cover", "pic")), description: archive.string("desc", "description"), duration: archive.int("duration") ?? 0, playCount: archive["stat"]?.objectValue?.int("play", "view") ?? archive.int("play", "view") ?? 0, danmakuCount: archive["stat"]?.objectValue?.int("danmaku", "reply") ?? 0, likeCount: archive["stat"]?.objectValue?.int("like") ?? 0)
}

private func liveFrom(_ major: [String: SpaceDynamicJSONValue]) -> UserSpaceDynamicItem.Live? {
    let candidate = major["live"] ?? major["live_rcmd"]
    guard let raw = candidate else { return nil }
    let value = decodedJSONObject(from: raw) ?? raw
    guard let roomID = findString(in: value, keys: ["room_id", "roomid", "room_id_str"]) else { return nil }
    return .init(roomID: roomID, title: findString(in: value, keys: ["title", "room_name"]) ?? "直播", coverURL: normalizedURL(findString(in: value, keys: ["cover", "cover_from_user", "keyframe"])), onlineCount: findString(in: value, keys: ["online", "online_count", "watched_show"]) ?? "", areaName: findString(in: value, keys: ["area_name", "parent_area_name"]) ?? "", link: normalizedURL(findString(in: value, keys: ["jump_url", "link"])))
}

private func preview(from major: [String: SpaceDynamicJSONValue], additional: [String: SpaceDynamicJSONValue]) -> UserSpaceDynamicItem.PreviewCard? {
    let candidates = ["common", "article", "pgc", "courses", "music", "medialist", "ugc_season"].compactMap { major[$0]?.objectValue } + [additional["common"]?.objectValue].compactMap { $0 }
    guard let value = candidates.first else { return nil }
    let title = value.string("title", "head_text", "name") ?? "相关内容"
    return .init(title: title, subtitle: value.string("desc1", "desc2", "desc", "subtitle"), coverURL: normalizedURL(value.string("cover", "cover_url", "pic")), link: normalizedURL(value.string("jump_url", "url")))
}

private func uniqueImages(in roots: [SpaceDynamicJSONValue?]) -> [UserSpaceDynamicItem.ImageAsset] {
    var result: [UserSpaceDynamicItem.ImageAsset] = []
    var seen = Set<String>()
    func visit(_ value: SpaceDynamicJSONValue?, key: String? = nil) {
        guard let value else { return }
        switch value {
        case let .object(object):
            // 图片 URL 既可能直接作为对象的 src，也可能位于嵌套 url 字段；
            // 宽高则通常位于该 URL 所属的图片对象中。
            object.forEach { key, child in
                if ["src", "img_src", "image_url", "img_url", "url"].contains(key.lowercased()),
                   let url = normalizedURL(child.stringValue),
                   seen.insert(url).inserted
                {
                    result.append(
                        .init(
                            url: url,
                            width: object.int("width", "img_width").map(CGFloat.init),
                            height: object.int("height", "img_height").map(CGFloat.init)
                        )
                    )
                }
                visit(child, key: key)
            }
        case let .array(values): values.forEach { visit($0) }
        default:
            break
        }
    }
    roots.forEach { visit($0) }
    return result
}

private func decodedJSONObject(from value: SpaceDynamicJSONValue) -> SpaceDynamicJSONValue? {
    guard case let .string(text) = value, let data = text.data(using: .utf8) else { return nil }
    return try? JSONDecoder().decode(SpaceDynamicJSONValue.self, from: data)
}

private func findString(in value: SpaceDynamicJSONValue, keys: [String]) -> String? {
    switch value {
    case let .object(object):
        if let direct = object.string(keys.first ?? "") { return direct }
        for key in keys { if let value = object[key]?.stringValue?.trimmedDynamicText { return value } }
        return object.values.lazy.compactMap { findString(in: $0, keys: keys) }.first
    case let .array(values): return values.lazy.compactMap { findString(in: $0, keys: keys) }.first
    default: return nil
    }
}

private func normalizedURL(_ raw: String?) -> String? {
    guard var value = raw?.trimmedDynamicText, !value.isEmpty else { return nil }
    if value.hasPrefix("//") { value = "https:" + value }
    if value.hasPrefix("http://") { value = "https://" + value.dropFirst(7) }
    return value
}

private extension String {
    var trimmedDynamicText: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
