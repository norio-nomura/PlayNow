//
//  Playground.swift
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

struct Playground {
    enum Error: ErrorType {
        case CantBuildPlaygroundURL
        case UnknownPlaygroundVersion
    }
    
    let baseURL: NSURL
    let contentsSwiftData: NSData?
    init(fileURL: NSURL?, contentsSwift: String? = nil) throws {
        baseURL = try Playground.playgroundURL(fromURL: fileURL)
        contentsSwiftData = Playground.contentsSwiftData(contentsSwift)
    }
    
    var contentsXcplaygroundURL: NSURL {
        return baseURL.URLByAppendingPathComponent(Playground.contentsXcplayground)
    }
    
    var pagesURL: NSURL {
        return baseURL.URLByAppendingPathComponent(Playground.pagesPathExtension, isDirectory: true)
    }
    
    var pageURL: NSURL {
        return pagesURL.URLByAppendingPathComponent(Playground.pagePathComponent, isDirectory: true)
    }
    
    var pageContentsSwiftURL: NSURL {
        return pageURL.URLByAppendingPathComponent(Playground.contentsSwift)
    }
    
    func update() throws -> Playground {
        // check existence of contents.xcplayground
        let ws = NSWorkspace.sharedWorkspace()
        if contentsXcplaygroundURL.fileURLExists {
            try addPageToPlayground()
            
            // open playground.
            let app = try ws.openURL(baseURL, options: .WithoutActivation, configuration: [:])
            
            // wait until finishedLaunching if openURL() launching Xcode
            while !app.finishedLaunching {
                NSRunLoop.currentRunLoop().runUntilDate(NSDate(timeIntervalSinceNow: 1))
            }
            // wait 3+ seconds for openURL() launching Xcode
            sleep(Playground.waitSecondsBeforeOpeningPage) // wait 3+ seconds
            
            // open page in playground
            try ws.openURL(pageURL, options: [], configuration: [:])
            
        } else { // file does not exist
            try buildPlayground()
            
            // open playground.
            ws.openURL(baseURL)
        }
        return self
    }
    
    /// add page to existing Playground
    func addPageToPlayground() throws {
        // check version
        let contentsXcplayground = try NSXMLDocument(contentsOfURL: contentsXcplaygroundURL, options: NSXMLNodeOptionsNone)
        guard let playgroundNode = try contentsXcplayground.nodesForXPath("/playground").first as? NSXMLElement,
            let version = playgroundNode.attributeForName("version")?.stringValue
            where version == "6.0" else {
                throw Playground.Error.UnknownPlaygroundVersion
        }
        
        // save unused pages before adding page
        let unusedPageURLs = try unusedPages()
        
        // add page
        let fm = NSFileManager.defaultManager()
        try fm.createDirectoryAtURL(pageURL, withIntermediateDirectories: true, attributes: nil)
        do {
            try contentsSwiftData?.writeToURL(pageContentsSwiftURL, options: .DataWritingWithoutOverwriting)
        } catch NSCocoaError.FileWriteFileExistsError {
            // ignore file exists error. It may happen by configuration of "pageNameDateFormat"
        }
        
        // remove unused pages
        do { try unusedPageURLs.forEach(fm.removeItemAtURL) } catch {}
        
        // update contents.xcplayground if "/playground/pages" exists
        if let pagesNode = try playgroundNode.nodesForXPath("./pages").first as? NSXMLElement {
            
            func basenameFromURL(url: NSURL) -> String? {
                return (url.lastPathComponent as NSString?)?.stringByDeletingPathExtension
            }
            
            // remove each unused page from pages node
            try unusedPageURLs.flatMap(basenameFromURL).forEach {
                try pagesNode.nodesForXPath("./page[@name=\"\($0)\"]").forEach {
                    $0.detach()
                }
            }
            
            // add page to pages node
            let pageNode = try NSXMLElement(XMLString: "<page name=\"\(Playground.pageName)\"/>")
            pagesNode.addChild(pageNode)
            
            let data = contentsXcplayground.XMLDataWithOptions(NSXMLNodePrettyPrint)
            try data.writeToURL(contentsXcplaygroundURL, options: .DataWritingAtomic)
        }
    }
    
    /// Array of unused page's url.
    /// If between creation and modification is less than 2 seconds, it is regarded unused.
    func unusedPages() throws -> [NSURL] {
        let fm = NSFileManager.defaultManager()
        let keys = [NSURLCreationDateKey, NSURLContentModificationDateKey]
        let urls = try fm.contentsOfDirectoryAtURL(pagesURL,
            includingPropertiesForKeys: keys,
            options: [.SkipsSubdirectoryDescendants, .SkipsHiddenFiles])
            .filter { $0.pathExtension == Playground.pagePathExtension }
            .filter {
                if let creationDate = try $0.resourceValuesForKeys(keys)[NSURLCreationDateKey] as? NSDate,
                    let info = try? $0.URLByAppendingPathComponent(Playground.contentsSwift)
                    .resourceValuesForKeys(keys),
                    let modificationDate = info[NSURLContentModificationDateKey] as? NSDate {
                        return modificationDate.timeIntervalSinceDate(creationDate) < Playground.regardedUnusedTimeInterval
                } else {
                    return false
                }
        }
        return urls.filter {
            $0 != pageURL // exclude adding page. It may happen by configuration of "pageNameDateFormat"
        }
    }
    
    /// Create new Playground
    func buildPlayground() throws {
        // create package
        let fm = NSFileManager.defaultManager()
        try fm.createDirectoryAtURL(baseURL, withIntermediateDirectories: true, attributes: nil)
        
        // create contents.xcplayground
        let contentsXcplayground = try NSXMLDocument(XMLString: Playground.contentsXcplaygroundXMLString, options: NSXMLDocumentTidyXML)
        if let playgroundNode = try contentsXcplayground.nodesForXPath("/playground").first as? NSXMLElement {
            let pagesNode = try NSXMLElement(XMLString: "<pages><page name=\"\(Playground.pageName)\"/></pages>")
            playgroundNode.addChild(pagesNode)
        }
        let data = contentsXcplayground.XMLDataWithOptions(NSXMLNodePrettyPrint)
        try data.writeToURL(contentsXcplaygroundURL, options: .DataWritingWithoutOverwriting)
        
        // add page
        try fm.createDirectoryAtURL(pageURL, withIntermediateDirectories: true, attributes: nil)
        try contentsSwiftData?.writeToURL(pageContentsSwiftURL, options: .DataWritingWithoutOverwriting)
    }
    
    /// Avoid added Page regarding unused.
    func checkMakeUsedIfFromServices() throws {
        if Playground.makeUsedIfFromServices,
            let modificationDate = try pageContentsSwiftURL.resourceValuesForKeys([NSURLContentModificationDateKey])[NSURLContentModificationDateKey] as? NSDate {
            let touchedDate = modificationDate.dateByAddingTimeInterval(Playground.regardedUnusedTimeInterval + 1)
            try pageContentsSwiftURL.setResourceValue(touchedDate, forKey: NSURLContentModificationDateKey)
        }
    }
}

extension Playground {
    // customizable
    static let defaultURL = defaults.URLForKey("defaultDirectory")
    static let targetPlatform = defaults.stringForKey("targetPlatform") ?? "osx"
    static let contentsSwiftDefault =  defaults.stringForKey("contentsSwiftString") ?? "var str = \"Hello, playground\""
    
    static let playgroundNamePrefix = defaults.stringForKey("playgroundNamePrefix") ?? "PlayNow-"
    static let playgroundNameDateFormat = defaults.stringForKey("playgroundNamePrefix") ?? "yyyyMMdd"
    // Restriction of Page name is tighter than filename.
    static let pageNamePrefix = defaults.stringForKey("pageNamePrefix") ?? ""
    static let pageNameDateFormat = defaults.stringForKey("pageNameDateFormat") ?? "HHmmss"
    static let makeUsedIfFromServices = defaults.objectForKey("makeUsedIfFromServices").flatMap { ($0 as? NSNumber)?.boolValue } ?? true
    static let waitSecondsBeforeOpeningPage = UInt32(max(defaults.integerForKey("waitSecondsBeforeOpeningPage"), 3))
    
    // constants
    static let pathExtension = "playground"
    static let contentsXcplayground = "contents.xcplayground"
    static let pagesPathExtension = "Pages"
    static let pagePathExtension = "xcplaygroundpage"
    static let contentsSwift = "Contents.swift"
    static let regardedUnusedTimeInterval: NSTimeInterval = 2.0
    
    // template
    static let contentsXcplaygroundXMLString = [
        "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>",
        "<playground version='6.0' target-platform='\(targetPlatform)' requires-full-environment='true'/>"
        ].joinWithSeparator("\n")
    
    static let defaults = NSUserDefaults.standardUserDefaults()
    static let now = NSDate()
    
    static let playgroundName = playgroundNamePrefix + now.stringWithFormat(playgroundNameDateFormat)
    static let playgroundPathComponent = [playgroundName, Playground.pathExtension].joinWithSeparator(".")
    static let pageName = Playground.sanitizePageName(pageNamePrefix + now.stringWithFormat(pageNameDateFormat))
    static let pagePathComponent = [pageName, Playground.pagePathExtension].joinWithSeparator(".")
    
    /// Replace some characters with "_".
    /// Restriction of Page name is tighter than filename.
    static func sanitizePageName(name: String) -> String {
        let regex = try! NSRegularExpression(pattern: "[\\\\:/]", options: [])
        let range = NSMakeRange(0, (name as NSString).length)
        return regex.stringByReplacingMatchesInString(name, options: [], range: range, withTemplate: "_")
    }
    
    /// Contents will `contents` parameter, defaults of "contentsSwiftString" or coded default.
    /// - Parameter contents: String?
    /// - Returns: NSData from contents adding header and footer
    static func contentsSwiftData(contents: String?) -> NSData? {
        return [
            "//: [Previous](@previous)",
            "",
            "import Foundation",
            "",
            contents ?? contentsSwiftDefault,
            "",
            "//: [Next](@next)"
            ].joinWithSeparator("\n").dataUsingEncoding(NSUTF8StringEncoding)
    }
    
    /// decide using which Playground and return it
    /// - Parameter fromURL: NSURL?
    /// - Returns: NSURL of Playground
    static func playgroundURL(fromURL url: NSURL?) throws -> NSURL {
        func isPlaygroundURL(url: NSURL) -> Bool {
            return url.pathExtension == Playground.pathExtension
        }
        
        func appendPlaygroundPathComponentToURL(url: NSURL) -> NSURL? {
            return url.URLByAppendingPathComponent(playgroundPathComponent, isDirectory: true)
        }
        
        func playgroundURLFromURL(url: NSURL) -> NSURL? {
            return isPlaygroundURL(url) ? url : appendPlaygroundPathComponentToURL(url)
        }
        
        var desktopURL: NSURL? {
            return NSFileManager.defaultManager().URLsForDirectory(.DesktopDirectory, inDomains: .UserDomainMask).first
        }
        
        if let playgroundURL = url.flatMap(playgroundURLFromURL) {
            return playgroundURL
        } else if let playgroundURL = defaultURL.flatMap(appendPlaygroundPathComponentToURL) {
            return playgroundURL
        } else if let playgroundURL = desktopURL.flatMap(appendPlaygroundPathComponentToURL) {
            return playgroundURL
        } else {
            throw Error.CantBuildPlaygroundURL
        }
    }
}
