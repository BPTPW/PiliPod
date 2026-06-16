import Foundation

struct SearchSuggestResponse: Decodable {
    let code: Int
    let result: SearchSuggestResult?
}

struct SearchSuggestResult: Decodable {
    let tag: [SearchSuggestItem]
}

struct SearchSuggestItem: Decodable, Identifiable, Hashable {
    let value: String
    let ref: Int?
    let name: String
    let spid: Int?
    let type: String?

    var id: String { value }
}
