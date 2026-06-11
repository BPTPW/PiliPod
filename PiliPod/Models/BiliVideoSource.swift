//
//  BiliVideoSource.swift
//  PiliPod
//
//  Created by co on 2026/5/21.
//

import Foundation

struct BiliVideoSource: Equatable {
    let videoURL: URL
    let audioURL: URL

    let width: Int
    let height: Int

    let videoCodecs: String
    let audioCodecs: String

    let videoBandwidth: Int
    let audioBandwidth: Int

    let fps: Int

    var aspectRatio: CGFloat {
        CGFloat(width) / CGFloat(height)
    }
}

// MARK: - PlayURL API Response

struct PlayUrlResponse: Decodable {
    let code: Int
    let message: String?
    let data: PlayUrlData
}

struct PlayUrlData: Decodable {
    let dash: DASHData
    let quality: Int?
    let acceptDescription: [String]
    let acceptQuality: [Int]
    let video_codecid: Int?

    enum CodingKeys: String, CodingKey {
        case dash
        case quality
        case acceptDescription = "accept_description"
        case acceptQuality = "accept_quality"
        case video_codecid
    }
}

struct DASHData: Decodable {
    let video: [DASHVideo]
    let audio: [DASHAudio]
    let dolby: DolbyData?
    let flac: FlacData?
}

struct DASHVideo: Decodable {
    let id: Int
    let baseUrl: String
    let backupUrl: [String]?
    let bandwidth: Int
    let mimeType: String
    let codecs: String
    let width: Int
    let height: Int
    let frameRate: String
    let sar: String?

    enum CodingKeys: String, CodingKey {
        case id
        case baseUrl
        case backupUrl
        case bandwidth
        case mimeType
        case codecs
        case width
        case height
        case frameRate
        case sar
        case base_url
        case backup_url
        case mime_type
        case frame_rate
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        baseUrl = try container.decodeIfPresent(String.self, forKey: .baseUrl)
            ?? container.decode(String.self, forKey: .base_url)
        backupUrl = try container.decodeIfPresent([String].self, forKey: .backupUrl)
            ?? container.decodeIfPresent([String].self, forKey: .backup_url)
        bandwidth = try container.decode(Int.self, forKey: .bandwidth)
        mimeType = try container.decodeIfPresent(String.self, forKey: .mimeType)
            ?? container.decode(String.self, forKey: .mime_type)
        codecs = try container.decode(String.self, forKey: .codecs)
        width = try container.decode(Int.self, forKey: .width)
        height = try container.decode(Int.self, forKey: .height)
        frameRate = try container.decodeIfPresent(String.self, forKey: .frameRate)
            ?? container.decodeIfPresent(String.self, forKey: .frame_rate)
            ?? "30"
        sar = try container.decodeIfPresent(String.self, forKey: .sar)
    }
}

struct DASHAudio: Decodable {
    let id: Int
    let baseUrl: String
    let backupUrl: [String]?
    let bandwidth: Int
    let mimeType: String
    let codecs: String
    let channels: Int?
    let sampleRate: String?

    enum CodingKeys: String, CodingKey {
        case id
        case baseUrl
        case backupUrl
        case bandwidth
        case mimeType
        case codecs
        case channels
        case sampleRate
        case base_url
        case backup_url
        case mime_type
        case sample_rate
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        baseUrl = try container.decodeIfPresent(String.self, forKey: .baseUrl)
            ?? container.decode(String.self, forKey: .base_url)
        backupUrl = try container.decodeIfPresent([String].self, forKey: .backupUrl)
            ?? container.decodeIfPresent([String].self, forKey: .backup_url)
        bandwidth = try container.decode(Int.self, forKey: .bandwidth)
        mimeType = try container.decodeIfPresent(String.self, forKey: .mimeType)
            ?? container.decode(String.self, forKey: .mime_type)
        codecs = try container.decode(String.self, forKey: .codecs)
        channels = try container.decodeIfPresent(Int.self, forKey: .channels)
        sampleRate = try container.decodeIfPresent(String.self, forKey: .sampleRate)
            ?? container.decodeIfPresent(String.self, forKey: .sample_rate)
    }
}

struct DolbyData: Decodable {
    let type: Int?
    let audio: [DASHAudio]?
}

struct FlacData: Decodable {
    let audio: DASHAudio?
}

// MARK: - Video Detail Response

struct VideoDetailResponse: Codable {
    let code: Int
    let data: VideoDetailData
}

struct VideoDetailData: Codable {
    let aid: Int
    let bvid: String
    let cid: Int
    let title: String
    let desc: String
    let duration: Int
    let owner: VideoOwner
    let pages: [VideoPage]
    let pic: String
    let videos: Int
    let copyright: Int
    let pubdate: Int
    let descV2: [DescV2Item]?
    let stat: VideoStat

    enum CodingKeys: String, CodingKey {
        case aid
        case bvid
        case cid
        case title
        case desc
        case duration
        case owner
        case pages
        case pic
        case videos
        case copyright
        case pubdate
        case descV2 = "desc_v2"
        case stat
    }
}

struct VideoOwner: Codable {
    let mid: Int
    let name: String
    let face: String
}

struct VideoPage: Codable {
    let cid: Int
    let page: Int
    let part: String
    let duration: Int
}

struct VideoPageListResponse: Codable {
    let code: Int
    let message: String
    let ttl: Int
    let data: [VideoPageListItem]
}

struct VideoPageListItem: Codable, Identifiable, Equatable {
    let cid: Int
    let page: Int
    let part: String
    let duration: Int
    let firstFrame: String?

    var id: Int { cid }

    enum CodingKeys: String, CodingKey {
        case cid
        case page
        case part
        case duration
        case firstFrame = "first_frame"
    }
}

struct DescV2Item: Codable, Identifiable {
    let rawText: String
    let type: Int
    let bizId: Int64

    var id: String {
        "\(type)-\(bizId)-\(rawText)"
    }

    enum CodingKeys: String, CodingKey {
        case rawText = "raw_text"
        case type
        case bizId = "biz_id"
    }
}

struct VideoStat: Codable {
    let view: Int
    let danmaku: Int
    let reply: Int
    let favorite: Int
    let coin: Int
    let share: Int
    let like: Int
}

// MARK: - History Report Response

struct HistoryReportResponse: Codable {
    let code: Int
}
