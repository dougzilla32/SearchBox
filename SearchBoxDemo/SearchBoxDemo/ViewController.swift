//
//  ViewController.swift
//  SearchBox
//
//  Created by dougzilla32 on 04/25/2018.
//  Copyright (c) 2018 dougzilla32. All rights reserved.
//

import Cocoa
import SearchBox

class ViewController: NSViewController, NSWindowDelegate, SearchBoxDelegate {
    @IBOutlet weak var searchBox: SearchBox!
    
    @IBAction func searchMe(_ sender: Any) {
        print("searchMe: \(searchBox.stringValue) \(searchBox.detailValue)")
    }
    
    // MARK: NSViewController
    
    override func viewDidAppear() {
        self.view.window?.delegate = self
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        
        searchBox.searchBoxDelegate = self
        searchBox.searchHistoryCount = 10
    }
    
    // MARK: NSWindowDelegate
    
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        NSApplication.shared.terminate(self)
        return true
    }
    
    // MARK: SearchBoxDelegate

    func completions(for text: String) async throws -> [SearchBoxCompletion] {
        var completions = [SearchBoxCompletion]()
        if let spellCompletions = NSSpellChecker.shared.completions(forPartialWordRange: NSMakeRange(0, text.count), in: text, language: nil, inSpellDocumentWithTag: 0) {
            for s in spellCompletions {
                completions.append(SearchBoxCompletion(name: s, detail: "us", favorite: false))
            }
        }
        return completions
    }
}
