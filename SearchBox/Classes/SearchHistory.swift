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
    public internal(set) var limit: Int
    public internal(set) var map = [String: SearchHistoryItem]()

    init(limit: Int) {
        first = SearchHistoryItem(name: "", detail: "")
        last = first
        self.limit = Swift.max(limit, 2)
    }
    
    public func add(name: String, detail: String) {
        var item: SearchHistoryItem! = map[name]
        if item != nil {
            if item.name == last.name {
                last = last.prev!
            }
            item.remove()
        } else {
            item = SearchHistoryItem(name: name, detail: detail)
            map[name] = item
            if map.count > limit {
                let item = first.next!
                map[item.name] = nil
                item.remove()
            }
        }
        last.next = item
        item.prev = last
        last = item
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
    public var any: Any?
    public var timestamp: Date
    
    init(name: String, detail: String) {
        self.name = name
        self.detail = detail
        timestamp = Date()
    }
    
    func remove() {
        prev?.next = next
        next?.prev = prev
        next = nil
        prev = nil
    }
}
