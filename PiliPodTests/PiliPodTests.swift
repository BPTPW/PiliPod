//
//  PiliPodTests.swift
//  PiliPodTests
//
//  Created by co on 2026/5/21.
//

import Testing

struct PiliPodTests {

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
