//
//  SearchHistory.swift
//  WeatherCheck
//
//  Created by Doug Stein on 4/16/18.
//  Copyright © 2018 Doug Stein. All rights reserved.
//

import Foundation

class SearchHistory: Sequence {
    var first: SearchHistoryItem
    var last: SearchHistoryItem
    var map = [String: SearchHistoryItem]()
    var count = 0
    var limit: Int
    
    init(limit: Int) {
        first = SearchHistoryItem(name: "", detail: "")
        last = first
        self.limit = Swift.max(limit, 2)
    }
    
    func add(name: String, detail: String) {
        var item: SearchHistoryItem! = map[name]
        if item != nil {
            if item.name == last.name {
                last = last.prev!
            }
            item.remove()
            item.timestamp = Date()
        } else {
            item = SearchHistoryItem(name: name, detail: detail)
            count += 1
            map[name] = item
            if count > limit {
                first.next!.remove()
                count -= 1
            }
        }
        last.next = item
        item.prev = last
        last = item
    }
    
    func makeIterator() -> SearchHistory.SearchHistoryIterator {
        return SearchHistoryIterator(item: last)
    }
    
    struct SearchHistoryIterator: IteratorProtocol {
        var currentItem: SearchHistoryItem
        
        init(item: SearchHistoryItem) {
            currentItem = item
        }
    
        mutating func next() -> SearchHistoryItem? {
            var item: SearchHistoryItem? = nil
            if let prev = currentItem.prev {
                item = currentItem
                currentItem = prev
            }
            return item
        }
    }
}

class SearchHistoryItem {
    var prev: SearchHistoryItem?
    var next: SearchHistoryItem?
    var name: String
    var detail: String
    var timestamp: Date
    
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
