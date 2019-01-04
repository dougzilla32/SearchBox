//
//  SearchHistory.swift
//  SearchBox
//
//  Created by Doug Stein on 4/16/18.
//

import Foundation

public class SearchHistory: Sequence {
    private var first: SearchHistoryItem
    private var last: SearchHistoryItem
    private var lastNonFavorite: SearchHistoryItem
    public internal(set) var limit: Int
    public internal(set) var map = [String: SearchHistoryItem]()
    private var favoriteCount = 0

    init(limit: Int) {
        first = SearchHistoryItem(name: "", detail: "", favorite: false)
        last = first
        lastNonFavorite = first
        self.limit = Swift.max(limit, 2)
    }
    
    public func add(name: String, detail: String, favorite: Bool) {
        var item: SearchHistoryItem! = map[name]
        if item != nil {
            if item === last {
                last = last.prev!
            }
            if item === lastNonFavorite {
                lastNonFavorite = lastNonFavorite.prev!
            }
            
            item.remove()
            item.detail = detail
            
            if item.favorite != favorite {
                if favorite {
                    favoriteCount += 1
                } else {
                    favoriteCount -= 1
                }
            }
            item.favorite = favorite
        } else {
            item = SearchHistoryItem(name: name, detail: detail, favorite: favorite)
            map[name] = item
            if !favorite && (map.count - favoriteCount) > limit {
                let item = first.next!
                map[item.name] = nil
                item.remove()
            }
            if favorite {
                favoriteCount += 1
            }
        }
        
        if favorite {
            // Insert favorite items alphabetically
            var cur: SearchHistoryItem! = first.next
            while cur != nil {
                if cur.favorite && (cur.detail < item.detail || (cur.detail == item.detail && cur.name < item.name)) {
                    cur.prev!.insertAfter(item: item)
                    break
                }
                cur = cur.next
            }
            if cur == nil {
                last.insertAfter(item: item)
                last = item
            }
        } else {
            if last === lastNonFavorite {
                last = item
            }
            lastNonFavorite.insertAfter(item: item)
            lastNonFavorite = item
        }
    }
    
    public func makeIterator() -> SearchHistory.SearchHistoryIterator {
        return SearchHistoryIterator(item: last)
    }
    
    public struct SearchHistoryIterator: IteratorProtocol {
        var currentItem: SearchHistoryItem
        
        init(item: SearchHistoryItem) {
            currentItem = item
        }
    
        public mutating func next() -> SearchHistoryItem? {
            var item: SearchHistoryItem? = nil
            if let prev = currentItem.prev {
                item = currentItem
                currentItem = prev
            }
            return item
        }
    }
}

public class SearchHistoryItem {
    var prev: SearchHistoryItem?
    var next: SearchHistoryItem?
    public var name: String
    public var detail: String
    public var favorite: Bool
    public var any: Any?
    public var timestamp: Date
    
    init(name: String, detail: String, favorite: Bool) {
        self.name = name
        self.detail = detail
        self.favorite = favorite
        timestamp = Date()
    }
    
    func insertAfter(item: SearchHistoryItem) {
        item.prev = self
        item.next = next
        next?.prev = item
        next = item
    }
    
    func remove() {
        prev?.next = next
        next?.prev = prev
        next = nil
        prev = nil
    }
}
