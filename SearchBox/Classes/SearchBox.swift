//
//  SearchBox.swift
//  SearchBox
//
//  Created by Doug Stein on 4/13/18.
//

import Cocoa
import PromiseKit
import SwiftyBeaver

@IBDesignable
public class SearchBox: NSSearchField, NSSearchFieldDelegate {
    // Delegate for this search box
    public var searchBoxDelegate: SearchBoxDelegate?
    
    // Do not take the focus if set to true
    public var refuseFocus: Bool = false
    
    // Indicates if we should show completions as highlighted text in the text field
    @IBInspectable public var fillCompletions: Bool = false
    
    // Indicates if we should hide the cancel button when the field does not have the focus
    @IBInspectable public var hideCancelButton: Bool = false

    // If set to a number greater than zero, the SearchBox keeps track of this many items
    // it it's search history.  Setting this value clears any existing history.
    public var searchHistoryCount: Int {
        get {
            return searchHistory?.map.count ?? 0
        }
        
        set {
            if newValue != 0 {
                searchHistory = SearchHistory(limit: newValue)
            } else {
                searchHistory = nil
            }
        }
    }
    
    public var searchName: String {
        get {
            return nameValue
        }
        
        set {
            let historyItem = searchHistory?.map[newValue]
            searchValue = (name: newValue, detail: historyItem?.detail ?? "", favorite: historyItem?.favorite ?? false)
        }
    }
    
    public var searchValue: (name: String, detail: String, favorite: Bool) {
        get {
            return (name: stringValue, detail: detailValue, favorite: favoriteValue)
        }
        
        set {
            stringValue = newValue.name
            nameValue = newValue.name
            detailValue = newValue.detail
            favoriteValue = newValue.favorite
            searchHistory?.insert(name: newValue.name, detail: newValue.detail, favorite: newValue.favorite)
        }
    }
    
    public func updateName(oldName: String, newName: String) {
        if nameValue == oldName {
            stringValue = newName
            nameValue = newName
            if let item = searchHistory?.map[oldName] {
                detailValue = item.detail
                favoriteValue = item.favorite
            }
        }
        
        searchHistory?.rename(oldName: oldName, newName: newName)
    }
    
    // The most recently searched name
    var nameValue = ""
    
    // The most recently selected detail from the suggestions window
    public var detailValue = ""

    // The most recently selected favorite from the suggestions window
    private var favoriteValue = false
    
    public internal(set) var searchHistory: SearchHistory?
    
    // If set to true, select all the text when we get a mouseDown event
    private var wantsSelectAll = false
    
    // If set to true, show favorites and recently searched rather than completions
    var showFavorites = false
    
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
        self.sendsSearchStringImmediately = true
        self.sendsWholeSearchString = true
    }
    
    override public func awakeFromNib() {
        super.awakeFromNib()
        setup()
    }
    
    override public func becomeFirstResponder() -> Bool {
        if refuseFocus {
            return false
        }
        // Select all the text when we get the focus
        wantsSelectAll = true
        return super.becomeFirstResponder()
    }
    
    override public func mouseDown(with event: NSEvent) {
        if #available(OSX 10.11, *) {
            let location = convert(event.locationInWindow, from: nil)
            let rect = rectForCancelButton(whenCentered: false)
            if mouse(location, in: rect) {
                // Intercept the cancelButtonCell mouseDown event -- the default behavior causes
                // the search field to give up the focus which is not our desired behavior.
                super.stringValue = ""
                
                // Let the delegate know the text changed
                NotificationCenter.default.post(name: NSControl.textDidBeginEditingNotification, object: self, userInfo: ["NSFieldEditor": self.window!.fieldEditor(true, for: self)!])
            } else {
                super.mouseDown(with: event)
            }
        } else {
            super.mouseDown(with: event)
        }
        
        if wantsSelectAll {
            wantsSelectAll = false
            if self.stringValue.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) != "" {
                if let textEditor = currentEditor() {
                    textEditor.selectAll(self)
                }
                showFavorites = true
                // Let the delegate know the text changed
                NotificationCenter.default.post(name: NSControl.textDidBeginEditingNotification, object: self, userInfo: ["NSFieldEditor": self.window!.fieldEditor(true, for: self)!])
            }
        }
    }

    override public func resignFirstResponder() -> Bool {
        let status = super.resignFirstResponder()
        // The NSText editor took the focus from this NSSearchField, so effectively we have the focus
        if currentEditor() != nil {
            // Show the cancel button while we have the focus
            if hideCancelButton && cancelButtonCell != nil {
                (cell as? NSSearchFieldCell)?.cancelButtonCell = cancelButtonCell
                cancelButtonCell = nil
            }
            
            if self.stringValue.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) == "" {
                // For an empty text field, the delegate does not receive the begin editing notification.  So we send it ourselves here.
                NotificationCenter.default.post(name: NSControl.textDidBeginEditingNotification, object: self, userInfo: ["NSFieldEditor": self.window!.fieldEditor(true, for: self)!])
            }
        }
        return status
    }

    // MARK: Suggestions and Search History
    
    private var suggestionsController: SuggestionsWindowController?

    private var skipNextSuggestion = false

    /* This is the action method for when the user changes the suggestion selection. Note, this action is called continuously as the suggestion selection changes while being tracked and does not denote user committal of the suggestion. For suggestion committal, the text field's action method is used (see above). This method is wired up programatically in the -controlTextDidBeginEditing: method below.
     */
    @IBAction public func update(withSelectedSuggestion sender: Any?) {
        let entry = (sender as? SuggestionsWindowController)?.selectedSuggestion()
        if entry != nil && !entry!.isEmpty {
            let fieldEditor: NSText? = self.window?.fieldEditor(false, for: self)
            if fieldEditor != nil {
                updateFieldEditor(fieldEditor, withSuggestion: entry![kSuggestionLabel] as? String)
            }
        }
    }
    
    var cancelContext: CancelContext?

    func cancelAllRequests() {
        cancelContext?.cancel()
        cancelContext = nil
    }
    
    func suggestions(forText text: String) -> CancellablePromise<[[String: Any]]> {
        let searchDelegate: SearchBoxDelegate! = self.searchBoxDelegate
        if text == "" || searchDelegate == nil {
            var suggestions = [[String: Any]]()
            if searchHistory != nil {
                for item in searchHistory! {
                    suggestions.append([kSuggestionLabel: item.name, kSuggestionDetailedLabel: item.detail, kSuggestionFavorite: item.favorite])
                }
            }
            return cancellable(Promise.value(suggestions))
        }
        
        return searchDelegate.completions(for: self.stringValue.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)).map { items -> [[String: Any]] in
            var suggestions = [[String: Any]]()
            var alreadyUsed = Set<String>()
            if self.searchHistory != nil {
                let lowercasedStringValue = self.stringValue.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).lowercased()
                for item in self.searchHistory! where item.name.lowercased().starts(with: lowercasedStringValue) {
                    suggestions.append([kSuggestionLabel: item.name, kSuggestionDetailedLabel: item.detail, kSuggestionFavorite: item.favorite])
                    alreadyUsed.insert("\(item.name)|\(item.detail)")
                }
            }
            for item in items {
                if !alreadyUsed.contains("\(item.0)|\(item.1)") {
                    suggestions.append([kSuggestionLabel: item.0, kSuggestionDetailedLabel: item.1, kSuggestionFavorite: item.2])
                }
            }
            return suggestions
        }
    }
    
    /* Determines the current list of suggestions, display the suggestions and update the field editor.
     */
    func updateSuggestions(from control: NSControl?) {
        guard let fieldEditor = self.window?.fieldEditor(false, for: control) else {
            return
        }
        
        let text: String?
        if fillCompletions {
            // Only use the text up to the caret position
            let selection: NSRange? = fieldEditor.selectedRange
            text = (selection != nil) ? (fieldEditor.string as NSString?)?.substring(to: selection!.location) : nil
        } else {
            text = fieldEditor.string
        }
        
        cancelAllRequests()
        
        cancelContext = firstly {
            self.suggestions(forText: showFavorites ? "" : (text ?? ""))
        }.done { suggestions in
            if suggestions.count > 0 {
                // We have at least 1 suggestion. Update the field editor to the first suggestion and show the suggestions window.
                let suggestion = suggestions[0]
                self.updateFieldEditor(fieldEditor, withSuggestion: suggestion[kSuggestionLabel] as? String)
                self.suggestionsController?.setSuggestions(suggestions)
                if !(self.suggestionsController?.window?.isVisible ?? false) {
                    self.suggestionsController?.begin(for: (control as? SearchBox))
                }
            } else if self.showFavorites {
                self.suggestionsController?.setSuggestions(suggestions)
            } else {
                // No suggestions. Cancel the suggestion window.
                self.cancelSuggestions()
            }
            self.showFavorites = false
        }.catch { error in
            // TODO: indicate to the user that the suggestions are not working -- most likely due to the network being unavailable -- show a network down indicator on the refresh button
            SwiftyBeaver.error(error)
        }.cancelContext
        cancelContext?.timeout(after: 10.0)
    }
    
    func favoriteUpdated(label: String, detailedLabel: String, favorite: Bool) {
        searchHistory?.insert(name: label, detail: detailedLabel, favorite: favorite)
        if nameValue != "" {
            if nameValue == label {
                detailValue = detailedLabel
                favoriteValue = favorite
            } else {
                searchHistory?.insert(name: nameValue, detail: detailValue, favorite: favoriteValue)
            }
        }
        searchBoxDelegate?.favoriteUpdated(name: label, detail: detailedLabel, favorite: favorite)
    }
    
    /* Update the field editor with a suggested string. The additional suggested characters are auto selected.
     */
    private func updateFieldEditor(_ fieldEditor: NSText?, withSuggestion suggestion: String?) {
        /*
         NOTE: Do not update the text field with the suggestion text, because modern
         searches do not do this.
         
         let selection = NSRange(location: fieldEditor?.selectedRange.location ?? 0, length: suggestion?.count ?? 0)
         fieldEditor?.string = suggestion ?? ""
         fieldEditor?.selectedRange = selection
         */
    }
    
    func cancelSuggestions() {
        cancelAllRequests()
        
        /* If the suggestionController is already in a cancelled state, this call does nothing and is therefore always safe to call.
         */
        suggestionsController?.cancelSuggestions()
    }
    
    private func cancelEditing() {
        cancelSuggestions()
        currentEditor()?.selectedRange = NSRange(location: 0, length: 0)
        self.window?.makeFirstResponder(nil)
    }
    
    public func revertEditing() {
        super.stringValue = nameValue
        cancelEditing()
    }
    
    private func endEditing() {
        cancelEditing()

        let value = self.stringValue.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        if value != "" {
            searchValue = (name: value, detail: detailValue, favorite: favoriteValue)
            sendAction(action, to: target)
        } else if nameValue != "" {
            super.stringValue = nameValue
        }
    }
    
    @discardableResult
    override open func sendAction(_ action: Selector?, to target: Any?) -> Bool {
        // Workaround for bug where the NSSearchField sends an action event when the user selects all
        // the text and presses the delete key.
        guard stringValue.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) != "" else {
            return false
        }
        
        return super.sendAction(action, to: target)
    }


    // MARK: NSTextFieldDelegate
    
    override public func textDidEndEditing(_ notification: Notification) {
        super.textDidEndEditing(notification)
        if hideCancelButton && currentEditor() == nil {
            // The NSText editor is cancelled, so effectively we resigned the focus.
            // Hide the cancel button when we do not have the focus.
            cancelButtonCell = (cell as? NSSearchFieldCell)?.cancelButtonCell
            (cell as? NSSearchFieldCell)?.cancelButtonCell = nil
        }
    }

    /* In interface builder, we set this class object as the delegate for the search text field. When the user starts editing the text field, this method is called. This is an opportune time to display the initial suggestions.
     */
    override public func controlTextDidBeginEditing(_ notification: Notification) {
        if !skipNextSuggestion {
            if suggestionsController == nil {
                suggestionsController = SuggestionsWindowController()
                suggestionsController?.target = self
                suggestionsController?.action = #selector(SearchBox.update(withSelectedSuggestion:))
            }
            updateSuggestions(from: notification.object as? NSControl)
        }
    }
    
    /* The field editor's text may have changed for a number of reasons. Generally, we should update the suggestions window with the new suggestions. However, in some cases (the user deletes characters) we cancel the suggestions window.
     */
    override public func controlTextDidChange(_ notification: Notification) {
        if !skipNextSuggestion {
            updateSuggestions(from: notification.object as? NSControl)
        } else {
            // If we are skipping this suggestion, then cancel the suggestions window.
            // If the suggestionController is already in a cancelled state, this call does nothing and is therefore always safe to call.
            suggestionsController?.cancelSuggestions()
            // This suggestion has been skipped, don't skip the next one.
            skipNextSuggestion = false
        }
    }
    
    /* The field editor has ended editing the text. This is not the same as the action from the NSTextField. In the MainMenu.xib, the search text field is setup to only send its action on return / enter. If the user tabs to or clicks on another control, text editing will end and this method is called. We don't consider this committal of the action. Instead, we realy on the text field's action to commit
     the suggestion. However, since the action may not occur, we need to cancel the suggestions window here.
     */
    override public func controlTextDidEndEditing(_ obj: Notification) {
        suggestionsController?.cancelSuggestions()
    }
    
    /* As the delegate for the NSTextField, this class is given a chance to respond to the key binding commands interpreted by the input manager when the field editor calls -interpretKeyEvents:. This is where we forward some of the keyboard commands to the suggestion window to facilitate keyboard navigation. Also, this is where we can determine when the user deletes and where we can prevent AppKit's auto completion.
     */
    public func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            // Revert to previous city when escape key is pressed
            revertEditing()
            return true
        }
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            // Giving up the focus will cause 'controlTextDidEndEditing' to be called
            if let selectedSuggestion = suggestionsController?.selectedSuggestion() {
                super.stringValue = selectedSuggestion[kSuggestionLabel] as! String
                nameValue = selectedSuggestion[kSuggestionLabel] as! String
                detailValue = selectedSuggestion[kSuggestionDetailedLabel] as! String
                favoriteValue = selectedSuggestion[kSuggestionFavorite] as! Bool
            } else {
                detailValue = ""
                favoriteValue = false
            }
            
            self.window?.makeFirstResponder(nil)
            endEditing()
            
            // Intercept the newline, otherwise the city name will be selected (default behavior of NSTextField).  We do not want the text selected, because then the textfield appears to not have the focus. This is the appearance we want when the forecast is refreshed.
            return true
        }
        if commandSelector == #selector(NSResponder.moveUp(_:)) {
            // Move up in the suggested selections list
            suggestionsController?.moveUp(textView)
            return true
        }
        if commandSelector == #selector(NSResponder.moveDown(_:)) {
            // Move down in the suggested selections list
            suggestionsController?.moveDown(textView)
            return true
        }
        if commandSelector == #selector(NSResponder.deleteForward(_:)) || commandSelector == #selector(NSResponder.deleteBackward(_:)) {
            /* The user is deleting the highlighted portion of the suggestion or more. Return NO so that the field editor performs the deletion. The field editor will then call -controlTextDidChange:. We don't want to provide a new set of suggestions as that will put back the characters the user just deleted. Instead, set skipNextSuggestion to YES which will cause -controlTextDidChange: to cancel the suggestions window. (see -controlTextDidChange: above)
             */
            if fillCompletions {
                // Disabled by default as modern search fields do not do this.
                let insertionRange = textView.selectedRanges[0].rangeValue
                if commandSelector == #selector(NSResponder.deleteBackward(_:)) {
                    skipNextSuggestion = (insertionRange.location != 0 || insertionRange.length > 0)
                } else {
                    skipNextSuggestion = (insertionRange.location != textView.string.count || insertionRange.length > 0)
                }
            }
            return false
        }
        if commandSelector == #selector(NSResponder.complete(_:)) {
            // The user has pressed the key combination for auto completion. AppKit has a built in auto completion. By overriding this command we prevent AppKit's auto completion and can respond to the user's intention by showing or cancelling our custom suggestions window.
            if suggestionsController?.window != nil && suggestionsController!.window!.isVisible {
                suggestionsController?.cancelSuggestions()
            } else {
                updateSuggestions(from: control)
            }
            return true
        }
        // This is a command that we don't specifically handle, let the field editor do the appropriate thing.
        return false
    }
}

extension DispatchWorkItem: Equatable {
    public static func ==(lhs: DispatchWorkItem, rhs: DispatchWorkItem) -> Bool {
        // Compare the instances
        return lhs === rhs
    }
}

extension DispatchWorkItem: Hashable {
    public var hashValue: Int {
        // Use the instance's unique identifier for hashing
        return ObjectIdentifier(self).hashValue
    }
}
