//
//  ViewController.swift
//  SearchBox
//
//  Created by dougzilla32 on 04/25/2018.
//  Copyright (c) 2018 dougzilla32. All rights reserved.
//

import Cocoa
import SearchBox
import Alamofire
import PromiseKit
import CancelForPromiseKit

class ViewController: NSViewController, SearchBoxDelegate {
    func completions(for text: String) -> Promise<[(String, String)]> {
        var completions = [(String, String)]()
        if let spellCompletions = NSSpellChecker.shared.completions(forPartialWordRange: NSMakeRange(0, text.count), in: text, language: nil, inSpellDocumentWithTag: 0) {
            for s in spellCompletions {
                completions.append((s, "us"))
            }
        }
        return Promise.valueCC(completions)
    }
    
    @IBAction func searchMe(_ sender: Any) {
        print("searchMe: \(searchBox.stringValue) \(searchBox.detailValue)")
    }
    
    @IBOutlet weak var searchBox: SearchBox!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        searchBox.searchBoxDelegate = self        
        searchBox.searchHistoryCount = 10
    }
    
    override var representedObject: Any? {
        didSet {
            // Update the view, if already loaded.
        }
    }
}
