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
    private var favoriteCount = 0
    
    private var comparator: (SearchHistoryItem, SearchHistoryItem) -> Bool {
        didSet {
            resort()
        }
    }
    
    static func nameComparator(item1: SearchHistoryItem, item2: SearchHistoryItem) -> Bool {
        if item1.favorite != item2.favorite {
            return item1.favorite && !item2.favorite
        }
        return item1.name < item2.name
    }

    static func countryComparator(item1: SearchHistoryItem, item2: SearchHistoryItem) -> Bool {
        if item1.favorite != item2.favorite {
            return item1.favorite && !item2.favorite
        }
        if item1.detail != item2.detail {
            if item1.detail == "US" { return true }
            if item2.detail == "US" { return false }
            return item1.detail < item2.detail
        }
        return item1.name < item2.name
    }
    
    static func distanceComparator(item1: SearchHistoryItem, item2: SearchHistoryItem) -> Bool {
        if item1.favorite != item2.favorite {
            return item1.favorite && !item2.favorite
        }
        // TODO: compute distance from current location
        return item1.name < item2.name
    }
    
   init(limit: Int) {
        first = SearchHistoryItem(name: "", detail: "", favorite: false)
        last = first
        self.limit = Swift.max(limit, 2)
        
        comparator = SearchHistory.nameComparator
    }
    
    public func resort() {
        var arr: [SearchHistoryItem] = []
        var item: SearchHistoryItem! = first.next
        while item != nil {
            arr.append(item)
            item = item.next
        }
        arr.sort(by: comparator)
        arr.reverse()
        
        var prev = first
        for item in arr {
            prev.next = item
            item.prev = prev
            item.next = nil
            prev = item
        }
    }
    
    func matchingItems(isFavorited: Bool) -> [SearchHistoryItem] {
        var arr: [SearchHistoryItem] = []
        var item: SearchHistoryItem! = last
        while item !== first {
            if item.favorite == isFavorited {
                arr.append(item)
            }
            item = item.prev
        }
        return arr
    }
    
    public func append(name: String, detail: String, favorite: Bool) {
        var item: SearchHistoryItem! = map[name]
        if item != nil {
            // update existing item, leave it in the same place in the list
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
            // add new item
            item = SearchHistoryItem(name: name, detail: detail, favorite: favorite)
            map[name] = item
            if favorite {
                favoriteCount += 1
            }
            last.insertAfter(item)
            last = item
        }
    }
    
    public func insert(name: String, detail: String, favorite: Bool) {
        var item: SearchHistoryItem! = map[name]
        if item != nil {
            // update existing item, remove from list and re-insert
            if item === last {
                last = last.prev!
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
            // add new item
            item = SearchHistoryItem(name: name, detail: detail, favorite: favorite)
            map[name] = item
            if favorite {
                favoriteCount += 1
            }
        }
        
        // enforce limit on recent searches
        if !favorite && (map.count - favoriteCount) > limit {
            let del = first.next!
            map[del.name] = nil
            del.remove()
        }

        // insert item into the list according to 'comparator'
        var cur: SearchHistoryItem! = first.next
        while cur != nil {
            if comparator(cur, item) {
                cur.prev!.insertAfter(item)
                break
            }
            cur = cur.next
        }
        if cur == nil {
            last.insertAfter(item)
            last = item
        }
    }
    
    func insert(_ item: SearchHistoryItem) {
        assert(map[item.name] == nil)
        map[item.name] = item
        if item.favorite {
            favoriteCount += 1
        }
        first.insertAfter(item)
        if last === first {
            last = item
        }
    }
    
    func remove(_ item: SearchHistoryItem) {
        assert(map[item.name] != nil)
        if last === item {
            last = item.prev!
        }
        map.removeValue(forKey: item.name)
        if item.favorite {
            favoriteCount -= 1
        }
        item.remove()
    }
    
    public func rename(oldName: String, newName: String) {
        guard oldName != newName else {
            return
        }
        if let item = map[oldName] {
            if let dupItem = map[newName] {
                dupItem.remove()
            }

            // re-insert to sort properly
            item.remove()
            item.name = newName
            insert(name: item.name, detail: item.detail, favorite: item.favorite)
        }
    }
    
    public func makeIterator() -> SearchHistory.SearchHistoryIterator {
        return SearchHistoryIterator(currentItem: last, firstItem: first)
    }
    
    public struct SearchHistoryIterator: IteratorProtocol {
        var currentItem: SearchHistoryItem
        var firstItem: SearchHistoryItem
    
        public mutating func next() -> SearchHistoryItem? {
            var item: SearchHistoryItem? = nil
            if let prev = currentItem.prev {
                item = currentItem
                currentItem = prev
            }
            return (item === firstItem) ? nil : item
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
    
    func insertAfter(_ item: SearchHistoryItem) {
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
