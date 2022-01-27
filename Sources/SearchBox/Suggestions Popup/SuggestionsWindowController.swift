//  Converted to Swift 4 by Swiftify v4.1.6654 - https://objectivec2swift.com/
/*
 File: SuggestionsWindowController.swift
 Abstract: The controller for the suggestions popup window. This class handles creating, displaying, and event tracking of the suggestion popup window.
 Version: 1.4
 Disclaimer: IMPORTANT:  This Apple software is supplied to you by Apple
 Inc. ("Apple") in consideration of your agreement to the following
 terms, and your use, installation, modification or redistribution of
 this Apple software constitutes acceptance of these terms.  If you do
 not agree with these terms, please do not use, install, modify or
 redistribute this Apple software.
 In consideration of your agreement to abide by the following terms, and
 subject to these terms, Apple grants you a personal, non-exclusive
 license, under Apple's copyrights in this original Apple software (the
 "Apple Software"), to use, reproduce, modify and redistribute the Apple
 Software, with or without modifications, in source and/or binary forms;
 provided that if you redistribute the Apple Software in its entirety and
 without modifications, you must retain this notice and the following
 text and disclaimers in all such redistributions of the Apple Software.
 Neither the name, trademarks, service marks or logos of Apple Inc. may
 be used to endorse or promote products derived from the Apple Software
 without specific prior written permission from Apple.  Except as
 expressly stated in this notice, no other rights or licenses, express or
 implied, are granted by Apple herein, including but not limited to any
 patent rights that may be infringed by your derivative works or by other
 works in which the Apple Software may be incorporated.
 The Apple Software is provided by Apple on an "AS IS" basis.  APPLE
 MAKES NO WARRANTIES, EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION
 THE IMPLIED WARRANTIES OF NON-INFRINGEMENT, MERCHANTABILITY AND FITNESS
 FOR A PARTICULAR PURPOSE, REGARDING THE APPLE SOFTWARE OR ITS USE AND
 OPERATION ALONE OR IN COMBINATION WITH YOUR PRODUCTS.
 IN NO EVENT SHALL APPLE BE LIABLE FOR ANY SPECIAL, INDIRECT, INCIDENTAL
 OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 INTERRUPTION) ARISING IN ANY WAY OUT OF THE USE, REPRODUCTION,
 MODIFICATION AND/OR DISTRIBUTION OF THE APPLE SOFTWARE, HOWEVER CAUSED
 AND WHETHER UNDER THEORY OF CONTRACT, TORT (INCLUDING NEGLIGENCE),
 STRICT LIABILITY OR OTHERWISE, EVEN IF APPLE HAS BEEN ADVISED OF THE
 POSSIBILITY OF SUCH DAMAGE.
 Copyright (C) 2012 Apple Inc. All Rights Reserved.
 */
import Cocoa

let kTrackerKey = "whichImageView"
let kThumbnailWidth: CGFloat = 24.0

let kSuggestionImage = "image"
let kSuggestionImageURL = "imageUrl"
let kSuggestionLabel = "label"
let kSuggestionDetailedLabel = "detailedLabel"
let kSuggestionFavorite = "favorite"
let kSuggestionObserver = "observer"

class SuggestionsWindowController: NSWindowController {
    var action: Selector?
    var target: Any?
    private var parentTextField: SearchBox?
    var suggestions = [[String: Any]]()
    private var viewControllers = [NSViewController]()
    private var trackingAreas = [AnyHashable]()
    private var needsLayoutUpdate = false
    private var localMouseDownEventMonitor: Any?
    private var lostFocusObserver: Any?
    private var cursorInsideView = false
    
    private var favoriteImage = NSImage(named: "Heart")
    private var favoriteOutlineImage = NSImage(named: "Heart outline")

    init() {
        let contentRec = NSRect(x: 0, y: 0, width: 20, height: 20)
        let window = SuggestionsWindow(contentRect: contentRec, defer: true)
        super.init(window: window)

        // SuggestionsWindow is a transparent window, create RoundedCornersView and set it as the content view to draw a menu like window.
        let contentView = RoundedCornersView(frame: contentRec)
        window.contentView = contentView
        contentView.autoresizesSubviews = false
        needsLayoutUpdate = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    /* Custom selectedView property setter so that we can set the highlighted property of the old and new selected views.
     */
    private var selectedView: NSView? {
        didSet {
            if selectedView != oldValue {
                (oldValue as? HighlightingView)?.setHighlighted(false)
            }
            (selectedView as? HighlightingView)?.setHighlighted(true)
        }
    }

    /* Set selected view and send action
     */
    func userSetSelectedView(_ view: NSView?) {
        selectedView = view
        if action != nil {
            NSApp.sendAction(action!, to: target, from: self)
        }
    }

    /* Position and lay out the suggestions window, set up auto cancelling tracking, and wires up the logical relationship for accessibility.
     */
    func begin(for parentTextField: SearchBox?) {
        let suggestionWindow: NSWindow? = window
        let parentWindow: NSWindow? = parentTextField?.window
        let parentFrame: NSRect? = parentTextField?.frame
        var frame: NSRect? = suggestionWindow?.frame
        frame?.size.width = (parentFrame?.size.width)!
        // Place the suggestion window just underneath the text field and make it the same width as th text field.
        var location = parentTextField?.superview?.convert(parentFrame?.origin ?? NSPoint.zero, to: nil)
        location = parentWindow?.convertToScreen(NSRect(x: location!.x, y: location!.y, width: 0, height: 0)).origin
        location?.y -= 2.0
        // nudge the suggestion window down so it doesn't overlapp the parent view
        suggestionWindow?.setFrame(frame ?? NSRect.zero, display: false)
        suggestionWindow?.setFrameTopLeftPoint(location ?? NSPoint.zero)
        // keep track of the parent text field in case we need to commit or abort editing.
        self.parentTextField = parentTextField
        layoutSuggestions()
        // The height of the window will be adjusted in -layoutSuggestions.
        // add the suggestion window as a child window so that it plays nice with Expose
        if let aWindow = suggestionWindow {
            parentWindow?.addChildWindow(aWindow, ordered: .above)
        }
        // The window must know its accessibility parent, the control must know the window one of its accessibility children
        // Note that views (controls especially) are often ignored, so we want the unignored descendant - usually a cell
        // Finally, post that we have created the unignored decendant of the suggestions window
        let unignoredAccessibilityDescendant = NSAccessibility.unignoredDescendant(of: parentTextField!)
        (suggestionWindow as? SuggestionsWindow)?.parentElement = unignoredAccessibilityDescendant
        (unignoredAccessibilityDescendant as? SuggestibleTextFieldCell)?.suggestionsWindow = suggestionWindow
        if let win = suggestionWindow, let winD = NSAccessibility.unignoredDescendant(of: win) {
            NSAccessibility.post(element: winD, notification: .created)
        }
        // setup auto cancellation if the user clicks outside the suggestion window and parent text field. Note: this is a local event monitor and will only catch clicks in windows that belong to this application. We use another technique below to catch clicks in other application windows.
        localMouseDownEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [NSEvent.EventTypeMask.leftMouseDown, NSEvent.EventTypeMask.rightMouseDown, NSEvent.EventTypeMask.otherMouseDown], handler: {(_ event: NSEvent) -> NSEvent? in
            // If the mouse event is in the suggestion window, then there is nothing to do.
            var event: NSEvent! = event
            if event.window != suggestionWindow {
                if event.window == parentWindow {
                    /* Clicks in the parent window should either be in the parent text field or dismiss the suggestions window. We want clicks to occur in the parent text field so that the user can move the caret or select the search text.
                     
                     Use hit testing to determine if the click is in the parent text field. Note: when editing an NSTextField, there is a field editor that covers the text field that is performing the actual editing. Therefore, we need to check for the field editor when doing hit testing.
                     */
                    let contentView: NSView? = parentWindow?.contentView
                    let locationTest: NSPoint? = contentView?.convert(event.locationInWindow, from: nil)
                    
                    let hitViews = contentView?.allViews(at: locationTest ?? NSPoint.zero) ?? []
                    let fieldEditor: NSText? = parentTextField?.currentEditor()
                    var insideParentTextField = false
                    for view in hitViews {
                        if view == parentTextField || ((fieldEditor != nil) && view == fieldEditor) {
                            insideParentTextField = true
                            break
                        }
                    }
                    if !insideParentTextField {
                        // Revert to original text value
                        parentTextField?.revertEditing()
                        // Since the click is not in the parent text field, return nil, so the parent window does not try to process it, and cancel the suggestion window.
                        event = nil
                        self.cancelSuggestions()
                    }
                } else {
                    // Not in the suggestion window, and not in the parent window. This must be another window or palette for this application.
                    // Revert to original text value
                    parentTextField?.revertEditing()                    
                    // Cancel the suggestion window
                    self.cancelSuggestions()
                }
            }
            return event
        })
        // as per the documentation, do not retain event monitors.
        // We also need to auto cancel when the window loses key status. This may be done via a mouse click in another window, or via the keyboard (cmd-~ or cmd-tab), or a notificaiton. Observing NSWindowDidResignKeyNotification catches all of these cases and the mouse down event monitor catches the other cases.
        lostFocusObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: parentWindow, queue: nil, using: {(_ arg1: Notification) -> Void in
            // lost key status, cancel the suggestion window
            self.cancelSuggestions()
        })
    }

    /* Order out the suggestion window, disconnect the accessibility logical relationship and dismantle any observers for auto cancel.
     Note: It is safe to call this method even if the suggestions window is not currently visible.
     */
    func cancelSuggestions() {
        let suggestionWindow: NSWindow? = window
        if suggestionWindow?.isVisible ?? false {
            // Remove the suggestion window from parent window's child window collection before ordering out or the parent window will get ordered out with the suggestion window.
            if let aWindow = suggestionWindow {
                suggestionWindow?.parent?.removeChildWindow(aWindow)
            }
            suggestionWindow?.orderOut(nil)
            // Disconnect the accessibility parent/child relationship
            ((suggestionWindow as? SuggestionsWindow)?.parentElement as? SuggestibleTextFieldCell)?.suggestionsWindow = nil
            (suggestionWindow as? SuggestionsWindow)?.parentElement = nil
        }
        // dismantle any observers for auto cancel
        if lostFocusObserver != nil {
            NotificationCenter.default.removeObserver(lostFocusObserver!)
            lostFocusObserver = nil
        }
        if localMouseDownEventMonitor != nil {
            NSEvent.removeMonitor(localMouseDownEventMonitor!)
            localMouseDownEventMonitor = nil
        }
        
        clearFavoriteObservers()
        clearUndoLists()
        parentTextField?.searchHistory?.resort()
    }

    /* Update the array of suggestions. The array should consist of NSDictionaries each containing the following keys:
     kSuggestionImageURL - The URL to an image file
     kSuggestionLabel - The main suggestion string
     kSuggestionDetailedLabel - A longer string that provides more detail about the suggestion
     kSuggestionImage - [optional] The image to show in the suggestion thumbnail. If this key is not provided, a thumbnail image will be created in a background que.
     */
    func setSuggestions(_ suggestions: [[String: Any]]?) {
        self.suggestions = suggestions!
        // We only need to update the layout if the window is currently visible.
        if (window?.isVisible)! {
            layoutSuggestions()
        }
    }

    /* Returns the dictionary of the currently selected suggestion.
     */
    func selectedSuggestion() -> [String: Any]? {
        if !(window?.isVisible)! {
            return nil
        }
        var suggestion: Any? = nil
        // Find the currently selected view's controller (if there is one) and return the representedObject which is the NSMutableDictionary that was passed in via -setSuggestions:
        let selectedView: NSView? = self.selectedView
        for viewController: NSViewController in viewControllers where selectedView == viewController.view {
            suggestion = viewController.representedObject
            break
        }
        return suggestion as? [String: Any]
    }

    // MARK: -
    // MARK: Mouse Tracking
    /* Mouse tracking is easily accomplished via tracking areas. We setup a tracking area for suggestion view and watch as the mouse moves in and out of those tracking areas.
     */
    /* Properly creates a tracking area for an image view.
     */
    func trackingArea(for view: NSView?) -> Any? {
        // make tracking data (to be stored in NSTrackingArea's userInfo) so we can later determine the imageView without hit testing
        var trackerData: [AnyHashable: Any]? = nil
        if let aView = view {
            trackerData = [
                kTrackerKey: aView
            ]
        }
        let trackingRect: NSRect = window!.contentView!.convert(view?.bounds ?? CGRect.zero, from: view)
        let trackingOptions: NSTrackingArea.Options = [.enabledDuringMouseDrag, .mouseEnteredAndExited, .activeInActiveApp]
        let trackingArea = NSTrackingArea(rect: trackingRect, options: trackingOptions, owner: self, userInfo: trackerData)
        return trackingArea
    }

    class FavoriteObserver: NSObject {
        let parentTextField: SearchBox
        
        init(parentTextField: SearchBox) { self.parentTextField = parentTextField }
        
        override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
            if let e = object as? Dictionary<String, Any> {
                parentTextField.favoriteUpdated(label: e[kSuggestionLabel] as! String, detailedLabel: e[kSuggestionDetailedLabel] as! String, favorite: e[kSuggestionFavorite] as! Bool)
            }
        }
    }
    
    private var favoriteObservers: [(NSMutableDictionary, FavoriteObserver)] = []
    private var favoritesLabel: NSTextView!
    private var favoritesButton: NSButton?
    private var recentlyVisitedLabel: NSTextView!
    private var recentlyVisitedButton: NSButton?
    private var headerColor: NSColor!
    
    private func clearFavoriteObservers() {
        for observer in favoriteObservers {
            observer.0.removeObserver(observer.1, forKeyPath: kSuggestionFavorite, context: nil)
        }
        favoriteObservers.removeAll()
    }
    
    // Creates suggestion views from suggestionprototype.xib for every suggestion and resize the suggestion window accordingly. Also creates a thumbnail image on a backgroung aue.
    private func layoutSuggestions() {
        let window: NSWindow? = self.window
        let contentView = window?.contentView as? RoundedCornersView
        // Remove any existing suggestion view and associated tracking area and set the selection to nil
        selectedView = nil
        cursorInsideView = false
        for viewController in viewControllers {
            viewController.view.removeFromSuperview()
        }
        viewControllers.removeAll()
        for trackingArea in trackingAreas {
            if let nsTrackingArea = trackingArea as? NSTrackingArea {
                contentView?.removeTrackingArea(nsTrackingArea)
            }
        }
        trackingAreas.removeAll()
        
        clearFavoriteObservers()
        
        headerColor = NSColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.1)
        if #available(OSX 10.14, *) {
            if contentView?.effectiveAppearance.name == .darkAqua || contentView?.effectiveAppearance.name == .vibrantDark {
                headerColor = NSColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.1)
            }
        }
        
        var hasFavoritesLabel = false
        var hasRecentlyVisitedLabel = false

        /* Iterate througn each suggestion creating a view for each entry.
         */
        /* The width of each suggestion view should match the width of the window. The height is determined by the view's height set in IB.
         */
        var contentFrame: NSRect? = contentView?.frame
        var frame = NSRect(x: 0, y: (contentView?.rcvCornerRadius)!, width: contentFrame!.width, height: 0.0)
        // offset the Y posistion so that the suggetion view does not try to draw past the rounded corners.
        for entry: [String: Any] in suggestions {
            frame.origin.y += frame.size.height

            if parentTextField?.stringValue.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) == ""
                || parentTextField?.showFavorites ?? false
                || undoFavorites != nil {
                var label: NSTextView!
                var button: NSButton!
                if (entry[kSuggestionFavorite] as? Bool) ?? false
                    || undoFavoriteNames?.contains(entry[kSuggestionLabel] as! String) ?? false {
                    if !hasFavoritesLabel {
                        if favoritesLabel == nil {
                            label = SuggestionsWindowController.createLabel("Favorites")
                            favoritesLabel = label
                            if parentTextField?.showClearFavoritesButton ?? false {
                                button = NSButton()
                                button.target = self
                                button.action = #selector(SuggestionsWindowController.toggleFavorites)
                            }
                            favoritesButton = button
                        } else {
                            label = favoritesLabel
                            button = favoritesButton
                        }
                        favoritesButton?.title = undoFavorites == nil ? "Clear" : "Undo"
                        hasFavoritesLabel = true
                    }
                } else {
                    if !hasRecentlyVisitedLabel {
                        if recentlyVisitedLabel == nil {
                            label = SuggestionsWindowController.createLabel("Recently Visited")
                            if parentTextField?.showClearRecentlyVisitedButton ?? false {
                                button = NSButton()
                                button.target = self
                                button.action = #selector(SuggestionsWindowController.toggleRecentlyVisited)
                            }
                            recentlyVisitedLabel = label
                            recentlyVisitedButton = button
                        } else {
                            label = recentlyVisitedLabel
                            button = recentlyVisitedButton
                        }
                        recentlyVisitedButton?.title = undoRecentlyVisited == nil ? "Clear" : "Undo"
                        hasRecentlyVisitedLabel = true
                    }
                }
                
                if label != nil {
                    frame.size.height = 21.0
                    label.frame = frame
                    label.backgroundColor = headerColor
                    let fontManager = NSFontManager.shared
                    label.font = fontManager.font(withFamily: label.font!.familyName!, traits: NSFontTraitMask.boldFontMask, weight: 0, size: 11.0)
                    contentView?.addSubview(label)

                    if button != nil {
                        button.bezelStyle = .inline
                        button.font = NSFont.systemFont(ofSize: 10.0)
                        button.cell?.backgroundStyle = .lowered
                        button.sizeToFit()
                        let inset = (frame.size.height - button.frame.size.height) / 2.0
                        button.frame = NSRect(
                            x: frame.size.width - (button.frame.size.width + 10) - inset,
                            y: inset,
                            width: button.frame.size.width + 10,
                            height: button.frame.size.height)
                        
                        label.addSubview(button)
                    }

                    frame.origin.y += frame.size.height
                }
            }
            
            let frameworkBundle = Bundle(for: SuggestionsWindowController.self)
            let viewController = NSViewController(nibName: "suggestionprototype", bundle: frameworkBundle)
            let view = viewController.view as? HighlightingView

            if parentTextField?.stringValue.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) == "" || parentTextField?.showFavorites ?? false {
                // If the search box is empty, then select the suggestion that matches the nameValue for the search box (what is reverts to)
                if entry[kSuggestionLabel] as? String == parentTextField?.nameValue {
                    selectedView = view
                }
            } else if viewControllers.count == 0 {
                // If the search box is not empty, then select the first suggestion
                selectedView = view
            }
            // Use the height as set in IB of the prototype view as the heigt for the suggestion view.
            frame.size.height = (view?.frame.size.height)!
            view?.frame = frame
            if let aView = view {
                contentView?.addSubview(aView)
            }
            // don't forget to create the tracking are.
            let trackingArea = self.trackingArea(for: view) as? NSTrackingArea
            if let anArea = trackingArea {
                contentView?.addTrackingArea(anArea)
            }
            // convert the suggestion enty to a mutable dictionary. This dictionary is bound to the view controller's representedObject. The represented object is what all the subviews are bound to in IB. We must use a mutable dictionary because we may change one of its key values.
            let mutableEntry = (entry as NSDictionary).mutableCopy() as! NSMutableDictionary
            viewController.representedObject = mutableEntry
            
            // set up favorite observer
            if let parentTextField = self.parentTextField {
                let observer = FavoriteObserver(parentTextField: parentTextField)
                mutableEntry[kSuggestionObserver] = observer
                mutableEntry.addObserver(observer, forKeyPath: kSuggestionFavorite, options: .new, context: nil)
                favoriteObservers.append((mutableEntry, observer))
            }
            
            viewControllers.append(viewController)
            if let anArea = trackingArea {
                trackingAreas.append(anArea)
            }
            /* If the suggestion entry does not contain an NSImage (and never does in this sample code), then create a thumbnail from the fileURL on a background que
             */
            if mutableEntry[kSuggestionImage] == nil && mutableEntry[kSuggestionImageURL] != nil {
                // Load the image in an operation block so that the window pops up immediatly
                ITESharedOperationQueue()?.addOperation({
                    if let fileURL = mutableEntry[kSuggestionImageURL] as? URL,
                        let thumbnailImage = NSImage.iteThumbnailImage(withContentsOf: fileURL, width: kThumbnailWidth) {
                        OperationQueue.main.addOperation({
                            mutableEntry[kSuggestionImage] = thumbnailImage
                        })
                    }
                })
            }
        }
        
        if !hasFavoritesLabel {
            favoritesLabel?.removeFromSuperview()
        }
        if !hasRecentlyVisitedLabel && undoRecentlyVisited == nil {
            recentlyVisitedLabel?.removeFromSuperview()
        }
        if undoRecentlyVisited != nil {
            recentlyVisitedButton?.title = "Undo"
            frame.origin.y += frame.size.height
            frame.size.height = 21.0
            recentlyVisitedLabel.frame = frame
        }
        /* We have added all of the suggestion to the window. Now set the size of the window.
         */
        // Don't forget to account for the extra room needed the rounded corners.
        contentFrame?.size.height = frame.maxY + (contentView?.rcvCornerRadius)!
        var winFrame: NSRect = NSRect(origin: window!.frame.origin, size: window!.frame.size)
        winFrame.origin.y = winFrame.maxY - contentFrame!.height
        winFrame.size.height = contentFrame!.height
        window?.setFrame(winFrame, display: true)
    }
    
    static func createLabel(_ name: String) -> NSTextView {
        let label = NSTextView()
        label.string = name
        label.isEditable = false
        label.isSelectable = false
        label.textContainerInset = NSSize(width: 0, height: 4)
        return label
    }

    private var undoFavorites: [SearchHistoryItem]?
    private var undoFavoriteNames: Set<String>?
    private var undoRecentlyVisited: [SearchHistoryItem]?
    private var undoRecentlyVisitedNames: Set<String>?
    
    private func clearUndoLists() {
        undoFavorites = nil
        undoFavoriteNames = nil
        undoRecentlyVisited = nil
        undoRecentlyVisitedNames = nil
    }

    @objc func toggleFavorites(sender: NSButton) {
        if let favorites = undoFavorites {
            undoFavorites = nil
            undoFavoriteNames = nil
            for f in favorites {
                f.favorite = true
            }
        } else {
            if let favorites = parentTextField?.searchHistory?.matchingItems(isFavorited: true) {
                undoFavorites = favorites
                undoFavoriteNames = Set()
                for f in favorites {
                    f.favorite = false
                    undoFavoriteNames?.insert(f.name)
                }
            }
        }
        parentTextField?.showFavorites = true
        parentTextField?.updateSuggestions(from: nil)
    }
    
    @objc func toggleRecentlyVisited() {
        if let recentlyVisited = undoRecentlyVisited {
            undoRecentlyVisited = nil
            undoRecentlyVisitedNames = nil
            for s in recentlyVisited {
                parentTextField?.searchHistory?.insert(s)
            }
        } else {
            if let recentlyVisited = parentTextField?.searchHistory?.matchingItems(isFavorited: false) {
                undoRecentlyVisited = recentlyVisited
                undoRecentlyVisitedNames = Set()
                for s in recentlyVisited {
                    parentTextField?.searchHistory?.remove(s)
                    undoRecentlyVisitedNames?.insert(s.name)
                }
            }
        }
        parentTextField?.showFavorites = true
        parentTextField?.updateSuggestions(from: nil)
    }
    
    /* The mouse is now over one of our child image views. Update selection and send action.
     */
    override func mouseEntered(with event: NSEvent) {
        let view: NSView?
        if let userData = event.trackingArea?.userInfo as? [String: NSView] {
            view = userData[kTrackerKey]!
            cursorInsideView = true
        } else {
            view = nil
            cursorInsideView = false
        }
        userSetSelectedView(view)
    }

    /* The mouse has left one of our child image views. Set the selection to no selection and send action
     */
    override func mouseExited(with event: NSEvent) {
        userSetSelectedView(nil)
        cursorInsideView = false
    }

    /* The user released the mouse button. Force the parent text field to send its return action. Notice that there is no mouseDown: implementation. That is because the user may hold the mouse down and drag into another view.
     */
    override func mouseUp(with theEvent: NSEvent) {
        guard cursorInsideView else {
            return
        }
        if let selectedSuggestion = selectedSuggestion() {
            parentTextField?.searchValue =
                (name: selectedSuggestion[kSuggestionLabel] as! String,
                 detail: selectedSuggestion[kSuggestionDetailedLabel] as! String,
                 favorite: selectedSuggestion[kSuggestionFavorite] as! Bool)
        }
        parentTextField?.validateEditing()
        parentTextField?.abortEditing()
        parentTextField?.sendAction(parentTextField?.action, to: parentTextField?.target)
        cancelSuggestions()
    }

    // MARK: -
    // MARK: Keyboard Tracking
    /* In addition to tracking the mouse, we want to allow changing our selection via the keyboard. However, the suggestion window never gets key focus as the key focus remains on te text field. Therefore we need to route move up and move down action commands from the text field and this controller. See CustomMenuAppDelegate.m -control:textView:doCommandBySelector: to see how that is done.
     */
    /* move the selection up and send action.
     */
    override func moveUp(_ sender: Any?) {
        let selectedView: NSView? = self.selectedView
        var previousView: NSView? = nil
        for viewController: NSViewController in viewControllers {
            let view: NSView? = viewController.view
            if view == selectedView {
                break
            }
            previousView = view
        }
        if previousView != nil {
            userSetSelectedView(previousView)
        }
    }
    /* move the selection down and send action.
     */
    override func moveDown(_ sender: Any?) {
        let selectedView: NSView? = self.selectedView
        var previousView: NSView? = nil
        for viewController: NSViewController in viewControllers.reversed() {
            let view: NSView? = viewController.view
            if view == selectedView {
                break
            }
            previousView = view
        }
        if previousView != nil {
            userSetSelectedView(previousView)
        }
    }
}

extension NSView {
    func allViews(at point: NSPoint) -> [NSView] {
        var stack = [NSView]()
        var result = [NSView]()
        
        stack.append(self)
        while let view = stack.popLast() {
            let localPoint = view.convert(point, from: self)
            
            if view.bounds.contains(localPoint) {
                result.append(view)
            }
            stack.append(contentsOf: view.subviews)
        }
        return result
    }
}

