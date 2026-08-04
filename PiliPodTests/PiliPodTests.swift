//
//  PiliPodTests.swift
//  PiliPodTests
//
//  Created by co on 2026/5/21.
//

import Testing

struct PiliPodTests {

    @Test func manualCDNRewritePreservesMediaPathAndSignature() throws {
        let source = try #require(URL(string: "https://upos-sz-mirrorcos.bilivideo.com/upgcxcode/12/34/56/video.m4s?deadline=123&sign=abc%2Fdef"))

        let rewritten = try #require(
            PlaybackCDNPlanner.safelyRewritingHost(
                of: source,
                to: "upos-sz-mirrorali.bilivideo.com"
            )
        )

        #expect(rewritten.scheme == "https")
        #expect(rewritten.host == "upos-sz-mirrorali.bilivideo.com")
        #expect(rewritten.path == "/upgcxcode/12/34/56/video.m4s")
        #expect(rewritten.query == "deadline=123&sign=abc%2Fdef")
    }

    @Test func nonMediaURLsAreNeverRewritten() throws {
        let apiURL = try #require(URL(string: "https://api.bilibili.com/x/player/wbi/playurl?cid=1"))
        let imageURL = try #require(URL(string: "https://i0.hdslb.com/bfs/archive/cover.jpg"))

        #expect(PlaybackCDNPlanner.safelyRewritingHost(of: apiURL, to: "upos-sz-mirrorali.bilivideo.com") == nil)
        #expect(PlaybackCDNPlanner.safelyRewritingHost(of: imageURL, to: "upos-sz-mirrorali.bilivideo.com") == nil)
    }

    @Test func manualRouteKeepsOriginalURLsAsFallbacks() throws {
        let primary = try #require(URL(string: "https://upos-sz-mirrorcos.bilivideo.com/upgcxcode/12/34/56/video.m4s?sign=primary"))
        let backup = try #require(URL(string: "https://upos-sz-mirrorhw.bilivideo.com/upgcxcode/12/34/56/video.m4s?sign=backup"))

        let candidates = PlaybackCDNPlanner.candidates(primary: primary, backups: [backup], route: .ali)

        #expect(candidates.count == 3)
        #expect(candidates[0].host == "upos-sz-mirrorali.bilivideo.com")
        #expect(candidates[1] == primary)
        #expect(candidates[2] == backup)
    }

    @Test func wbiMixinKeyMatchesDocumentExample() {
        let mixinKey = BiliWbiSignature.makeMixinKey(
            imgKey: "7cd084941338484aae1ad9425b84077c",
            subKey: "4932caff0ff746eab6f01bf08b70ac45"
        )

        #expect(mixinKey == "ea1db124af3c7062474693fa704f4ff8")
    }

    @Test func wbiSigningMatchesDocumentExample() {
        let signedItems = BiliWbiSignature.sign(
            queryItems: [
                URLQueryItem(name: "foo", value: "114"),
                URLQueryItem(name: "bar", value: "514"),
                URLQueryItem(name: "zab", value: "1919810"),
            ],
            imgKey: "7cd084941338484aae1ad9425b84077c",
            subKey: "4932caff0ff746eab6f01bf08b70ac45",
            timestamp: 1702204169
        )

        let signedValues = Dictionary(uniqueKeysWithValues: signedItems.map { ($0.name, $0.value ?? "") })
        #expect(signedValues["w_rid"] == "8f6f2b5b3d485fe1886cec6a0be8c5d4")
        #expect(signedValues["wts"] == "1702204169")
    }

}
