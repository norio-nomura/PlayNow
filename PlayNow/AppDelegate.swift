//
//  AppDelegate.swift
//  PlayNow
//
//  Created by 野村 憲男 on 9/5/15.
//
//  Copyright (c) 2015 Norio Nomura
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.
//

import Cocoa

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {

    @IBOutlet weak var window: NSWindow!

    let url = Process.arguments.dropFirst().first.map { NSURL(fileURLWithPath: $0) }
    var executed = false

    func applicationDidFinishLaunching(notification: NSNotification) {
        // Document said "Service requests can arrive immediately after you register the object."
        // But it does not as I tested.
        NSApplication.sharedApplication().servicesProvider = self
        
        // So, 
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, numericCast(NSEC_PER_SEC)), dispatch_get_main_queue()) {
            [unowned self] in
            if !self.executed {
                do {
                    try Playground(fileURL: self.url).update()
                } catch {
                    NSLog("#PlayNow: \(error)")
                }
            }
            NSApplication.sharedApplication().terminate(self)
        }
    }

    /// Service Provider handler
    /// - SeeAlso: [Services Implementation Guide](https://developer.apple.com/library/prerelease/mac/documentation/Cocoa/Conceptual/SysServices/introduction.html)
    func executeInPlayground(pasteboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        let contents = pasteboard.stringForType(NSPasteboardTypeString)
        
        do {
            // When called from Services, avoid added Page regarding unused.
            try Playground(fileURL: url, contentsSwift: contents).update().checkMakeUsedIfFromServices()
        } catch {
            NSLog("#PlayNow: \(error)")
        }
        
        executed = true
    }
}

