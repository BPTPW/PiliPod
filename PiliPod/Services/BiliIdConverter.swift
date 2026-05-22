//
//  BiliIdConverter.swift
//  PiliPod
//
//  Created by co on 2026/5/22.
//

import Foundation

final class BiliIdConverter {
    private static let xorCode: Int64 = 23_442_827_791_579
    private static let maskCode: Int64 = 2_251_799_813_685_247
    private static let maxAid: Int64 = 1 << 51
    private static let base: Int64 = 58
    private static let prefix = "BV1"
    private static let alphabet = Array("FcwAPNKTMug3GV5Lj7EJnHpWsx4tb8haYeviqBz6rkCy12mUSDQX9RdoZf".utf8)
    private static let decodeMap: [UInt8: Int64] = Dictionary(
        uniqueKeysWithValues: alphabet.enumerated().map { ($0.element, Int64($0.offset)) }
    )

    static func av2bv(aid: Int64) -> String {
        guard aid >= 0, aid <= maskCode else {
            return ""
        }

        var bytes = Array("BV1000000000".utf8)
        var bvIndex = bytes.count - 1
        var temp = (maxAid | aid) ^ xorCode

        while temp > 0, bvIndex >= prefix.count {
            bytes[bvIndex] = alphabet[Int(temp % base)]
            temp /= base
            bvIndex -= 1
        }

        bytes.swapAt(3, 9)
        bytes.swapAt(4, 7)

        return String(decoding: bytes, as: UTF8.self)
    }

    static func bv2av(bvid: String) -> String {
        guard bvid.hasPrefix(prefix), bvid.utf8.count == 12 else {
            return ""
        }

        var bytes = Array(bvid.utf8)
        bytes.swapAt(3, 9)
        bytes.swapAt(4, 7)

        var temp: Int64 = 0
        for byte in bytes.dropFirst(prefix.count) {
            guard let index = decodeMap[byte] else {
                return ""
            }
            temp = temp * base + index
        }

        return String((temp & maskCode) ^ xorCode)
    }
}
