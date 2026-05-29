//
//  BiliAPI.swift
//  PiliPod
//
//  Created by co on 2026/5/21.
//

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
        guard let url = URL(string: "https://grpc.biliapi.net/bilibili.main.community.reply.v1.Reply/MainList") else {
            throw APIError.invalidURL
        }

        var reqMessage = Bilibili_Main_Community_Reply_V1_MainListReq()
        reqMessage.oid = aid
        reqMessage.type = 1
        reqMessage.cursor = .init()
        reqMessage.cursor.next = next
        reqMessage.cursor.mode = mode

        let messageBytes = try reqMessage.serializedData()
        var grpcBody = Data([0x00])
        var length = UInt32(messageBytes.count).bigEndian
        withUnsafeBytes(of: &length) { bytes in
            grpcBody.append(contentsOf: bytes)
        }
        grpcBody.append(messageBytes)

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
            let payloadLength = lenData.reduce(UInt32(0)) { (acc, byte) in
                (acc << 8) | UInt32(byte)
            }
            idx += 5

            let end = idx + Int(payloadLength)
            guard end <= data.count else { break }

            let payload = data[idx..<end]
            idx = end

            if flag & 0x80 == 0 {
                return try Bilibili_Main_Community_Reply_V1_MainListReply(serializedBytes: payload)
            }

            if flag & 0x80 != 0,
               let trailerText = String(data: payload, encoding: .utf8) {
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
        var params: [String: String] = [
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
                    title: title,
                    coverURL: cover,
                    onlineCount: online,
                    anchorName: anchorName
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

    // MARK: -获取用户卡片
    
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

        let request = makeRequest(url: url)
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

        let request = makeRequest(url: url)
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
    
    // sign 创建
    
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

        // 请求体顺序：其他 key 按字典序，最后固定 appkey、ts、sign
        private func makeOrderedBodyString(from parameters: [String: String]) -> String {
            let tailKeys = ["appkey", "ts", "sign"]
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
        case .responseError(let code):
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

private struct EmptyCodable: Codable {}
