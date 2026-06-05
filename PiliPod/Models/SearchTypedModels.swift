import Foundation

struct SearchTypedVideoResponse: Decodable {
    let code: Int
    let message: String?
    let ttl: Int?
    let data: SearchTypedVideoData?
}

struct SearchTypedVideoData: Decodable {
    let page: Int
    let numPages: Int
    let result: [SearchComprehensiveVideo]

    enum CodingKeys: String, CodingKey {
        case page
        case numPages
        case result
    }
}

struct SearchTypedUserResponse: Decodable {
    let code: Int
    let message: String?
    let ttl: Int?
    let data: SearchTypedUserData?
}

struct SearchTypedUserData: Decodable {
    let page: Int
    let numPages: Int
    let result: [SearchComprehensiveUser]

    enum CodingKeys: String, CodingKey {
        case page
        case numPages
        case result
    }
}
