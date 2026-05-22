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

struct PlayUrlResponse: Codable {
    let code: Int
    let data: PlayUrlData
}

struct PlayUrlData: Codable {
    let dash: DASHData
    let quality: Int?
    let video_codecid: Int?

    enum CodingKeys: String, CodingKey {
        case dash
        case quality
        case video_codecid
    }
}

struct DASHData: Codable {
    let video: [DASHVideo]
    let audio: [DASHAudio]
    let dolby: DolbyData?
    let flac: FlacData?
}

struct DASHVideo: Codable {
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
    }
}

struct DASHAudio: Codable {
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
    }
}

struct DolbyData: Codable {
    let type: Int?
    let audio: [DASHAudio]?
}

struct FlacData: Codable {
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

// MARK: - History Report Response

struct HistoryReportResponse: Codable {
    let code: Int
}
