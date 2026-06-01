//
//  CommentPostModels.swift
//  PiliPod
//
//  Created by Codex on 2026/6/1.
//

import Foundation

struct CommentImageUploadData: Codable {
    let imageURL: String
    let imageWidth: Int
    let imageHeight: Int
    let imgSize: Int

    enum CodingKeys: String, CodingKey {
        case imageURL = "image_url"
        case imageWidth = "image_width"
        case imageHeight = "image_height"
        case imgSize = "img_size"
    }
}

struct CommentPictureUploadPayload: Codable {
    let imgSrc: String
    let imgWidth: Int
    let imgHeight: Int
    let imgSize: Int

    enum CodingKeys: String, CodingKey {
        case imgSrc = "img_src"
        case imgWidth = "img_width"
        case imgHeight = "img_height"
        case imgSize = "img_size"
    }
}

struct CommentAddResponseData: Codable {
    let successAction: Int?
    let successToast: String?
    let needCaptcha: Bool?
    let url: String?
    let rpid: Int64?
    let root: Int64?
    let parent: Int64?

    enum CodingKeys: String, CodingKey {
        case successAction = "success_action"
        case successToast = "success_toast"
        case needCaptcha = "need_captcha"
        case url
        case rpid
        case root
        case parent
    }
}
