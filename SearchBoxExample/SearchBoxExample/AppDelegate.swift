//
//  AppDelegate.swift
//  SearchBox
//
//  Created by dougzilla32 on 04/25/2018.
//  Copyright (c) 2018 dougzilla32. All rights reserved.
//

import Cocoa
import SwiftyBeaver

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        setupSwiftyBeaverLogging()
    }
    
    func setupSwiftyBeaverLogging() {
        let console = ConsoleDestination()
        console.minLevel = .verbose
        SwiftyBeaver.addDestination(console)
    }
    
    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }
    
}

