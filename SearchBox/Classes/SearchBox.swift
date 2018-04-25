//
//  SearchBox.swift
//  WeatherCheck
//
//  Created by Doug Stein on 4/13/18.
//  Copyright © 2018 Doug Stein. All rights reserved.
//

import Alamofire
import Cocoa
import PromiseKit
import SwiftyBeaver

class SearchBox: NSSearchField, NSSearchFieldDelegate {
    // Delegate for this search box
    public var searchBoxDelegate: SearchBoxDelegate?
    
    // Do not take the focus if set to true
    public var refuseFocus = false
    
    // Indicates if we should show completions as highlighted text in the text field
    public var fillInCompletions = false
    
    // Indicates if we should hide the cancel button when the field does not have the focus
    public var hideCancelButton = false

    // If set to true, select all the text when we get a mouseDown event
    private var wantsSelectAll = false
    
    // Used to hide the cancel button when the search field does not have the focus.
    private var cancelButtonCell: NSButtonCell?
    
    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }
    
    public required init?(coder decoder: NSCoder) {
        super.init(coder: decoder)
        setup()
    }
    
    private func setup() {
        self.delegate = self
    }
    
    override func becomeFirstResponder() -> Bool {
        if refuseFocus {
            return false
        }
        // Select all the text when we get the focus
        wantsSelectAll = true
        return super.becomeFirstResponder()
    }
    
    override func mouseDown(with event: NSEvent) {
        if #available(OSX 10.11, *) {
            let location = convert(event.locationInWindow, from: nil)
            let rect = rectForCancelButton(whenCentered: false)
            if mouse(location, in: rect) {
                // Intercept the cancelButtonCell mouseDown event -- the default behavior causes
                // the search field to give up the focus which is not our desired behavior.
                self.stringValue = ""
                
                // Let the delegate know the text changed
                NotificationCenter.default.post(name: NSControl.textDidChangeNotification, object: self, userInfo: ["NSFieldEditor": self.window!.fieldEditor(true, for: self)!])
            } else {
                super.mouseDown(with: event)
            }
        } else {
            super.mouseDown(with: event)
        }
        
        if wantsSelectAll {
            if self.stringValue != "" {
                // Simulate Cmd+A for Select All
                let source = CGEventSource(stateID: CGEventSourceStateID.hidSystemState)
                let tapLocation = CGEventTapLocation.cghidEventTap
                let cmdA = CGEvent(keyboardEventSource: source, virtualKey: 0x00, keyDown: true)
                cmdA?.flags = CGEventFlags.maskCommand
                cmdA?.post(tap: tapLocation)
            }
            wantsSelectAll = false
        }
    }

    override func resignFirstResponder() -> Bool {
        let status = super.resignFirstResponder()
        // The NSText editor took the focus from this NSSearchField, so effectively we have the focus
        if currentEditor() != nil {
            // Show the cancel button while we have the focus
            if cancelButtonCell != nil {
                (cell as? NSSearchFieldCell)?.cancelButtonCell = cancelButtonCell
                cancelButtonCell = nil
            }
            
            if self.stringValue == "" {
                // For an empty text field, the delegate does not receive the begin editing notification.  So we send it ourselves here.
                NotificationCenter.default.post(name: NSControl.textDidBeginEditingNotification, object: self, userInfo: ["NSFieldEditor": self.window!.fieldEditor(true, for: self)!])
            }
        }
        return status
    }

    // MARK: Suggestions and Search History
    
    private var suggestionsController: SuggestionsWindowController = {
        // Create the suggestions controller
        let suggestionsController = SuggestionsWindowController()
        suggestionsController.target = self
        suggestionsController.action = #selector(SearchBox.update(withSelectedSuggestion:))
        return suggestionsController
    }()
    
    private var skipNextSuggestion = false
    private var searchHistory = SearchHistory(limit: 10)

    /* This is the action method for when the user changes the suggestion selection. Note, this action is called continuously as the suggestion selection changes while being tracked and does not denote user committal of the suggestion. For suggestion committal, the text field's action method is used (see above). This method is wired up programatically in the -controlTextDidBeginEditing: method below.
     */
    @IBAction func update(withSelectedSuggestion sender: Any) {
        let entry = (sender as? SuggestionsWindowController)?.selectedSuggestion()
        SwiftyBeaver.verbose("update \(String(describing: entry))")
        if entry != nil && !entry!.isEmpty {
            let fieldEditor: NSText? = self.window?.fieldEditor(false, for: self)
            if fieldEditor != nil {
                updateFieldEditor(fieldEditor, withSuggestion: entry![kSuggestionLabel] as? String)
            }
        }
    }
    
    var currentWorkItem: DispatchWorkItem?
    var currentRequest: Request?
    private var mostRecentCity: String?

    func cancelAllRequests() {
        if let workItem = currentWorkItem {
            currentWorkItem = nil
            workItem.cancel()
        }
        if let request = currentRequest {
            currentRequest = nil
            request.cancel()
        }
    }
    
    func after(seconds: TimeInterval) -> Guarantee<Void> {
        let (rg, seal) = Guarantee<Void>.pending()
        let when = DispatchTime.now() + seconds
        let task = DispatchWorkItem { seal(()) }
        currentWorkItem = task
        DispatchQueue.global(qos: .default).asyncAfter(deadline: when, execute: task)
        return rg
    }
    
    func completions(for text: String, delegate searchDelegate: SearchBoxDelegate) -> Promise<[(String,String)]> {
        let completions = searchDelegate.completions(for: text)
        self.currentRequest = completions.0
        return completions.1
    }
    
    func suggestions(forText text: String) -> Promise<[[String: Any]]> {
        cancelAllRequests()
        
        let searchDelegate: SearchBoxDelegate! = self.searchBoxDelegate
        if text == "" || searchDelegate == nil {
            var suggestions = [[String: Any]]()
            for item in searchHistory {
                suggestions.append([kSuggestionLabel: item.name, kSuggestionDetailedLabel: item.country])
            }
            return Promise.value(suggestions)
        }
        
        return self.after(seconds: 0.2).then { _ in
            return self.completions(for: self.stringValue, delegate: searchDelegate)
        }.then { cities -> Promise<[[String: Any]]> in
            self.currentRequest = nil
            
            var suggestions = [[String: Any]]()
            var alreadyUsed = Set<String>()
            for item in self.searchHistory where item.name.starts(with: self.stringValue) {
                suggestions.append([kSuggestionLabel: item.name, kSuggestionDetailedLabel: item.country])
                alreadyUsed.insert("\(item.name)|\(item.country)")
            }
            for city in cities {
                if !alreadyUsed.contains("\(city.0)|\(city.1)") {
                    suggestions.append([kSuggestionLabel: city.0, kSuggestionDetailedLabel: city.1])
                }
            }
            return Promise.value(suggestions)
        }
    }
    
    /* Determines the current list of suggestions, display the suggestions and update the field editor.
     */
    func updateSuggestions(from control: NSControl?) {
        SwiftyBeaver.verbose("updateSuggestions")
        let fieldEditor: NSText? = self.window?.fieldEditor(false, for: control)
        if fieldEditor != nil {
            // Only use the text up to the caret position
            let selection: NSRange? = fieldEditor?.selectedRange
            let text = (selection != nil) ? (fieldEditor?.string as NSString?)?.substring(to: selection!.location) : nil
            SwiftyBeaver.verbose("fetch suggestions IN \"\(String(describing: text))\"")
            
            firstly {
                self.suggestions(forText: text ?? "")
            }.done { suggestions in
                SwiftyBeaver.verbose("fetch suggestions OUT \"\(suggestions.count)\"")
                if suggestions.count > 0 {
                    // We have at least 1 suggestion. Update the field editor to the first suggestion and show the suggestions window.
                    let suggestion = suggestions[0]
                    self.updateFieldEditor(fieldEditor, withSuggestion: suggestion[kSuggestionLabel] as? String)
                    self.suggestionsController.setSuggestions(suggestions)
                    if !(self.suggestionsController.window?.isVisible ?? false) {
                        self.suggestionsController.begin(for: (control as? NSTextField))
                    }
                } else {
                    // No suggestions. Cancel the suggestion window.
                    self.cancelSuggestions()
                }
            }.catch { error in
                // TODO: indicate to the user that the suggestions are not working -- most likely due to the network being unavailable -- show a network down indicator on the refresh button
                SwiftyBeaver.error(error)
            }
        }
    }
    
    /* Update the field editor with a suggested string. The additional suggested characters are auto selected.
     */
    private func updateFieldEditor(_ fieldEditor: NSText?, withSuggestion suggestion: String?) {
        SwiftyBeaver.verbose("updateFieldEditor")
        /*
         NOTE: Do not update the text field with the suggestion text, because modern
         searches do not do this.
         
         let selection = NSRange(location: fieldEditor?.selectedRange.location ?? 0, length: suggestion?.count ?? 0)
         fieldEditor?.string = suggestion ?? ""
         fieldEditor?.selectedRange = selection
         */
    }
    
    func cancelSuggestions() {
        SwiftyBeaver.verbose("cancelSuggestions")
        cancelAllRequests()
        
        /* If the suggestionController is already in a cancelled state, this call does nothing and is therefore always safe to call.
         */
        suggestionsController.cancelSuggestions()
    }
    
    private func cancelEditing() {
        SwiftyBeaver.verbose("cancelEditing")
        cancelSuggestions()
        currentEditor()?.selectedRange = NSRange(location: 0, length: 0)
        self.window?.makeFirstResponder(nil)
    }
    
    private func endEditing() {
        SwiftyBeaver.verbose("endEditing")
        cancelEditing()
        mostRecentCity = self.stringValue
        searchBoxDelegate?.search(for: self.stringValue)
    }
    
    // MARK: NSTextFieldDelegate
    
    override func textDidEndEditing(_ notification: Notification) {
        super.textDidEndEditing(notification)
        if hideCancelButton {
            if currentEditor() == nil {
                // The NSText editor is cancelled, so effectively we resigned the focus.
                // Hide the cancel button when we do not have the focus.
                cancelButtonCell = (cell as? NSSearchFieldCell)?.cancelButtonCell
                (cell as? NSSearchFieldCell)?.cancelButtonCell = nil
            }
        }
    }

    /* In interface builder, we set this class object as the delegate for the search text field. When the user starts editing the text field, this method is called. This is an opportune time to display the initial suggestions.
     */
    override func controlTextDidBeginEditing(_ notification: Notification?) {
        SwiftyBeaver.verbose("controlTextDidBeginEditing")
        
        if !skipNextSuggestion {
            updateSuggestions(from: notification?.object as? NSControl)
        }
    }
    
    /* The field editor's text may have changed for a number of reasons. Generally, we should update the suggestions window with the new suggestions. However, in some cases (the user deletes characters) we cancel the suggestions window.
     */
    override func controlTextDidChange(_ notification: Notification?) {
        SwiftyBeaver.verbose("controlTextDidChange")
        if !skipNextSuggestion {
            updateSuggestions(from: notification?.object as? NSControl)
        } else {
            // If we are skipping this suggestion, then cancel the suggestions window.
            // If the suggestionController is already in a cancelled state, this call does nothing and is therefore always safe to call.
            suggestionsController.cancelSuggestions()
            // This suggestion has been skipped, don't skip the next one.
            skipNextSuggestion = false
        }
    }
    
    /* The field editor has ended editing the text. This is not the same as the action from the NSTextField. In the MainMenu.xib, the search text field is setup to only send its action on return / enter. If the user tabs to or clicks on another control, text editing will end and this method is called. We don't consider this committal of the action. Instead, we realy on the text field's action to commit
     the suggestion. However, since the action may not occur, we need to cancel the suggestions window here.
     */
    override func controlTextDidEndEditing(_ obj: Notification?) {
        SwiftyBeaver.verbose("controlTextDidEndEditing")
        suggestionsController.cancelSuggestions()
    }
    
    /* As the delegate for the NSTextField, this class is given a chance to respond to the key binding commands interpreted by the input manager when the field editor calls -interpretKeyEvents:. This is where we forward some of the keyboard commands to the suggestion window to facilitate keyboard navigation. Also, this is where we can determine when the user deletes and where we can prevent AppKit's auto completion.
     */
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            // Revert to previous city when escape key is pressed
            self.stringValue = mostRecentCity ?? ""
            cancelEditing()
            return true
        }
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            SwiftyBeaver.verbose("interceptNewline")
            // Giving up the focus will cause 'controlTextDidEndEditing' to be called
            if let selectedSuggestion = suggestionsController.selectedSuggestion() {
                self.stringValue = selectedSuggestion[kSuggestionLabel] as! String
            }
            self.window?.makeFirstResponder(nil)
            endEditing()
            
            // Intercept the newline, otherwise the city name will be selected (default behavior of NSTextField).  We do not want the text selected, because then the textfield appears to not have the focus. This is the appearance we want when the forecast is refreshed.
            return true
        }
        if commandSelector == #selector(NSResponder.moveUp(_:)) {
            // Move up in the suggested selections list
            suggestionsController.moveUp(textView)
            return true
        }
        if commandSelector == #selector(NSResponder.moveDown(_:)) {
            // Move down in the suggested selections list
            suggestionsController.moveDown(textView)
            return true
        }
        if commandSelector == #selector(NSResponder.deleteForward(_:)) || commandSelector == #selector(NSResponder.deleteBackward(_:)) {
            /* The user is deleting the highlighted portion of the suggestion or more. Return NO so that the field editor performs the deletion. The field editor will then call -controlTextDidChange:. We don't want to provide a new set of suggestions as that will put back the characters the user just deleted. Instead, set skipNextSuggestion to YES which will cause -controlTextDidChange: to cancel the suggestions window. (see -controlTextDidChange: above)
             */
            if fillInCompletions {
                // Disabled by default as modern search fields do not do this.
                let insertionRange = textView.selectedRanges[0].rangeValue
                if commandSelector == #selector(NSResponder.deleteBackward(_:)) {
                    skipNextSuggestion = (insertionRange.location != 0 || insertionRange.length > 0)
                } else {
                    skipNextSuggestion = (insertionRange.location != textView.string.count || insertionRange.length > 0)
                }
            }
            SwiftyBeaver.verbose("control skipNextSuggestion=\(skipNextSuggestion)")
            return false
        }
        if commandSelector == #selector(NSResponder.complete(_:)) {
            // The user has pressed the key combination for auto completion. AppKit has a built in auto completion. By overriding this command we prevent AppKit's auto completion and can respond to the user's intention by showing or cancelling our custom suggestions window.
            if suggestionsController.window != nil && suggestionsController.window!.isVisible {
                suggestionsController.cancelSuggestions()
            } else {
                updateSuggestions(from: control)
            }
            return true
        }
        // This is a command that we don't specifically handle, let the field editor do the appropriate thing.
        return false
    }
}

