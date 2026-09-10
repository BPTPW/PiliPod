//
//  PrivateMessageSession.swift
//  PiliPod
//

import Foundation

struct PrivateMessageSession: Identifiable, Hashable, Sendable {
    let talkerID: UInt64
    let sessionType: UInt32
    let name: String
    let avatarURL: String
    let lastMessageContent: String
    let lastMessageType: Int
    let lastMessageTimestamp: UInt64
    let unreadCount: UInt32

    var id: String { "\(sessionType)-\(talkerID)" }

    var messagePreview: String {
        let prefix: String
        switch lastMessageType {
        case 2, 13:
            prefix = "[图片]"
        case 3:
            prefix = "[语音]"
        case 4, 7, 14:
            prefix = "[分享]"
        case 6:
            prefix = "[表情]"
        case 9:
            prefix = "[小程序]"
        case 11:
            prefix = "[视频]"
        case 12:
            prefix = "[专栏]"
        default:
            prefix = ""
        }

        let content = Self.previewContent(
            from: lastMessageContent,
            messageType: lastMessageType
        )
        if prefix.isEmpty {
            return content.isEmpty ? "暂无消息" : content
        }
        return content.isEmpty ? prefix : "\(prefix) \(content)"
    }

    private static func previewContent(from rawContent: String, messageType: Int) -> String {
        let fallback = rawContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = fallback.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let content = object as? [String: Any]
        else {
            return fallback
        }

        if messageType == 18,
           let nested = content["content"] as? String,
           let nestedData = nested.data(using: .utf8),
           let parts = try? JSONSerialization.jsonObject(with: nestedData) as? [[String: Any]]
        {
            return parts.compactMap { $0["text"] as? String }.joined(separator: " ")
        }

        let keys: [String]
        switch messageType {
        case 1:
            keys = ["content", "text"]
        case 7:
            keys = ["title", "headline", "content"]
        case 10:
            keys = ["title", "text", "content"]
        case 11, 12, 14:
            keys = ["title", "summary", "headline", "desc", "content"]
        case 13:
            keys = ["title", "text", "content"]
        default:
            keys = ["title", "text", "content", "summary", "headline", "desc"]
        }

        for key in keys {
            if let value = content[key] as? String,
               !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            {
                return value.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return fallback
    }

    init(session: Bilibili_Im_Type_SessionInfo) {
        let isGroup = session.groupType != 0 || !session.groupName.isEmpty
        talkerID = session.talkerID
        sessionType = session.sessionType
        name = session.accountInfo.name.isEmpty
            ? (session.groupName.isEmpty ? "未知会话" : session.groupName)
            : session.accountInfo.name
        avatarURL = session.accountInfo.picURL.isEmpty && isGroup
            ? session.groupCover
            : session.accountInfo.picURL
        lastMessageContent = session.lastMsg.content
        lastMessageType = session.lastMsg.msgType.rawValue
        lastMessageTimestamp = session.lastMsg.timestamp == 0
            ? session.sessionTs
            : session.lastMsg.timestamp
        unreadCount = session.unreadCount
    }

    init(restSession: PrivateMessageRESTSession, name: String?, avatarURL: String?) {
        talkerID = restSession.talkerID
        sessionType = restSession.sessionType
        self.name = name?.isEmpty == false
            ? name!
            : (restSession.accountInfo?.name.isEmpty == false
                ? restSession.accountInfo!.name
                : (restSession.groupName.isEmpty ? "未知会话" : restSession.groupName))
        self.avatarURL = avatarURL?.isEmpty == false
            ? avatarURL!
            : (restSession.accountInfo?.picURL.isEmpty == false
                ? restSession.accountInfo!.picURL
                : restSession.groupCover)
        lastMessageContent = restSession.lastMsg?.content ?? ""
        lastMessageType = restSession.lastMsg?.msgType ?? 0
        lastMessageTimestamp = restSession.lastMsg?.timestamp ?? restSession.sessionTimestamp / 1_000_000
        unreadCount = restSession.unreadCount
    }
}

struct PrivateMessageRESTSession: Decodable, Sendable {
    let talkerID: UInt64
    let sessionType: UInt32
    let groupName: String
    let groupCover: String
    let sessionTimestamp: UInt64
    let unreadCount: UInt32
    let lastMsg: PrivateMessageRESTMessage?
    let accountInfo: PrivateMessageRESTAccountInfo?

    enum CodingKeys: String, CodingKey {
        case talkerID = "talker_id"
        case sessionType = "session_type"
        case groupName = "group_name"
        case groupCover = "group_cover"
        case sessionTimestamp = "session_ts"
        case unreadCount = "unread_count"
        case lastMsg = "last_msg"
        case accountInfo = "account_info"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        talkerID = try container.decode(UInt64.self, forKey: .talkerID)
        sessionType = try container.decode(UInt32.self, forKey: .sessionType)
        groupName = try container.decodeIfPresent(String.self, forKey: .groupName) ?? ""
        groupCover = try container.decodeIfPresent(String.self, forKey: .groupCover) ?? ""
        sessionTimestamp = try container.decodeIfPresent(UInt64.self, forKey: .sessionTimestamp) ?? 0
        unreadCount = try container.decodeIfPresent(UInt32.self, forKey: .unreadCount) ?? 0
        lastMsg = try container.decodeIfPresent(PrivateMessageRESTMessage.self, forKey: .lastMsg)
        accountInfo = try container.decodeIfPresent(PrivateMessageRESTAccountInfo.self, forKey: .accountInfo)
    }
}

struct PrivateMessageRESTAccountInfo: Decodable, Sendable {
    let name: String
    let picURL: String

    enum CodingKeys: String, CodingKey {
        case name
        case picURL = "pic_url"
    }
}

struct PrivateMessageRESTMessage: Decodable, Sendable {
    let msgType: Int
    let content: String
    let timestamp: UInt64

    enum CodingKeys: String, CodingKey {
        case msgType = "msg_type"
        case content
        case timestamp
    }
}

struct PrivateMessageRESTMessagesData: Decodable, Sendable {
    let messages: [PrivateMessageRESTDetailMessage]

    enum CodingKeys: String, CodingKey {
        case messages
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        messages = try container.decodeIfPresent([PrivateMessageRESTDetailMessage].self, forKey: .messages) ?? []
    }
}

struct PrivateMessageRESTDetailMessage: Decodable, Sendable {
    let senderUID: UInt64
    let receiverType: Int
    let receiverID: UInt64
    let messageType: Int
    let content: String
    let sequenceNumber: UInt64
    let timestamp: UInt64
    let messageKey: UInt64
    let status: UInt32
    let isSystemCancelled: Bool

    enum CodingKeys: String, CodingKey {
        case senderUID = "sender_uid"
        case receiverType = "receiver_type"
        case receiverID = "receiver_id"
        case messageType = "msg_type"
        case content
        case sequenceNumber = "msg_seqno"
        case timestamp
        case messageKey = "msg_key"
        case status = "msg_status"
        case isSystemCancelled = "sys_cancel"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        senderUID = try container.decode(UInt64.self, forKey: .senderUID)
        receiverType = try container.decodeIfPresent(Int.self, forKey: .receiverType) ?? 1
        receiverID = try container.decodeIfPresent(UInt64.self, forKey: .receiverID) ?? 0
        messageType = try container.decode(Int.self, forKey: .messageType)
        content = try container.decodeIfPresent(String.self, forKey: .content) ?? ""
        sequenceNumber = try container.decodeIfPresent(UInt64.self, forKey: .sequenceNumber) ?? 0
        timestamp = try container.decodeIfPresent(UInt64.self, forKey: .timestamp) ?? 0
        messageKey = try container.decodeIfPresent(UInt64.self, forKey: .messageKey) ?? 0
        status = try container.decodeIfPresent(UInt32.self, forKey: .status) ?? 0
        isSystemCancelled = try container.decodeIfPresent(Bool.self, forKey: .isSystemCancelled) ?? false
    }

    var protobufMessage: Bilibili_Im_Type_Msg {
        var message = Bilibili_Im_Type_Msg()
        message.senderUid = senderUID
        message.receiverID = receiverID
        message.receiverType = Bilibili_Im_Type_RecverType(rawValue: receiverType)
            ?? .enRecverTypePeer
        message.msgType = Bilibili_Im_Type_MsgType(rawValue: messageType)
            ?? .enInvalidMsgType
        message.content = content
        message.msgSeqno = sequenceNumber
        message.timestamp = timestamp
        message.msgKey = messageKey
        message.msgStatus = status
        message.sysCancel = isSystemCancelled
        return message
    }
}

struct PrivateMessageRESTSessionsData: Decodable, Sendable {
    let sessionList: [PrivateMessageRESTSession]

    enum CodingKeys: String, CodingKey {
        case sessionList = "session_list"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sessionList = try container.decodeIfPresent([PrivateMessageRESTSession].self, forKey: .sessionList) ?? []
    }
}

struct PrivateMessageUserCard: Decodable, Sendable {
    let mid: UInt64
    let name: String
    let face: String

    enum CodingKeys: String, CodingKey {
        case mid
        case name
        case face
    }
}
