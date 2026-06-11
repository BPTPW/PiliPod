//
//  BiliAPI.swift
//  PiliPod
//
//  Created by co on 2026/5/21.
//

import CoreGraphics
import CryptoKit
import Foundation
import SwiftProtobuf

class BiliAPI {
    static let shared = BiliAPI()

    // PiliPlus 中通用的 Bilibili 移动端 AppKey 和 Secret
    private static let appKey = "dfca71928277209b"
    private static let appSecret = "b5475a8825547a4fc26c7d518eaaa02e"

    private init() {}

    // MARK: - 创建带登录状态的http请求

    private func makeRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url)

        let cookie = LoginSession.shared.cookieString
        if !cookie.isEmpty {
            request.setValue(cookie, forHTTPHeaderField: "Cookie")
        }

        return request
    }

    // MARK: - 轻量表单 POST（不加签）

    private func makePostFormRequest(
        urlString: String,
        parameters: [String: String]
    ) -> URLRequest? {
        guard let url = URL(string: urlString) else { return nil }

        var request = makeRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(
            "application/x-www-form-urlencoded",
            forHTTPHeaderField: "Content-Type"
        )
        request.setValue(
            "bili-universal/103300 (iPhone; iOS 18.2; Scale/3.00)",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("https://www.bilibili.com", forHTTPHeaderField: "Referer")

        // cookie登录状态
        let cookie = LoginSession.shared.cookieString
        if !cookie.isEmpty {
            request.setValue(cookie, forHTTPHeaderField: "Cookie")
        }

        var components = URLComponents()
        components.queryItems = parameters.map {
            URLQueryItem(name: $0.key, value: $0.value)
        }
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)
        return request
    }

    // MARK: - 构建移动端 App 请求（加签 + 公共参数）

    private func makeAppRequest(
        baseURLString: String,
        method: String = "GET",
        parameters: [String: String] = [:]
    ) -> URLRequest? {
        guard let baseURL = URL(string: baseURLString) else { return nil }

        // 合并业务参数与系统公共移动端参数
        var allParams = parameters
        allParams["appkey"] = BiliAPI.appKey
        allParams["mobi_app"] = "android_hd"
        allParams["platform"] = "android"
        allParams["ts"] = String(Int(Date().timeIntervalSince1970))

        // 写入移动端凭证 accessKey
        if let accessKey = LoginSession.shared.accessKey, !accessKey.isEmpty {
            allParams["access_key"] = accessKey
        }

        // 进行签名
        allParams["sign"] = generateSign(for: allParams)
        let paramsString = makeOrderedBodyString(from: allParams)

        // 组装真正的 URLRequest
        var request = URLRequest(url: baseURL)
        request.httpMethod = method

        // 伪造符合 iOS 移动端行为的公共 Header
        request.setValue("bili-universal/103300 (iPhone; iOS 18.2; Scale/3.00)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        // 移动端请求作为稳妥保障，一并带上 Cookie
        let cookie = LoginSession.shared.cookieString
        if !cookie.isEmpty {
            request.setValue(cookie, forHTTPHeaderField: "Cookie")
        }

        // 7. 根据 GET 还是 POST 将带 sign 的参数绑定到 Request 中
        if method.uppercased() == "GET" {
            if var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) {
                if let existing = components.percentEncodedQuery, !existing.isEmpty {
                    components.percentEncodedQuery = existing + "&" + paramsString
                } else {
                    components.percentEncodedQuery = paramsString
                }
                if let finalURL = components.url {
                    request.url = finalURL
                }
            }
        } else {
            request.httpBody = paramsString.data(using: .utf8)
        }

        return request
    }

    // MARK: - MD5 工具

    private func md5(_ string: String) -> String {
        let digest = Insecure.MD5.hash(data: Data(string.utf8))
        return digest.map { String(format: "%02hhx", $0) }.joined()
    }

    // MARK: - 获取视频评论（gRPC）

    func fetchVideoCommentMainList(
        aid: Int64,
        next: Int64 = 0,
        mode: Bilibili_Main_Community_Reply_V1_Mode = .mainListHot
    ) async throws -> Bilibili_Main_Community_Reply_V1_MainListReply {
        var reqMessage = Bilibili_Main_Community_Reply_V1_MainListReq()
        reqMessage.oid = aid
        reqMessage.type = 1
        reqMessage.cursor = .init()
        reqMessage.cursor.next = next
        reqMessage.cursor.mode = mode

        let payload = try await sendGrpcUnary(
            path: "/bilibili.main.community.reply.v1.Reply/MainList",
            body: reqMessage.serializedData()
        )
        return try Bilibili_Main_Community_Reply_V1_MainListReply(serializedBytes: payload)
    }

    func fetchVideoCommentDetailList(
        aid: Int64,
        rootRpid: Int64,
        next: Int64 = 0,
        mode: Bilibili_Main_Community_Reply_V1_Mode = .mainListHot
    ) async throws -> Bilibili_Main_Community_Reply_V1_DetailListReply {
        var reqMessage = Bilibili_Main_Community_Reply_V1_DetailListReq()
        reqMessage.oid = aid
        reqMessage.type = 1
        reqMessage.root = rootRpid
        reqMessage.rpid = rootRpid
        reqMessage.scene = .reply
        reqMessage.cursor = .init()
        reqMessage.cursor.next = next
        reqMessage.cursor.mode = mode

        let payload = try await sendGrpcUnary(
            path: "/bilibili.main.community.reply.v1.Reply/DetailList",
            body: reqMessage.serializedData()
        )
        return try Bilibili_Main_Community_Reply_V1_DetailListReply(serializedBytes: payload)
    }

    private func sendGrpcUnary(path: String, body: Data) async throws -> Data {
        guard let url = URL(string: "https://grpc.biliapi.net\(path)") else {
            throw APIError.invalidURL
        }

        var grpcBody = Data([0x00])
        var length = UInt32(body.count).bigEndian
        withUnsafeBytes(of: &length) { bytes in
            grpcBody.append(contentsOf: bytes)
        }
        grpcBody.append(body)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = grpcBody
        request.setValue("application/grpc", forHTTPHeaderField: "Content-Type")
        request.setValue("trailers", forHTTPHeaderField: "TE")
        request.setValue("grpc.biliapi.net", forHTTPHeaderField: "Host")
        request.setValue(
            "bili-universal/7320300 os/ios model/iPhone 13 mobi_app/iphone build/7320300 network/2 wifi/0 channel/AppStore",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("https://www.bilibili.com", forHTTPHeaderField: "Referer")

        let cookie = LoginSession.shared.cookieString
        if !cookie.isEmpty {
            request.setValue(cookie, forHTTPHeaderField: "Cookie")
        }
        if let accessKey = LoginSession.shared.accessKey, !accessKey.isEmpty {
            request.setValue("identify_v1 \(accessKey)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.requestFailed
        }
        guard (200 ... 299).contains(httpResponse.statusCode) else {
            throw APIError.requestFailed
        }

        let headerGrpcStatus = httpResponse.value(forHTTPHeaderField: "grpc-status")
        let headerGrpcMessage = httpResponse.value(forHTTPHeaderField: "grpc-message")
        if let headerGrpcStatus, headerGrpcStatus != "0" {
            throw APIError.grpcError(
                status: headerGrpcStatus,
                message: decodeGrpcMessage(headerGrpcMessage)
            )
        }

        var idx = 0
        while idx + 5 <= data.count {
            let flag = data[idx]
            let lenData = data[(idx + 1)..<(idx + 5)]
            let payloadLength = lenData.reduce(UInt32(0)) { acc, byte in
                (acc << 8) | UInt32(byte)
            }
            idx += 5
            let end = idx + Int(payloadLength)
            guard end <= data.count else { break }
            let payload = data[idx..<end]
            idx = end

            if flag & 0x80 == 0 {
                return Data(payload)
            }

            if flag & 0x80 != 0,
               let trailerText = String(data: payload, encoding: .utf8)
            {
                let status = parseTrailerValue("grpc-status", in: trailerText)
                if let status, status != "0" {
                    let message = parseTrailerValue("grpc-message", in: trailerText)
                    throw APIError.grpcError(
                        status: status,
                        message: decodeGrpcMessage(message)
                    )
                }
            }
        }

        throw APIError.requestFailed
    }

    private func parseTrailerValue(_ key: String, in trailerText: String) -> String? {
        for line in trailerText.split(separator: "\r\n", omittingEmptySubsequences: true) {
            let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: true)
            guard parts.count == 2 else { continue }
            if parts[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == key.lowercased() {
                return parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
    }

    private func decodeGrpcMessage(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "unknown" }
        let replaced = raw.replacingOccurrences(of: "+", with: " ")
        return replaced.removingPercentEncoding ?? raw
    }

    // MARK: - 获取网页版推荐视频

    func fetchRecommendVideos(
        freshIdx: Int,
        freshType: Int,
        brush: Int
    ) async throws -> [VideoItem] {
        var components = URLComponents(
            string: "https://api.bilibili.com/x/web-interface/index/top/feed/rcmd"
        )
        components?.queryItems = [
            URLQueryItem(name: "fresh_idx", value: String(freshIdx)),
            URLQueryItem(name: "fresh_type", value: String(freshType)),
            URLQueryItem(name: "brush", value: String(brush))
        ]

        guard let url = components?.url else {
            return []
        }

        let request = makeRequest(url: url)
        let (data, _) = try await URLSession.shared.data(for: request)

        let response = try JSONDecoder().decode(
            RecommendResponse.self,
            from: data
        )

        return response.data.item.map {
            VideoItem(from: $0)
        }
    }

    // MARK: - 获取首页直播 Feed

    func fetchLiveHomeFeed() async throws -> LiveHomeFeedPayload {
        let urlString = "https://api.live.bilibili.com/xlive/app-interface/v2/index/feed"
        let params: [String: String] = [
            "channel": "master",
            "actionKey": "appkey",
            "build": "8430300",
            "version": "8.43.0",
            "c_locale": "zh_CN",
            "device": "android",
            "device_name": "android",
            "device_type": "0",
            "fnval": "912",
            "disable_rcmd": "0",
            "https_url_req": "1",
            "mobi_app": "android",
            "network": "wifi",
            "page": "1",
            "platform": "android",
            "relation_page": "1",
            "s_locale": "zh_CN",
            "scale": "2",
            "statistics": #"{"appId":1,"platform":3,"version":"8.43.0","abtest":""}"#
        ]

        guard let request = makeAppRequest(baseURLString: urlString, method: "GET", parameters: params) else {
            throw APIError.invalidURL
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200 ... 299).contains(httpResponse.statusCode)
        else {
            throw APIError.requestFailed
        }

        let decoded = try JSONDecoder().decode(LiveIndexFeedResponse.self, from: data)
        guard decoded.code == 0 else {
            throw APIError.businessError(code: decoded.code, message: decoded.message)
        }

        var followingItems: [LiveFollowingItem] = []
        var areaTabs: [LiveAreaTab] = [LiveAreaTab(id: "recommend", title: "推荐")]
        var rooms: [LiveCardModel] = []

        for card in decoded.data?.cardList ?? [] {
            switch card.cardType {
            case "my_idol_v1":
                followingItems = (card.cardData.myIdol?.list ?? []).map { item in
                    LiveFollowingItem(
                        roomId: String(item.roomid),
                        uid: item.uid,
                        name: item.uname,
                        faceURL: item.face.replacingOccurrences(of: "http://", with: "https://"),
                        link: item.link
                    )
                }

            case "area_entrance_v3":
                let tabs = (card.cardData.areaEntrance?.list ?? []).map { tab in
                    LiveAreaTab(id: "area_\(tab.id)", title: tab.title)
                }
                if !tabs.isEmpty {
                    areaTabs.append(contentsOf: tabs)
                }

            case "small_card_v1":
                guard let room = card.cardData.smallCard, room.isAd == false else { continue }
                rooms.append(mapLiveSmallCard(room))

            default:
                continue
            }
        }

        return LiveHomeFeedPayload(
            followingItems: followingItems,
            areaTabs: areaTabs,
            rooms: rooms
        )
    }

    func fetchLivePlaybackInfo(roomID: String, qn: Int = 10000) async throws -> LivePlaybackInfo {
        var components = URLComponents(
            string: "https://api.live.bilibili.com/xlive/web-room/v2/index/getRoomPlayInfo"
        )
        components?.queryItems = [
            URLQueryItem(name: "room_id", value: roomID),
            URLQueryItem(name: "protocol", value: "0"),
            URLQueryItem(name: "format", value: "0"),
            URLQueryItem(name: "codec", value: "0"),
            URLQueryItem(name: "qn", value: String(qn)),
            URLQueryItem(name: "platform", value: "web"),
            URLQueryItem(name: "ptype", value: "8"),
            URLQueryItem(name: "dolby", value: "5"),
            URLQueryItem(name: "panorama", value: "1")
        ]

        guard let url = components?.url else {
            throw APIError.invalidURL
        }

        let signedURL = try await BiliWbiSigner.shared.sign(url: url)
        let request = makeRequest(url: signedURL)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200 ... 299).contains(httpResponse.statusCode)
        else {
            throw APIError.requestFailed
        }

        let decoded = try JSONDecoder().decode(LiveRoomPlayInfoResponse.self, from: data)
        guard decoded.code == 0 else {
            throw APIError.businessError(code: decoded.code, message: decoded.message)
        }
        guard let payload = decoded.data else {
            throw APIError.requestFailed
        }
        let playurl = payload.playurlInfo.playurl

        guard
            let selectedCodec = liveAVCCodec(from: playurl),
            let urlInfo = selectedCodec.urlInfo.first,
            let streamURL = buildLiveStreamURL(
                host: urlInfo.host,
                baseURL: selectedCodec.baseURL,
                extra: urlInfo.extra,
                qn: qn
            )
        else {
            throw APIError.requestFailed
        }

        let aspectRatio: CGFloat = payload.isPortrait ? (9.0 / 16.0) : (16.0 / 9.0)
        let acceptedQualityCodes = Set(selectedCodec.acceptQn)
        let qualityOptions = playurl.gQnDesc
            .filter { acceptedQualityCodes.contains($0.qn) }
            .map { quality in
                VideoQualityOption(
                    id: quality.qn,
                    code: quality.qn,
                    label: liveQualityLabel(for: quality.qn, fallback: quality.desc)
                )
            }
            .sorted { $0.code < $1.code }

        return LivePlaybackInfo(
            roomID: String(payload.roomID),
            streamURL: streamURL,
            aspectRatio: aspectRatio,
            currentQn: qn,
            qualityOptions: qualityOptions
        )
    }

    private func liveAVCCodec(from playurl: LiveRoomPlayurl) -> LiveRoomCodec? {
        playurl.stream
            .first(where: { $0.protocolName == "http_stream" })?
            .format.first(where: { $0.formatName == "flv" })?
            .codec.first(where: { codec in
                let normalized = codec.codecName.lowercased()
                return normalized == "avc" || normalized == "h264"
            })
    }

    private func liveQualityLabel(for code: Int, fallback: String?) -> String {
        switch code {
        case 80: return "流畅"
        case 150: return "高清"
        case 250: return "超清"
        case 400: return "蓝光"
        case 10000: return "原画"
        case 15000: return "2K"
        case 20000: return "4K"
        case 30000: return "杜比"
        default: return fallback ?? String(code)
        }
    }

    func fetchLiveDanmakuInfo(roomID: Int) async throws -> LiveDanmakuInfo {
        var components = URLComponents(
            string: "https://api.live.bilibili.com/xlive/web-room/v1/index/getDanmuInfo"
        )
        components?.queryItems = [
            URLQueryItem(name: "id", value: String(roomID)),
            URLQueryItem(name: "type", value: "0"),
            URLQueryItem(name: "web_location", value: "444.8")
        ]

        guard let url = components?.url else {
            throw APIError.invalidURL
        }

        let signedURL = try await BiliWbiSigner.shared.sign(url: url)
        let request = makeRequest(url: signedURL)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200 ... 299).contains(httpResponse.statusCode)
        else {
            throw APIError.requestFailed
        }

        let decoded = try JSONDecoder().decode(LiveDanmakuInfoResponse.self, from: data)
        guard decoded.code == 0 else {
            throw APIError.businessError(code: decoded.code, message: decoded.message)
        }
        guard let payload = decoded.data else {
            throw APIError.requestFailed
        }

        return LiveDanmakuInfo(
            token: payload.token,
            hosts: payload.hostList.map { LiveDanmakuHost(host: $0.host, wssPort: $0.wssPort) }
        )
    }

    func fetchLiveDanmakuHistory(roomID: Int) async throws -> [LiveDanmakuMessage] {
        var components = URLComponents(
            string: "https://api.live.bilibili.com/xlive/web-room/v1/dM/gethistory"
        )
        components?.queryItems = [
            URLQueryItem(name: "roomid", value: String(roomID))
        ]

        guard let url = components?.url else {
            throw APIError.invalidURL
        }

        let request = makeRequest(url: url)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200 ... 299).contains(httpResponse.statusCode)
        else {
            throw APIError.requestFailed
        }

        let decoded = try JSONDecoder().decode(LiveDanmakuHistoryResponse.self, from: data)
        guard decoded.code == 0 else {
            throw APIError.businessError(code: decoded.code, message: decoded.message)
        }
        guard let payload = decoded.data else {
            throw APIError.requestFailed
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        return (payload.admin + payload.room)
            .map { item in
                LiveDanmakuMessage(
                    username: item.nickname,
                    content: item.text,
                    sentAt: formatter.date(from: item.timeline),
                    emoticons: item.emots?.compactMap { key, value in
                        let placeholder = value.emoji ?? value.descript ?? key
                        guard !placeholder.isEmpty else { return nil }
                        let urlString = value.url?.replacingOccurrences(of: "http://", with: "https://")
                        return LiveDanmakuEmoticon(
                            placeholder: placeholder,
                            url: urlString.flatMap(URL.init(string:)),
                            width: CGFloat(max(value.width ?? value.height ?? 20, 1)),
                            height: CGFloat(max(value.height ?? value.width ?? 20, 1))
                        )
                    } ?? []
                )
            }
            .sorted {
                switch ($0.sentAt, $1.sentAt) {
                case let (lhs?, rhs?):
                    return lhs < rhs
                case (.some, nil):
                    return true
                case (nil, .some):
                    return false
                case (nil, nil):
                    return false
                }
            }
    }

    func fetchLiveRoomInfo(roomID: String) async throws -> LiveRoomInfo {
        var components = URLComponents(
            string: "https://api.live.bilibili.com/xlive/web-room/v1/index/getH5InfoByRoom"
        )
        components?.queryItems = [
            URLQueryItem(name: "room_id", value: roomID)
        ]

        guard let url = components?.url else {
            throw APIError.invalidURL
        }

        let request = makeRequest(url: url)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200 ... 299).contains(httpResponse.statusCode)
        else {
            throw APIError.requestFailed
        }

        let decoded = try JSONDecoder().decode(LiveRoomInfoResponse.self, from: data)
        guard decoded.code == 0 else {
            throw APIError.businessError(code: decoded.code, message: decoded.message)
        }
        guard let payload = decoded.data else {
            throw APIError.requestFailed
        }

        let areaParts = [payload.roomInfo.parentAreaName, payload.roomInfo.areaName]
            .filter { !$0.isEmpty }
        let areaName = Array(NSOrderedSet(array: areaParts)).compactMap { $0 as? String }.joined(separator: " · ")
        let backgroundURL = payload.roomInfo.appBackground.isEmpty ? nil : payload.roomInfo.appBackground
        let onlineText = payload.watchedShow?.textLarge ?? "\(VideoItem.formatCount(payload.roomInfo.online))人气"

        return LiveRoomInfo(
            roomID: String(payload.roomInfo.roomID),
            uid: payload.anchorInfo.baseInfo.uid,
            title: payload.roomInfo.title,
            coverURL: payload.roomInfo.cover.replacingOccurrences(of: "http://", with: "https://"),
            backgroundURL: backgroundURL?.replacingOccurrences(of: "http://", with: "https://"),
            onlineCount: onlineText,
            anchorName: payload.anchorInfo.baseInfo.uname,
            faceURL: payload.anchorInfo.baseInfo.face.replacingOccurrences(of: "http://", with: "https://"),
            areaName: areaName
        )
    }

    // MARK: - 获取视频相关推荐

    func fetchRelatedVideos(bvid: String, limit: Int = 40) async throws -> [VideoItem] {
        var components = URLComponents(
            string: "https://api.bilibili.com/x/web-interface/archive/related"
        )
        components?.queryItems = [
            URLQueryItem(name: "bvid", value: bvid)
        ]

        guard let url = components?.url else {
            throw APIError.invalidURL
        }

        let request = makeRequest(url: url)
        let (data, _) = try await URLSession.shared.data(for: request)

        let response = try JSONDecoder().decode(RelatedVideosResponse.self, from: data)

        guard response.code == 0 else {
            throw APIError.responseError(response.code)
        }

        let videos = response.data ?? []
        return videos
            .filter { $0.bvid != bvid }
            .prefix(max(0, min(limit, 40)))
            .map { VideoItem(from: $0) }
    }

    // MARK: - 获取App版推荐视频

    func fetchAppRecommendVideos(idx: Int, flush: Int) async throws -> Data {
        // App 推荐数据的基准接口地址
        let appRcmdHost = "https://app.bilibili.com/x/v2/feed/index"

        // 组装所需的特定业务参数
        let businessParams: [String: String] = [
            "idx": String(idx),
            "flush": String(flush),
            "pull": flush == 1 ? "true" : "false",
            "device": "phone",
            "login_event": "1"
        ]

        // 使用新封装的加签构造器创建请求
        guard var request = makeAppRequest(baseURLString: appRcmdHost, method: "GET", parameters: businessParams) else {
            throw APIError.invalidURL
        }

        // 添加请求 headers
        request.setValue(BiliDeviceConfig.shared.buvid, forHTTPHeaderField: "buvid")
        request.setValue("1111111111111111111111111111111111111111111111111111111111111111", forHTTPHeaderField: "fp_local")
        request.setValue("1111111111111111111111111111111111111111111111111111111111111111", forHTTPHeaderField: "fp_remote")
        request.setValue("11111111", forHTTPHeaderField: "session_id")
        request.setValue("prod", forHTTPHeaderField: "env")
        request.setValue("android_hd", forHTTPHeaderField: "app-key")
        request.setValue("11111111111111111111111111111111:1111111111111111:0:0", forHTTPHeaderField: "x-bili-trace-id")
        request.setValue("", forHTTPHeaderField: "x-bili-aurora-eid")
        request.setValue("", forHTTPHeaderField: "x-bili-aurora-zone")
        request.setValue("cronet", forHTTPHeaderField: "bili-http-engine")

        print(request.url)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200 ... 299).contains(httpResponse.statusCode)
        else {
            throw APIError.requestFailed
        }

        return data
    }

    // MARK: - 获取并解析App版推荐Feed

    func fetchAppRecommendFeed(idx: Int, flush: Int) async throws -> (cards: [FeedCardItem], nextIdx: Int) {
        let data = try await fetchAppRecommendVideos(idx: idx, flush: flush)
        let parsed = try parseAppRecommendFeed(from: data)
        return parsed
    }

    // MARK: - 获取个人空间信息（App）

    func fetchUserSpace(mid: Int, fromViewAid: Int?) async throws -> UserSpaceData {
        let urlString = "https://app.bilibili.com/x/v2/space"
        var params = makeSpaceCommonParameters(mid: mid)

        if let fromViewAid {
            params["from_view_aid"] = String(fromViewAid)
        }

        guard let request = makeAppRequest(baseURLString: urlString, method: "GET", parameters: params) else {
            throw APIError.invalidURL
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200 ... 299).contains(httpResponse.statusCode)
        else {
            throw APIError.requestFailed
        }

        let decoded = try JSONDecoder().decode(UserSpaceResponse.self, from: data)
        guard decoded.code == 0 else {
            throw APIError.businessError(code: decoded.code, message: decoded.message)
        }
        guard let spaceData = decoded.data else {
            throw APIError.requestFailed
        }

        return spaceData
    }

    // MARK: - 获取个人空间投稿（App，游标分页）

    func fetchSpaceArchiveCursor(
        mid: Int,
        aid: Int?,
        order: String = "pubdate",
        ps: Int = 20,
        qn: Int = 80
    ) async throws -> SpaceArchiveData {
        let urlString = "https://app.biliapi.com/x/v2/space/archive/cursor"
        var params = makeSpaceCommonParameters(mid: mid)
        params["order"] = order
        params["ps"] = String(ps)
        params["qn"] = String(qn)
        if let aid {
            params["aid"] = String(aid)
        }

        guard let request = makeAppRequest(baseURLString: urlString, method: "GET", parameters: params) else {
            throw APIError.invalidURL
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200 ... 299).contains(httpResponse.statusCode)
        else {
            throw APIError.requestFailed
        }

        let decoded = try JSONDecoder().decode(SpaceArchiveResponse.self, from: data)
        guard decoded.code == 0 else {
            throw APIError.businessError(code: decoded.code, message: decoded.message)
        }
        guard let archiveData = decoded.data else {
            throw APIError.requestFailed
        }

        return archiveData
    }

    // MARK: - 获取历史记录

    func fetchHistoryList(
        max: Int? = nil,
        business: String? = nil,
        viewAt: Int? = nil,
        type: String = "archive",
        ps: Int = 20
    ) async throws -> HistoryData {
        var components = URLComponents(string: "https://api.bilibili.com/x/web-interface/history/cursor")
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "type", value: type),
            URLQueryItem(name: "ps", value: String(ps))
        ]

        if let max {
            queryItems.append(URLQueryItem(name: "max", value: String(max)))
        }
        if let business, !business.isEmpty {
            queryItems.append(URLQueryItem(name: "business", value: business))
        }
        if let viewAt {
            queryItems.append(URLQueryItem(name: "view_at", value: String(viewAt)))
        }

        components?.queryItems = queryItems

        guard let url = components?.url else {
            throw APIError.invalidURL
        }

        let request = makeRequest(url: url)
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200 ... 299).contains(httpResponse.statusCode)
        else {
            throw APIError.requestFailed
        }

        let decoded = try JSONDecoder().decode(HistoryResponse.self, from: data)
        guard decoded.code == 0 else {
            throw APIError.businessError(code: decoded.code, message: decoded.message)
        }
        guard let historyData = decoded.data else {
            throw APIError.requestFailed
        }

        return historyData
    }

    // MARK: - 获取关注列表

    func fetchFollowingList(
        vmid: Int,
        pn: Int = 1,
        ps: Int = 50,
        orderType: String? = nil
    ) async throws -> FollowingData {
        var components = URLComponents(string: "https://api.bilibili.com/x/relation/followings")
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "vmid", value: String(vmid)),
            URLQueryItem(name: "pn", value: String(pn)),
            URLQueryItem(name: "ps", value: String(ps))
        ]

        if let orderType, !orderType.isEmpty {
            queryItems.append(URLQueryItem(name: "order_type", value: orderType))
        }

        components?.queryItems = queryItems

        guard let url = components?.url else {
            throw APIError.invalidURL
        }

        let request = makeRequest(url: url)
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200 ... 299).contains(httpResponse.statusCode)
        else {
            throw APIError.requestFailed
        }

        let decoded = try JSONDecoder().decode(FollowingResponse.self, from: data)
        guard decoded.code == 0 else {
            throw APIError.businessError(code: decoded.code, message: decoded.message)
        }
        guard let followingData = decoded.data else {
            throw APIError.requestFailed
        }

        return followingData
    }

    // MARK: - 获取搜索热榜

    func fetchSearchTrending(limit: Int = 10) async throws -> [SearchTrendingItem] {
        var components = URLComponents(string: "https://api.bilibili.com/x/v2/search/trending/ranking")
        components?.queryItems = [
            URLQueryItem(name: "limit", value: String(limit))
        ]

        guard let url = components?.url else {
            throw APIError.invalidURL
        }

        let request = makeRequest(url: url)
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200 ... 299).contains(httpResponse.statusCode)
        else {
            throw APIError.requestFailed
        }

        let decoded = try JSONDecoder().decode(SearchTrendingResponse.self, from: data)
        guard decoded.code == 0 else {
            throw APIError.businessError(code: decoded.code, message: decoded.message)
        }

        return decoded.data?.list ?? []
    }

    // MARK: - 获取搜索发现

    func fetchSearchRecommend() async throws -> [SearchRecommendItem] {
        let urlString = "https://app.bilibili.com/x/v2/search/recommend"

        let params: [String: String] = [
            "from": "2",
            "channel": "master",
            "c_locale": "zh_CN",
            "mobi_app": "android",
            "platform": "android",
            "s_locale": "zh_CN"
        ]

        guard let request = makeAppRequest(baseURLString: urlString, method: "GET", parameters: params) else {
            throw APIError.invalidURL
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        print(String(data: data, encoding: .utf8))

        guard let httpResponse = response as? HTTPURLResponse,
              (200 ... 299).contains(httpResponse.statusCode)
        else {
            throw APIError.requestFailed
        }

        let decoded = try JSONDecoder().decode(SearchRecommendResponse.self, from: data)
        guard decoded.code == 0 else {
            throw APIError.businessError(code: decoded.code, message: decoded.message)
        }

        return decoded.data?.list ?? []
    }

    // MARK: - 综合搜索

    func fetchComprehensiveSearch(keyword: String) async throws -> [SearchComprehensiveModule] {
        var components = URLComponents(
            string: "https://api.bilibili.com/x/web-interface/wbi/search/all/v2"
        )
        components?.queryItems = [
            URLQueryItem(name: "keyword", value: keyword)
        ]

        guard let url = components?.url else {
            throw APIError.invalidURL
        }

        let signedURL = try await BiliWbiSigner.shared.sign(url: url)
        var request = makeRequest(url: signedURL)
        request.setValue("https://www.bilibili.com", forHTTPHeaderField: "Referer")
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 18_2 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.2 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200 ... 299).contains(httpResponse.statusCode)
        else {
            throw APIError.requestFailed
        }

        let decoded = try JSONDecoder().decode(SearchComprehensiveResponse.self, from: data)
        guard decoded.code == 0 else {
            throw APIError.businessError(code: decoded.code, message: decoded.message)
        }

        return decoded.data?.result.filter(\.hasSupportedContent) ?? []
    }

    // MARK: - 分类搜索

    func fetchTypedVideoSearch(keyword: String, page: Int = 1) async throws -> SearchTypedVideoData {
        var components = URLComponents(
            string: "https://api.bilibili.com/x/web-interface/wbi/search/type"
        )
        components?.queryItems = [
            URLQueryItem(name: "search_type", value: "video"),
            URLQueryItem(name: "keyword", value: keyword),
            URLQueryItem(name: "page", value: String(page))
        ]

        guard let url = components?.url else {
            throw APIError.invalidURL
        }

        let signedURL = try await BiliWbiSigner.shared.sign(url: url)
        var request = makeRequest(url: signedURL)
        request.setValue("https://www.bilibili.com", forHTTPHeaderField: "Referer")
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 18_2 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.2 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200 ... 299).contains(httpResponse.statusCode)
        else {
            throw APIError.requestFailed
        }

        let decoded = try JSONDecoder().decode(SearchTypedVideoResponse.self, from: data)
        guard decoded.code == 0, let payload = decoded.data else {
            throw APIError.businessError(code: decoded.code, message: decoded.message)
        }

        return payload
    }

    func fetchTypedUserSearch(keyword: String, page: Int = 1) async throws -> SearchTypedUserData {
        var components = URLComponents(
            string: "https://api.bilibili.com/x/web-interface/wbi/search/type"
        )
        components?.queryItems = [
            URLQueryItem(name: "search_type", value: "bili_user"),
            URLQueryItem(name: "keyword", value: keyword),
            URLQueryItem(name: "page", value: String(page))
        ]

        guard let url = components?.url else {
            throw APIError.invalidURL
        }

        let signedURL = try await BiliWbiSigner.shared.sign(url: url)
        var request = makeRequest(url: signedURL)
        request.setValue("https://www.bilibili.com", forHTTPHeaderField: "Referer")
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 18_2 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.2 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200 ... 299).contains(httpResponse.statusCode)
        else {
            throw APIError.requestFailed
        }

        let decoded = try JSONDecoder().decode(SearchTypedUserResponse.self, from: data)
        guard decoded.code == 0, let payload = decoded.data else {
            throw APIError.businessError(code: decoded.code, message: decoded.message)
        }

        return payload
    }

    private func makeSpaceCommonParameters(mid: Int) -> [String: String] {
        [
            "build": "8430300",
            "version": "8.43.0",
            "c_locale": "zh_CN",
            "channel": "master",
            "mobi_app": "android",
            "platform": "android",
            "s_locale": "zh_CN",
            "statistics": "{\"appId\":1,\"platform\":3,\"version\":\"8.43.0\",\"abtest\":\"\"}",
            "vmid": String(mid)
        ]
    }

    // MARK: - 评论点赞/点踩

    func likeComment(
        oid: Int,
        rpid: Int,
        isCancel: Bool
    ) async throws {
        guard LoginSession.shared.isLogin else {
            throw APIError.responseError(-101)
        }
        guard let accessKey = LoginSession.shared.accessKey, !accessKey.isEmpty else {
            throw APIError.responseError(-111)
        }

        let urlString = "https://api.bilibili.com/x/v2/reply/action"
        let params: [String: String] = [
            "type": "1",
            "oid": String(oid),
            "rpid": String(rpid),
            "action": isCancel ? "0" : "1",
            "access_key": accessKey
        ]
        guard let request = makeAppRequest(baseURLString: urlString, method: "POST", parameters: params) else {
            throw APIError.invalidURL
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200 ... 299).contains(httpResponse.statusCode)
        else {
            throw APIError.requestFailed
        }

        let decoded = try JSONDecoder().decode(SimpleAPIResponse<EmptyCodable>.self, from: data)
        guard decoded.code == 0 else {
            throw APIError.responseError(decoded.code)
        }
    }

    func hateComment(
        oid: Int,
        rpid: Int,
        isCancel: Bool
    ) async throws {
        guard LoginSession.shared.isLogin else {
            throw APIError.responseError(-101)
        }
        guard let accessKey = LoginSession.shared.accessKey, !accessKey.isEmpty else {
            throw APIError.responseError(-111)
        }

        let urlString = "https://api.bilibili.com/x/v2/reply/hate"
        let params: [String: String] = [
            "type": "1",
            "oid": String(oid),
            "rpid": String(rpid),
            "action": isCancel ? "0" : "1",
            "access_key": accessKey
        ]
        guard let request = makeAppRequest(baseURLString: urlString, method: "POST", parameters: params) else {
            throw APIError.invalidURL
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200 ... 299).contains(httpResponse.statusCode)
        else {
            throw APIError.requestFailed
        }

        let decoded = try JSONDecoder().decode(SimpleAPIResponse<EmptyCodable>.self, from: data)
        guard decoded.code == 0 else {
            throw APIError.responseError(decoded.code)
        }
    }

    // MARK: - 发表评论 / 上传评论图片

    func uploadCommentImage(data: Data, fileName: String = "comment.jpg") async throws -> CommentImageUploadData {
        guard LoginSession.shared.isLogin else {
            throw APIError.responseError(-101)
        }
        guard let csrf = LoginSession.shared.cookies?.bili_jct, !csrf.isEmpty else {
            throw APIError.responseError(-111)
        }

        guard let url = URL(string: "https://api.bilibili.com/x/dynamic/feed/draw/upload_bfs") else {
            throw APIError.invalidURL
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        var request = makeRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("https://www.bilibili.com", forHTTPHeaderField: "Referer")
        request.httpBody = makeUploadBody(
            boundary: boundary,
            csrf: csrf,
            fileData: data,
            fileName: fileName
        )

        let (respData, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200 ... 299).contains(httpResponse.statusCode)
        else {
            throw APIError.requestFailed
        }

        let decoded = try JSONDecoder().decode(SimpleAPIResponse<CommentImageUploadData>.self, from: respData)
        guard decoded.code == 0, let payload = decoded.data else {
            throw APIError.businessError(code: decoded.code, message: decoded.message)
        }
        return payload
    }

    // MARK: - 发送评论

    func addVideoComment(
        oid: Int,
        message: String,
        pictures: [CommentPictureUploadPayload] = [],
        root: Int? = nil,
        parent: Int? = nil
    ) async throws -> CommentAddResponseData {
        guard LoginSession.shared.isLogin else {
            throw APIError.responseError(-101)
        }
        guard let csrf = LoginSession.shared.cookies?.bili_jct, !csrf.isEmpty else {
            throw APIError.responseError(-111)
        }

        let urlString = "https://api.bilibili.com/x/v2/reply/add"
        var params: [String: String] = [
            "type": "1",
            "oid": String(oid),
            "message": message,
            "csrf": csrf
        ]
        if !pictures.isEmpty,
           let payload = try? JSONEncoder().encode(pictures),
           let picturesJSONString = String(data: payload, encoding: .utf8)
        {
            params["pictures"] = picturesJSONString
        }
        if let root, root > 0 {
            params["root"] = String(root)
        }
        if let parent, parent > 0 {
            params["parent"] = String(parent)
        }

        guard let request = makeAppRequest(baseURLString: urlString, method: "POST", parameters: params) else {
            throw APIError.invalidURL
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200 ... 299).contains(httpResponse.statusCode)
        else {
            throw APIError.requestFailed
        }

        let decoded = try JSONDecoder().decode(SimpleAPIResponse<CommentAddResponseData>.self, from: data)
        guard decoded.code == 0, let payload = decoded.data else {
            throw APIError.businessError(code: decoded.code, message: decoded.message)
        }
        return payload
    }

    private func makeUploadBody(
        boundary: String,
        csrf: String,
        fileData: Data,
        fileName: String
    ) -> Data {
        var body = Data()

        func appendField(name: String, value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }

        appendField(name: "csrf", value: csrf)
        appendField(name: "category", value: "daily")
        appendField(name: "biz", value: "new_dyn")

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file_up\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n".data(using: .utf8)!)

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        return body
    }

    func fetchUserReplyEmotePackages() async throws -> [ReplyEmotePackage] {
        var components = URLComponents(string: "https://api.bilibili.com/x/emote/user/panel/web")
        components?.queryItems = [
            URLQueryItem(name: "business", value: "reply")
        ]
        guard let url = components?.url else {
            throw APIError.invalidURL
        }

        let request = makeRequest(url: url)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200 ... 299).contains(httpResponse.statusCode)
        else {
            throw APIError.requestFailed
        }

        let decoded = try JSONDecoder().decode(UserReplyEmotePanelResponse.self, from: data)
        guard decoded.code == 0 else {
            throw APIError.businessError(code: decoded.code, message: decoded.message)
        }

        let packages = decoded.data?.packages ?? []
        return packages.filter { $0.flags?.added != false }
    }

    // MARK: - 解析App推荐接口数据

    private func parseAppRecommendFeed(from data: Data) throws -> (cards: [FeedCardItem], nextIdx: Int) {
        let response = try JSONDecoder().decode(AppFeedResponse.self, from: data)

        guard response.code == 0, let items = response.data?.items else {
            throw APIError.responseError(response.code)
        }

        let nextIdx = response.data?.config?.idx ?? 0
        var result: [FeedCardItem] = []

        for item in items {
            guard let gotoType = item.goto else { continue }

            // 过滤广告、游戏推广、横幅
            if gotoType == "ad" || gotoType == "game" || gotoType == "banner" {
                continue
            }

            switch gotoType {
            case "av":
                let rawParam = item.param ?? ""
                let title = item.title ?? ""
                let cover = (item.cover ?? "")
                    .replacingOccurrences(of: "http://", with: "https://")
                let playCount = (item.coverLeftText2 ?? "")
                    .replacingOccurrences(of: "观看", with: "")
                let danmakuCount = (item.coverLeftText3 ?? "")
                    .replacingOccurrences(of: "弹幕", with: "")
                let upName = item.args?.upName ?? ""
                let duration = item.playerArgs?.duration ?? 0
                let cid = item.playerArgs?.cid
                let publishTimeText = item.coverRightText ?? "--"
                let bottomRcmdReasonText = item.bottomRcmdReasonStyle?.text

                // App 接口 param 可能是 aid（纯数字），统一转为 bvid
                let bvid: String
                if rawParam.hasPrefix("BV") {
                    bvid = rawParam
                } else if let aid = Int64(rawParam) {
                    bvid = BiliIdConverter.av2bv(aid: aid)
                } else {
                    bvid = rawParam
                }

                let videoItem = VideoItem(
                    bvid: bvid,
                    cid: cid,
                    cover: cover,
                    title: title,
                    playCount: playCount,
                    danmakuCount: danmakuCount,
                    uploader: upName,
                    duration: duration,
                    progressSeconds: nil,
                    publishTimeText: publishTimeText,
                    bottomRcmdReasonText: bottomRcmdReasonText
                )
                result.append(.video(videoItem))

            case "live":
                let roomId = item.param ?? ""
                let title = item.title ?? ""
                let cover = (item.cover ?? "")
                    .replacingOccurrences(of: "http://", with: "https://")
                let online = item.coverLeftText1 ?? ""
                let anchorName = item.args?.upName ?? ""

                let liveModel = LiveCardModel(
                    roomId: roomId,
                    uid: item.args?.upId,
                    title: title,
                    coverURL: cover,
                    onlineCount: online,
                    anchorName: anchorName,
                    faceURL: "",
                    areaName: "",
                    badgeText: nil,
                    link: nil
                )
                result.append(.live(liveModel))

            default:
                break
            }
        }

        return (result, nextIdx)
    }

    // MARK: - 获取当前用户数据

    func fetchMyInfo() async throws -> UserCard {
        let url = URL(string: "https://api.bilibili.com/x/web-interface/nav")!
        let request = makeRequest(url: url)

        let (data, _) = try await URLSession.shared.data(for: request)

        let response = try JSONDecoder().decode(
            NavResponse.self,
            from: data
        )

        return response.data
    }

    // MARK: - 获取当前用户状态（动态/关注/粉丝）

    func fetchMyStat() async throws -> MyStat {
        let url = URL(string: "https://api.bilibili.com/x/web-interface/nav/stat")!
        let request = makeRequest(url: url)

        let (data, _) = try await URLSession.shared.data(for: request)

        let response = try JSONDecoder().decode(
            MyStatResponse.self,
            from: data
        )

        return response.data
    }

    // MARK: - 获取用户卡片

    func fetchUserCardStats(mid: Int) async throws -> UserCardStats {
        var components = URLComponents(string: "https://api.bilibili.com/x/web-interface/card")
        components?.queryItems = [
            URLQueryItem(name: "mid", value: String(mid))
        ]

        guard let url = components?.url else {
            throw APIError.invalidURL
        }

        let request = makeRequest(url: url)
        let (data, _) = try await URLSession.shared.data(for: request)

        let response = try JSONDecoder().decode(
            UserCardStatsResponse.self,
            from: data
        )

        if response.code != 0 {
            throw APIError.responseError(response.code)
        }

        guard let stats = response.data else {
            throw APIError.requestFailed
        }

        return stats
    }

    // MARK: - 视频详情

    func fetchVideoDetail(bvid: String) async throws -> VideoDetailData {
        var components = URLComponents(
            string: "https://api.bilibili.com/x/web-interface/view"
        )
        components?.queryItems = [
            URLQueryItem(name: "bvid", value: bvid)
        ]

        guard let url = components?.url else {
            throw APIError.invalidURL
        }

        let request = makeRequest(url: url)
        let (data, _) = try await URLSession.shared.data(for: request)

        let response = try JSONDecoder().decode(
            VideoDetailResponse.self,
            from: data
        )

        if response.code != 0 {
            throw APIError.responseError(response.code)
        }

        return response.data
    }

    // MARK: - 视频关系（点赞/点踩/投币/收藏状态）

    func fetchArchiveRelation(bvid: String) async throws -> ArchiveRelationData {
        var components = URLComponents(
            string: "https://api.bilibili.com/x/web-interface/archive/relation"
        )
        components?.queryItems = [
            URLQueryItem(name: "bvid", value: bvid)
        ]

        guard let url = components?.url else {
            throw APIError.invalidURL
        }

        let request = makeRequest(url: url)
        let (data, _) = try await URLSession.shared.data(for: request)

        let response = try JSONDecoder().decode(
            ArchiveRelationResponse.self,
            from: data
        )

        if response.code != 0 {
            throw APIError.responseError(response.code)
        }

        guard let relation = response.data else {
            throw APIError.requestFailed
        }

        return relation
    }

    // MARK: - 视频分P列表

    func fetchVideoPageList(bvid: String) async throws -> [VideoPageListItem] {
        var components = URLComponents(
            string: "https://api.bilibili.com/x/player/pagelist"
        )
        components?.queryItems = [
            URLQueryItem(name: "bvid", value: bvid)
        ]

        guard let url = components?.url else {
            throw APIError.invalidURL
        }

        let request = makeRequest(url: url)
        let (data, _) = try await URLSession.shared.data(for: request)

        let response = try JSONDecoder().decode(
            VideoPageListResponse.self,
            from: data
        )

        if response.code != 0 {
            throw APIError.responseError(response.code)
        }

        return response.data
    }

    // MARK: - 用户关系

    func modifyUserRelation(fid: Int, act: Int) async throws {
        guard act == 1 || act == 2 else {
            throw APIError.requestFailed
        }
        guard let csrf = LoginSession.shared.cookies?.bili_jct, !csrf.isEmpty else {
            throw APIError.responseError(-111)
        }

        let parameters: [String: String] = [
            "fid": String(fid),
            "act": String(act),
            "csrf": csrf
        ]

        guard let request = makePostFormRequest(
            urlString: "https://api.bilibili.com/x/relation/modify",
            parameters: parameters
        ) else {
            throw APIError.invalidURL
        }

        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(SimpleAPIResponse<EmptyCodable>.self, from: data)

        if response.code != 0 {
            throw APIError.businessError(code: response.code, message: response.message)
        }
    }

    // MARK: - 点赞

    func likeVideo(aid: Int, isCancel: Bool) async throws {
        guard let accessKey = LoginSession.shared.accessKey, !accessKey.isEmpty else {
            throw APIError.responseError(-101)
        }

        let params: [String: String] = [
            "access_key": accessKey,
            "aid": String(aid),
            "like": isCancel ? "1" : "0"
        ]

        guard let request = makePostFormRequest(
            urlString: "https://app.bilibili.com/x/v2/view/like",
            parameters: params
        ) else {
            throw APIError.invalidURL
        }

        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(
            SimpleAPIResponse<LikeToastData>.self,
            from: data
        )
        if response.code != 0 {
            throw APIError.responseError(response.code)
        }
    }

    // MARK: - 点踩

    func dislikeVideo(aid: Int, isCancel: Bool) async throws {
        guard let accessKey = LoginSession.shared.accessKey, !accessKey.isEmpty else {
            throw APIError.responseError(-101)
        }

        let params: [String: String] = [
            "access_key": accessKey,
            "aid": String(aid),
            "dislike": isCancel ? "1" : "0"
        ]

        guard let request = makePostFormRequest(
            urlString: "https://app.biliapi.net/x/v2/view/dislike",
            parameters: params
        ) else {
            throw APIError.invalidURL
        }

        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(
            SimpleAPIResponse<EmptyCodable>.self,
            from: data
        )
        if response.code != 0 {
            throw APIError.responseError(response.code)
        }
    }

    // MARK: - 投币

    func coinVideo(aid: Int, multiply: Int) async throws {
        guard let accessKey = LoginSession.shared.accessKey, !accessKey.isEmpty else {
            throw APIError.responseError(-101)
        }

        let params: [String: String] = [
            "access_key": accessKey,
            "aid": String(aid),
            "multiply": String(multiply),
            "select_like": "0"
        ]

        guard let request = makePostFormRequest(
            urlString: "https://app.bilibili.com/x/v2/view/coin/add",
            parameters: params
        ) else {
            throw APIError.invalidURL
        }

        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(
            SimpleAPIResponse<CoinAddData>.self,
            from: data
        )
        if response.code != 0 {
            throw APIError.responseError(response.code)
        }
    }

    // MARK: - 收藏夹列表（含目标是否已收藏）

    func fetchCreatedFavoriteFolders(
        upMid: Int64,
        rid: Int64
    ) async throws -> [FavoriteFolderItem] {
        var components = URLComponents(
            string: "https://api.bilibili.com/x/v3/fav/folder/created/list-all"
        )
        components?.queryItems = [
            URLQueryItem(name: "up_mid", value: String(upMid)),
            URLQueryItem(name: "rid", value: String(rid))
        ]

        guard let url = components?.url else {
            throw APIError.invalidURL
        }

        let request = makeRequest(url: url)
        let (data, _) = try await URLSession.shared.data(for: request)

        let response = try JSONDecoder().decode(
            FavoriteFolderListResponse.self,
            from: data
        )

        if response.code != 0 {
            throw APIError.responseError(response.code)
        }

        return response.data?.list ?? []
    }

    // MARK: - 收藏资源变更

    func dealFavoriteResource(
        rid: Int64,
        addMediaIds: [Int64],
        delMediaIds: [Int64]
    ) async throws {
        guard let accessKey = LoginSession.shared.accessKey, !accessKey.isEmpty else {
            throw APIError.responseError(-101)
        }
        guard let csrf = LoginSession.shared.cookies?.bili_jct, !csrf.isEmpty else {
            throw APIError.responseError(-111)
        }

        var params: [String: String] = [
            "rid": String(rid),
            "type": "2",
            "csrf": csrf
        ]

        if !addMediaIds.isEmpty {
            params["add_media_ids"] = addMediaIds.map(String.init).joined(separator: ",")
        }
        if !delMediaIds.isEmpty {
            params["del_media_ids"] = delMediaIds.map(String.init).joined(separator: ",")
        }

        guard let request = makePostFormRequest(
            urlString: "https://api.bilibili.com/medialist/gateway/coll/resource/deal",
            parameters: params
        ) else {
            throw APIError.invalidURL
        }

        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(
            SimpleAPIResponse<FavoriteDealData>.self,
            from: data
        )
        if response.code != 0 {
            throw APIError.responseError(response.code)
        }
    }

    // MARK: - 稍后再看（最多 100 个）

    func addToWatchLater(bvid: String) async throws {
        guard let sessData = LoginSession.shared.cookies?.SESSDATA, !sessData.isEmpty else {
            throw APIError.responseError(-101)
        }
        guard let csrf = LoginSession.shared.cookies?.bili_jct, !csrf.isEmpty else {
            throw APIError.responseError(-111)
        }

        let params: [String: String] = [
            "bvid": bvid,
            "csrf": csrf
        ]

        guard let request = makePostFormRequest(
            urlString: "https://api.bilibili.com/x/v2/history/toview/add",
            parameters: params
        ) else {
            throw APIError.invalidURL
        }

        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(
            SimpleAPIResponse<EmptyCodable>.self,
            from: data
        )
        if response.code != 0 {
            throw APIError.responseError(response.code)
        }
    }

    func fetchWatchLaterList() async throws -> WatchLaterData {
        guard let url = URL(string: "https://api.bilibili.com/x/v2/history/toview") else {
            throw APIError.invalidURL
        }

        let request = makeRequest(url: url)
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200 ... 299).contains(httpResponse.statusCode)
        else {
            throw APIError.requestFailed
        }

        let decoded = try JSONDecoder().decode(WatchLaterResponse.self, from: data)
        guard decoded.code == 0 else {
            throw APIError.businessError(code: decoded.code, message: decoded.message)
        }
        guard let watchLaterData = decoded.data else {
            throw APIError.requestFailed
        }

        return watchLaterData
    }

    // MARK: - 播放链接

    func fetchPlayUrl(
        bvid: String,
        cid: Int,
        fnval: Int = 4048,
        qn: Int = 127
    ) async throws -> PlayUrlResponse {
        var components = URLComponents(
            string: "https://api.bilibili.com/x/player/wbi/playurl"
        )
        components?.queryItems = [
            URLQueryItem(name: "bvid", value: bvid),
            URLQueryItem(name: "cid", value: String(cid)),
            URLQueryItem(name: "fnval", value: String(fnval)),
            URLQueryItem(name: "fourk", value: "4048"),
            URLQueryItem(name: "qn", value: String(qn))
        ]

        guard let url = components?.url else {
            throw APIError.invalidURL
        }

        let signedURL = try await BiliWbiSigner.shared.sign(url: url)
        let request = makeRequest(url: signedURL)
        let (data, _) = try await URLSession.shared.data(for: request)

        let response = try JSONDecoder().decode(
            PlayUrlResponse.self,
            from: data
        )

        if response.code != 0 {
            throw APIError.responseError(response.code)
        }

        return response
    }

    // MARK: - 播放器信息（含历史记录与在线人数）

    func fetchPlayerWbiV2(
        bvid: String,
        cid: Int
    ) async throws -> PlayerWbiV2Response {
        var components = URLComponents(
            string: "https://api.bilibili.com/x/player/wbi/v2"
        )
        components?.queryItems = [
            URLQueryItem(name: "bvid", value: bvid),
            URLQueryItem(name: "cid", value: String(cid))
        ]

        guard let url = components?.url else {
            throw APIError.invalidURL
        }

        let signedURL = try await BiliWbiSigner.shared.sign(url: url)
        let request = makeRequest(url: signedURL)
        let (data, _) = try await URLSession.shared.data(for: request)

        let response = try JSONDecoder().decode(
            PlayerWbiV2Response.self,
            from: data
        )

        if response.code != 0 {
            throw APIError.responseError(response.code)
        }

        return response
    }

    // MARK: - 视频快照预览

    func fetchVideoShotPreview(
        bvid: String,
        cid: Int
    ) async throws -> VideoShotPreviewMetadata {
        var components = URLComponents(
            string: "https://api.bilibili.com/x/player/videoshot"
        )
        components?.queryItems = [
            URLQueryItem(name: "bvid", value: bvid),
            URLQueryItem(name: "cid", value: String(cid)),
            URLQueryItem(name: "index", value: "0")
        ]

        guard let url = components?.url else {
            throw APIError.invalidURL
        }

        let request = makeRequest(url: url)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200 ... 299).contains(httpResponse.statusCode)
        else {
            throw APIError.requestFailed
        }

        let decoded = try JSONDecoder().decode(VideoShotPreviewResponse.self, from: data)
        guard decoded.code == 0, let payload = decoded.data else {
            throw APIError.businessError(code: decoded.code, message: decoded.message)
        }

        let spriteSheetURLs = payload.image.compactMap(normalizeBilibiliURL(_:))
        guard !spriteSheetURLs.isEmpty else {
            throw APIError.requestFailed
        }

        let timestamps = try await fetchVideoShotTimestamps(from: payload.pvdata)
        return VideoShotPreviewMetadata(
            spriteSheetURLs: spriteSheetURLs,
            timestamps: timestamps,
            columns: max(1, payload.imgXLen),
            rows: max(1, payload.imgYLen),
            tileWidth: max(1, payload.imgXSize),
            tileHeight: max(1, payload.imgYSize)
        )
    }

    private func fetchVideoShotTimestamps(from rawURL: String) async throws -> [TimeInterval] {
        guard let url = normalizeBilibiliURL(rawURL) else {
            throw APIError.invalidURL
        }

        let request = makeRequest(url: url)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200 ... 299).contains(httpResponse.statusCode)
        else {
            throw APIError.requestFailed
        }

        return decodeVideoShotTimestamps(from: data)
    }

    private func normalizeBilibiliURL(_ rawURL: String) -> URL? {
        let trimmed = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.hasPrefix("//") {
            return URL(string: "https:" + trimmed)
        }

        if trimmed.hasPrefix("http://") {
            return URL(string: "https://" + trimmed.dropFirst("http://".count))
        }

        if trimmed.hasPrefix("https://") {
            return URL(string: trimmed)
        }

        return URL(string: "https://" + trimmed)
    }

    private func decodeVideoShotTimestamps(from data: Data) -> [TimeInterval] {
        guard data.count >= 2 else { return [] }

        var result: [TimeInterval] = []
        result.reserveCapacity(data.count / 2)

        var offset = 0
        while offset + 1 < data.count {
            let high = UInt16(data[offset]) << 8
            let low = UInt16(data[offset + 1])
            result.append(TimeInterval(high | low))
            offset += 2
        }

        return result
    }

    // MARK: - 上报播放记录

    func reportHistory(
        aid: Int,
        cid: Int,
        progress: Int
    ) async throws {
        var components = URLComponents(
            string: "https://api.bilibili.com/x/v2/history/report"
        )
        components?.queryItems = [
            URLQueryItem(name: "aid", value: String(aid)),
            URLQueryItem(name: "cid", value: String(cid)),
            URLQueryItem(name: "progress", value: String(progress)),
            URLQueryItem(name: "platform", value: "web"),
            URLQueryItem(name: "csrf", value: LoginSession.shared.cookies?.bili_jct ?? "")
        ]

        guard let url = components?.url else {
            throw APIError.invalidURL
        }

        var request = makeRequest(url: url)
        request.httpMethod = "POST"

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200 ... 299).contains(httpResponse.statusCode)
        else {
            throw APIError.requestFailed
        }
    }

    // MARK: - 获取视频弹幕分包（protobuf）

    func fetchDanmakuSegment(
        cid: Int,
        segmentIndex: Int = 1
    ) async throws -> Bilibili_Community_Service_Dm_V1_DmSegMobileReply {
        var components = URLComponents(
            string: "https://api.bilibili.com/x/v2/dm/web/seg.so"
        )
        components?.queryItems = [
            URLQueryItem(name: "type", value: "1"),
            URLQueryItem(name: "oid", value: String(cid)),
            URLQueryItem(name: "segment_index", value: String(segmentIndex))
        ]

        guard let url = components?.url else {
            throw APIError.invalidURL
        }

        var request = makeRequest(url: url)
        request.setValue("https://www.bilibili.com", forHTTPHeaderField: "Referer")
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 18_2 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.2 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200 ... 299).contains(httpResponse.statusCode)
        else {
            throw APIError.requestFailed
        }

        return try Bilibili_Community_Service_Dm_V1_DmSegMobileReply(serializedBytes: data)
    }

    // MARK: - sign 创建

    private func generateSign(for parameters: [String: String]) -> String {
        var validParams = parameters
        validParams.removeValue(forKey: "sign")
        let sortedKeys = validParams.keys.sorted()
        // key / value 都走 RFC3986 编码，签名串按字典序拼接
        let paramString = sortedKeys.map { key in
            let value = validParams[key] ?? ""
            let encodedKey = key.biliUrlEncoded()
            let encodedValue = value.biliUrlEncoded()
            return encodedValue.isEmpty ? encodedKey : "\(encodedKey)=\(encodedValue)"
        }.joined(separator: "&")
        let digest = Insecure.MD5.hash(data: (paramString + BiliAPI.appSecret).data(using: .utf8) ?? Data())
        return digest.map { String(format: "%02hhx", $0) }.joined()
    }

    // MARK: - 请求体顺序：其他 key 按字典序，最后固定 appkey、ts、sign

    private func makeOrderedBodyString(from parameters: [String: String]) -> String {
        let tailKeys = ["access_key", "appkey", "ts", "sign"]
        let sortedOtherKeys = parameters.keys
            .filter { !tailKeys.contains($0) }
            .sorted()

        let orderedKeys = sortedOtherKeys + tailKeys.filter { parameters[$0] != nil }

        return orderedKeys.map { key in
            let value = parameters[key] ?? ""
            let encodedKey = key.biliUrlEncoded()
            let encodedValue = value.biliUrlEncoded()
            return encodedValue.isEmpty ? encodedKey : "\(encodedKey)=\(encodedValue)"
        }.joined(separator: "&")
    }
}

// MARK: - 错误处理

enum APIError: LocalizedError {
    case invalidURL
    case responseError(Int)
    case businessError(code: Int, message: String?)
    case noVideoOrAudio
    case requestFailed
    case grpcError(status: String, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "无效的 URL"
        case let .responseError(code):
            return "API 错误: \(code)"
        case let .businessError(code, message):
            if let message, !message.isEmpty {
                return message
            }
            return "API 错误: \(code)"
        case .noVideoOrAudio:
            return "未找到视频或音频流"
        case .requestFailed:
            return "请求失败"
        case let .grpcError(status, message):
            return "gRPC 错误: status=\(status), message=\(message)"
        }
    }
}

struct NavResponse: Codable {
    let data: UserCard
}

struct MyStatResponse: Codable {
    let data: MyStat
}

struct MyStat: Codable {
    let following: Int
    let follower: Int
    let dynamicCount: Int

    enum CodingKeys: String, CodingKey {
        case following
        case follower
        case dynamicCount = "dynamic_count"
    }
}

private struct LiveRecommendWatchedShow: Codable {
    let textLarge: String?

    enum CodingKeys: String, CodingKey {
        case textLarge = "text_large"
    }
}

struct LivePlaybackInfo {
    let roomID: String
    let streamURL: URL
    let aspectRatio: CGFloat
    let currentQn: Int
    let qualityOptions: [VideoQualityOption]
}

struct LiveRoomInfo {
    let roomID: String
    let uid: Int
    let title: String
    let coverURL: String
    let backgroundURL: String?
    let onlineCount: String
    let anchorName: String
    let faceURL: String
    let areaName: String
}

struct LiveHomeFeedPayload {
    let followingItems: [LiveFollowingItem]
    let areaTabs: [LiveAreaTab]
    let rooms: [LiveCardModel]
}

private struct LiveIndexFeedResponse: Codable {
    let code: Int
    let message: String
    let data: LiveIndexFeedData?
}

private struct LiveIndexFeedData: Codable {
    let cardList: [LiveIndexCard]

    enum CodingKeys: String, CodingKey {
        case cardList = "card_list"
    }
}

private struct LiveIndexCard: Codable {
    let cardType: String
    let cardData: LiveIndexCardData

    enum CodingKeys: String, CodingKey {
        case cardType = "card_type"
        case cardData = "card_data"
    }
}

private struct LiveIndexCardData: Codable {
    let myIdol: LiveMyIdolContainer?
    let areaEntrance: LiveAreaEntranceContainer?
    let smallCard: LiveSmallCard?

    enum CodingKeys: String, CodingKey {
        case myIdol = "my_idol_v1"
        case areaEntrance = "area_entrance_v3"
        case smallCard = "small_card_v1"
    }
}

private struct LiveMyIdolContainer: Codable {
    let list: [LiveMyIdolRoom]
}

private struct LiveMyIdolRoom: Codable {
    let uid: Int
    let uname: String
    let roomid: Int
    let face: String
    let link: String?
}

private struct LiveAreaEntranceContainer: Codable {
    let list: [LiveAreaEntranceTab]
}

private struct LiveAreaEntranceTab: Codable {
    let id: Int
    let title: String
}

private struct LiveSmallCard: Codable {
    let isAd: Bool?
    let uid: Int
    let id: Int
    let uname: String
    let face: String
    let title: String
    let cover: String
    let online: Int
    let link: String?
    let parentAreaName: String?
    let areaName: String?
    let watchedShow: LiveRecommendWatchedShow?
    let feedTag: LiveSmallCardFeedTag?

    enum CodingKeys: String, CodingKey {
        case isAd = "is_ad"
        case uid
        case id
        case uname
        case face
        case title
        case cover
        case online
        case link
        case parentAreaName = "parent_area_name"
        case areaName = "area_name"
        case watchedShow = "watched_show"
        case feedTag = "feed_tag"
    }
}

private struct LiveSmallCardFeedTag: Codable {
    let tagText: String?

    enum CodingKeys: String, CodingKey {
        case tagText = "tag_text"
    }
}

private struct LiveRoomPlayInfoResponse: Codable {
    let code: Int
    let message: String
    let data: LiveRoomPlayInfoData?
}

private struct LiveRoomPlayInfoData: Codable {
    let roomID: Int
    let isPortrait: Bool
    let playurlInfo: LiveRoomPlayurlInfo

    enum CodingKeys: String, CodingKey {
        case roomID = "room_id"
        case isPortrait = "is_portrait"
        case playurlInfo = "playurl_info"
    }
}

private struct LiveRoomPlayurlInfo: Codable {
    let playurl: LiveRoomPlayurl
}

private struct LiveRoomPlayurl: Codable {
    let gQnDesc: [LiveRoomQuality]
    let stream: [LiveRoomStream]

    enum CodingKeys: String, CodingKey {
        case gQnDesc = "g_qn_desc"
        case stream
    }
}

private struct LiveRoomQuality: Codable {
    let qn: Int
    let desc: String
}

private struct LiveRoomStream: Codable {
    let protocolName: String
    let format: [LiveRoomFormat]

    enum CodingKeys: String, CodingKey {
        case protocolName = "protocol_name"
        case format
    }
}

private struct LiveRoomFormat: Codable {
    let formatName: String
    let codec: [LiveRoomCodec]

    enum CodingKeys: String, CodingKey {
        case formatName = "format_name"
        case codec
    }
}

private struct LiveRoomCodec: Codable {
    let codecName: String
    let currentQn: Int
    let acceptQn: [Int]
    let baseURL: String
    let urlInfo: [LiveRoomURLInfo]

    enum CodingKeys: String, CodingKey {
        case codecName = "codec_name"
        case currentQn = "current_qn"
        case acceptQn = "accept_qn"
        case baseURL = "base_url"
        case urlInfo = "url_info"
    }
}

private struct LiveRoomURLInfo: Codable {
    let host: String
    let extra: String
}

private struct LiveDanmakuInfoResponse: Codable {
    let code: Int
    let message: String
    let data: LiveDanmakuInfoData?
}

private struct LiveDanmakuHistoryResponse: Codable {
    let code: Int
    let message: String
    let data: LiveDanmakuHistoryData?
}

private struct LiveRoomInfoResponse: Codable {
    let code: Int
    let message: String
    let data: LiveRoomInfoData?
}

private struct LiveRoomInfoData: Codable {
    let roomInfo: LiveRoomInfoRoom
    let anchorInfo: LiveRoomInfoAnchor
    let watchedShow: LiveRoomInfoWatchedShow?

    enum CodingKeys: String, CodingKey {
        case roomInfo = "room_info"
        case anchorInfo = "anchor_info"
        case watchedShow = "watched_show"
    }
}

private struct LiveRoomInfoRoom: Codable {
    let roomID: Int
    let title: String
    let cover: String
    let online: Int
    let areaName: String
    let parentAreaName: String
    let appBackground: String

    enum CodingKeys: String, CodingKey {
        case roomID = "room_id"
        case title
        case cover
        case online
        case areaName = "area_name"
        case parentAreaName = "parent_area_name"
        case appBackground = "app_background"
    }
}

private struct LiveRoomInfoAnchor: Codable {
    let baseInfo: LiveRoomInfoAnchorBase

    enum CodingKeys: String, CodingKey {
        case baseInfo = "base_info"
    }
}

private struct LiveRoomInfoAnchorBase: Codable {
    let uid: Int
    let uname: String
    let face: String
}

private struct LiveRoomInfoWatchedShow: Codable {
    let textLarge: String

    enum CodingKeys: String, CodingKey {
        case textLarge = "text_large"
    }
}

private struct LiveDanmakuInfoData: Codable {
    let token: String
    let hostList: [LiveDanmakuHostItem]

    enum CodingKeys: String, CodingKey {
        case token
        case hostList = "host_list"
    }
}

private struct LiveDanmakuHistoryData: Codable {
    let admin: [LiveDanmakuHistoryItem]
    let room: [LiveDanmakuHistoryItem]
}

private struct LiveDanmakuHistoryItem: Codable {
    let text: String
    let nickname: String
    let timeline: String
    let emots: [String: LiveDanmakuHistoryEmoticon]?
}

private struct LiveDanmakuHistoryEmoticon: Codable {
    let descript: String?
    let emoji: String?
    let url: String?
    let width: Int?
    let height: Int?
}

private struct LiveDanmakuHostItem: Codable {
    let host: String
    let wssPort: Int

    enum CodingKeys: String, CodingKey {
        case host
        case wssPort = "wss_port"
    }
}

private func buildLiveStreamURL(host: String, baseURL: String, extra: String, qn: Int) -> URL? {
    let normalizedHost = host.hasSuffix("/") ? String(host.dropLast()) : host
    let normalizedBase = baseURL.hasPrefix("/") ? baseURL : "/" + baseURL
    let urlString = normalizedHost + normalizedBase

    guard var components = URLComponents(string: urlString) else {
        return nil
    }

    let rawExtra = extra.hasPrefix("?") ? String(extra.dropFirst()) : extra
    components.percentEncodedQuery = rawExtra
    var queryItems = components.queryItems ?? []
    queryItems.removeAll { $0.name == "qn" }
    queryItems.append(URLQueryItem(name: "qn", value: String(qn)))
    components.queryItems = queryItems
    return components.url
}

private func mapLiveSmallCard(_ room: LiveSmallCard) -> LiveCardModel {
    let areaParts = [room.parentAreaName, room.areaName]
        .compactMap { value -> String? in
            guard let value, !value.isEmpty else { return nil }
            return value
        }
    let areaName = Array(NSOrderedSet(array: areaParts)).compactMap { $0 as? String }.joined(separator: " · ")

    return LiveCardModel(
        roomId: String(room.id),
        uid: room.uid,
        title: room.title,
        coverURL: room.cover.replacingOccurrences(of: "http://", with: "https://"),
        onlineCount: room.watchedShow?.textLarge ?? "\(VideoItem.formatCount(room.online))人气",
        anchorName: room.uname,
        faceURL: room.face.replacingOccurrences(of: "http://", with: "https://"),
        areaName: areaName,
        badgeText: room.feedTag?.tagText,
        link: room.link
    )
}

private struct EmptyCodable: Codable {}

struct VideoShotPreviewMetadata: Equatable {
    let spriteSheetURLs: [URL]
    let timestamps: [TimeInterval]
    let columns: Int
    let rows: Int
    let tileWidth: Int
    let tileHeight: Int

    private var maxFrameCount: Int {
        max(0, spriteSheetURLs.count * columns * rows)
    }

    func frame(at time: TimeInterval) -> VideoShotFrame? {
        guard maxFrameCount > 0 else { return nil }

        let frameIndex = resolvedFrameIndex(for: time)
        let clampedIndex = min(max(0, frameIndex), maxFrameCount - 1)
        let tilesPerSheet = max(1, columns * rows)
        let sheetIndex = min(clampedIndex / tilesPerSheet, spriteSheetURLs.count - 1)
        let cellIndex = clampedIndex % tilesPerSheet

        return VideoShotFrame(
            sheetURL: spriteSheetURLs[sheetIndex],
            column: cellIndex % columns,
            row: cellIndex / columns,
            columns: columns,
            rows: rows,
            tileWidth: tileWidth,
            tileHeight: tileHeight,
            timestamp: timestamps.isEmpty ? nil : timestamps[min(clampedIndex, timestamps.count - 1)]
        )
    }

    private func resolvedFrameIndex(for time: TimeInterval) -> Int {
        if timestamps.isEmpty {
            return 0
        }

        let clampedTime = max(0, time)
        var low = 0
        var high = timestamps.count - 1
        var answer = 0

        while low <= high {
            let mid = (low + high) / 2
            if timestamps[mid] <= clampedTime {
                answer = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }

        return answer
    }
}

struct VideoShotFrame: Equatable {
    let sheetURL: URL
    let column: Int
    let row: Int
    let columns: Int
    let rows: Int
    let tileWidth: Int
    let tileHeight: Int
    let timestamp: TimeInterval?
}

private struct VideoShotPreviewResponse: Codable {
    let code: Int
    let message: String
    let ttl: Int?
    let data: VideoShotPreviewPayload?
}

private struct VideoShotPreviewPayload: Codable {
    let pvdata: String
    let imgXLen: Int
    let imgYLen: Int
    let imgXSize: Int
    let imgYSize: Int
    let image: [String]

    enum CodingKeys: String, CodingKey {
        case pvdata
        case imgXLen = "img_x_len"
        case imgYLen = "img_y_len"
        case imgXSize = "img_x_size"
        case imgYSize = "img_y_size"
        case image
    }
}
