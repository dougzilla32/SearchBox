//
//  SearchHistory.swift
//  SearchBox
//
//  Created by Doug Stein on 4/16/18.
//

import Foundation

@MainActor public class SearchHistory {
    private var searchHistoryList = SortedArray<SearchHistoryItem>()
    private var limit: Int
    private var map = [String: SearchHistoryItem]()
    private var favoriteCount = 0
    
   init(limit: Int) {
        self.limit = Swift.max(limit, 2)
    }
    
    public var count: Int {
        return map.count
    }
    
    public func matchingItems(isFavorited: Bool) -> [SearchHistoryItem] {
        var arr: [SearchHistoryItem] = []
        for item in searchHistoryList where item.favorite == isFavorited {
            arr.append(item)
        }
        return arr
    }
    
    public func get(name: String) -> SearchHistoryItem? {
        return map[name]
    }
    
    public func insertOrUpdate(name: String, detail: String, favorite: Bool) {
        var item: SearchHistoryItem! = map[name]
        if item != nil {
            if item.favorite != favorite {
                if favorite {
                    favoriteCount += 1
                } else {
                    favoriteCount -= 1
                }
            }
            
            searchHistoryList.remove(item)
            item = SearchHistoryItem(name: name, detail: detail, favorite: favorite, timestamp: item.timestamp)
        } else {
            if favorite {
                favoriteCount += 1
            }

            item = SearchHistoryItem(name: name, detail: detail, favorite: favorite)
        }
        
        map[name] = item

        // enforce limit on recent searches
        if !favorite && (map.count - favoriteCount) > limit {
            searchHistoryList.removeLast()
        }

        searchHistoryList.insert(item)
    }
    
    public func insertOrUpdate(_ item: SearchHistoryItem) {
        insertOrUpdate(name: item.name, detail: item.detail, favorite: item.favorite)
    }
    
    public func insert(contentsOf newItems: [SearchHistoryItem]) {
        for item in newItems {
            assert(map[item.name] == nil)
            map[item.name] = item
        }
        searchHistoryList.insert(contentsOf: newItems)
    }
    
    public func remove(_ item: SearchHistoryItem) {
        map.removeValue(forKey: item.name)
        searchHistoryList.remove(item)
    }
    
    public func rename(oldName: String, newName: String) {
        guard oldName != newName else {
            return
        }
        if var item = map[oldName] {
            if let dupItem = map[newName] {
                remove(dupItem)
            }

            searchHistoryList.remove(item)
            item = SearchHistoryItem(name: newName, detail: item.detail, favorite: item.favorite, timestamp: item.timestamp)
            insertOrUpdate(item)
        }
    }
    
    public func completions(nameStartsWith prefix: String? = nil) -> [SearchBoxCompletion] {
        var completionItems = [SearchBoxCompletion]()
        for historyItem in searchHistoryList {
            if prefix == nil || historyItem.name.lowercased().starts(with: prefix!) {
                completionItems.append(SearchBoxCompletion(name: historyItem.name, detail: historyItem.detail, favorite: historyItem.favorite))
            }
        }
        return completionItems
    }
}

public class SearchHistoryItem: Comparable {
    public static func < (lhs: SearchHistoryItem, rhs: SearchHistoryItem) -> Bool {
        let lt: Bool
        if lhs.favorite != rhs.favorite {
            lt = lhs.favorite
        } else {
            if lhs.favorite {
                lt = lhs.name < rhs.name
            } else {
                lt = lhs.timestamp < rhs.timestamp
            }
        }
        return lt
    }
    
    public static func == (lhs: SearchHistoryItem, rhs: SearchHistoryItem) -> Bool {
        return lhs.name == rhs.name
            && lhs.favorite == rhs.favorite
            && lhs.timestamp == rhs.timestamp
    }
    
    public let name: String
    public let detail: String
    public let favorite: Bool
    public let timestamp: Date
    
    public init(name: String, detail: String, favorite: Bool) {
        self.name = name
        self.detail = detail
        self.favorite = favorite
        timestamp = Date()
    }

    internal init(name: String, detail: String, favorite: Bool, timestamp: Date) {
        self.name = name
        self.detail = detail
        self.favorite = favorite
        self.timestamp = timestamp
    }
}
