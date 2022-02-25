//
//  SearchBoxDelegate.swift
//  SearchBox
//
//  Created by Doug Stein on 4/24/18.
//

public struct SearchBoxCompletion {
    public init(name: String, detail: String, favorite: Bool) {
        self.name = name
        self.detail = detail
        self.favorite = favorite
    }
    
    public let name: String
    public let detail: String
    public let favorite: Bool
}

public protocol SearchBoxDelegate {
    func completions(for text: String) async throws -> [SearchBoxCompletion]
    
    @MainActor func favoriteUpdated(name: String, detail: String, favorite: Bool)
}

public extension SearchBoxDelegate {
    @MainActor func favoriteUpdated(name: String, detail: String, favorite: Bool) { }
}
