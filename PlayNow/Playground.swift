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
    enum Error: Swift.Error, CustomStringConvertible {
        case cantBuildPlaygroundURL
        case versionOfPlaygroundCanNotBeDetected(playgroundName: String)
        case versionOfPlaygroundIsNotSupported(version: String, playgroundName: String)
        
        var NSError: Foundation.NSError {
            let domain = (self as Foundation.NSError).domain
            let code = (self as Foundation.NSError).code
            let userInfo = [ NSLocalizedDescriptionKey: description ]
            return Foundation.NSError(domain: domain, code: code, userInfo: userInfo)
        }
        
        var description: String {
            switch self {
            case .cantBuildPlaygroundURL:
                return "Can't build playground url."
            case .versionOfPlaygroundCanNotBeDetected(let playgroundName):
                return "PlayNow can not edit \"\(playgroundName)\"" +
                " because the version of Playground can not be detected."
            case .versionOfPlaygroundIsNotSupported(let version, let playgroundName):
                return "PlayNow can not edit \"\(playgroundName)\"" +
                " because the version \"\(version)\" of Playground  is not supported."
            }
        }
    }
    
    let baseURL: URL
    let contentsSwiftData: Data?
    init(fileURL: URL?, contentsSwift: String? = nil) throws {
        baseURL = try Playground.playgroundURL(fromURL: fileURL)
        contentsSwiftData = Playground.contentsSwiftData(contentsSwift)
    }
    
    var contentsXcplaygroundURL: URL {
        return baseURL.appendingPathComponent(Playground.contentsXcplayground)
    }
    
    var pagesURL: URL {
        return baseURL.appendingPathComponent(Playground.pagesPath, isDirectory: true)
    }
    
    var pageURL: URL {
        return pagesURL.appendingPathComponent(Playground.pagePathComponent, isDirectory: true)
    }
    
    var pageContentsSwiftURL: URL {
        return pageURL.appendingPathComponent(Playground.contentsSwift)
    }

    @discardableResult
    func update() throws -> Playground {
        // check existence of contents.xcplayground
        if contentsXcplaygroundURL.fileURLExists {
            try addPageToPlayground()
            
            // open playground.
            let app = try Playground.openURL(baseURL, andActivate: false)
            
            // wait until finishedLaunching if openURL() launching Xcode
            while !app.isFinishedLaunching {
                RunLoop.current.run(until: Date(timeIntervalSinceNow: 1))
            }
            // wait 3+ seconds for openURL() launching Xcode
            sleep(Playground.waitSecondsBeforeOpeningPage) // wait 3+ seconds
            
            // open page in playground
            try Playground.openURL(pageURL)
            
        } else { // file does not exist
            try buildPlayground()
            
            // open playground.
            try Playground.openURL(baseURL)
        }
        return self
    }
    
    /// add page to existing Playground
    func addPageToPlayground() throws {
        // check version
        let contentsXcplayground = try XMLDocument(contentsOf: contentsXcplaygroundURL, options: 0)
        guard let playgroundNode = try contentsXcplayground.nodes(forXPath: "/playground").first as? XMLElement,
            let version = playgroundNode.attribute(forName: "version")?.stringValue else {
                throw Error.versionOfPlaygroundCanNotBeDetected(playgroundName: baseURL.lastPathComponent)
        }
        if "6.0".compare(version, options:.numeric) == .orderedAscending {
            throw Error.versionOfPlaygroundIsNotSupported(version: version, playgroundName: baseURL.lastPathComponent)
        }
        
        // save unused pages before adding page
        let unusedPageURLs = try unusedPages()
        
        // add page
        let fm = FileManager.default
        try fm.createDirectory(at: pageURL, withIntermediateDirectories: true, attributes: nil)
        do {
            try contentsSwiftData?.write(to: pageContentsSwiftURL, options: .withoutOverwriting)
        } catch CocoaError.fileWriteFileExists {
            // ignore file exists error. It may happen by configuration of "pageNameDateFormat"
        }
        
        // remove unused pages
        do { try unusedPageURLs.forEach(fm.removeItem(at:)) } catch {}
        
        // update contents.xcplayground if "/playground/pages" exists
        if let pagesNode = try playgroundNode.nodes(forXPath: "./pages").first as? XMLElement {
            
            func basenameFromURL(_ url: URL) -> String? {
                return (url.lastPathComponent as NSString?)?.deletingPathExtension
            }
            
            // remove each unused page from pages node
            try unusedPageURLs.flatMap(basenameFromURL).forEach {
                try pagesNode.nodes(forXPath: "./page[@name=\"\($0)\"]").forEach {
                    $0.detach()
                }
            }
            
            // add page to pages node
            let pageNode = try XMLElement(xmlString: "<page name=\"\(Playground.pageName)\"/>")
            pagesNode.addChild(pageNode)
            
            let data = contentsXcplayground
                .perform(#selector(XMLDocument.xmlData(withOptions:)), with: XMLNode.Options.nodePrettyPrint.rawValue)
                .takeRetainedValue() as! Data
            try data.write(to: contentsXcplaygroundURL, options: .atomic)
        }
    }
    
    /// Array of unused page's url.
    /// If between creation and modification is less than 2 seconds, it is regarded unused.
    func unusedPages() throws -> [URL] {
        let fm = FileManager.default
        let keys = [URLResourceKey.creationDateKey, URLResourceKey.contentModificationDateKey]
        let urls = try fm.contentsOfDirectory(at: pagesURL,
            includingPropertiesForKeys: keys,
            options: [.skipsSubdirectoryDescendants, .skipsHiddenFiles])
            .filter { $0.pathExtension == Playground.pagePathExtension }
            .filter {
                if let creationDate = try ($0 as NSURL).resourceValues(forKeys: keys)[URLResourceKey.creationDateKey] as? Date,
                    let info = try? ($0.appendingPathComponent(Playground.contentsSwift) as NSURL)
                    .resourceValues(forKeys: keys),
                    let modificationDate = info[URLResourceKey.contentModificationDateKey] as? Date {
                        return modificationDate.timeIntervalSince(creationDate) < Playground.regardedUnusedTimeInterval
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
        let fm = FileManager.default
        try fm.createDirectory(at: baseURL, withIntermediateDirectories: true, attributes: nil)
        
        // create contents.xcplayground
        let contentsXcplayground = try XMLDocument(xmlString: Playground.contentsXcplaygroundXMLString, options: Int(XMLNode.Options.documentTidyXML.rawValue))
        if let playgroundNode = try contentsXcplayground.nodes(forXPath: "/playground").first as? XMLElement {
            let pagesNode = try XMLElement(xmlString: "<pages><page name=\"\(Playground.pageName)\"/></pages>")
            playgroundNode.addChild(pagesNode)
        }
        let data = contentsXcplayground
            .perform(#selector(XMLDocument.xmlData(withOptions:)), with: XMLNode.Options.nodePrettyPrint.rawValue)
            .takeRetainedValue() as! Data
        try data.write(to: contentsXcplaygroundURL, options: .withoutOverwriting)
        
        // add page
        try fm.createDirectory(at: pageURL, withIntermediateDirectories: true, attributes: nil)
        try contentsSwiftData?.write(to: pageContentsSwiftURL, options: .withoutOverwriting)
    }
    
    /// Avoid added Page regarding unused.
    func checkMakeUsedIfFromServices() throws {
        if Playground.makeUsedIfFromServices,
            let modificationDate = try (pageContentsSwiftURL as NSURL).resourceValues(forKeys: [URLResourceKey.contentModificationDateKey])[URLResourceKey.contentModificationDateKey] as? Date {
            let touchedDate = modificationDate.addingTimeInterval(Playground.regardedUnusedTimeInterval + 1)
            try (pageContentsSwiftURL as NSURL).setResourceValue(touchedDate, forKey: URLResourceKey.contentModificationDateKey)
        }
    }
}

extension Playground {
    // customizable
    static let defaultURL = defaults.url(forKey: "defaultDirectory")
    static let targetPlatform = defaults.string(forKey: "targetPlatform") ?? "osx"
    static let contentsSwiftDefault =  defaults.string(forKey: "contentsSwiftString") ?? "var str = \"Hello, playground\""
    
    static let playgroundNamePrefix = defaults.string(forKey: "playgroundNamePrefix") ?? "PlayNow-"
    static let playgroundNameDateFormat = defaults.string(forKey: "playgroundNamePrefix") ?? "yyyyMMdd"
    // Restriction of Page name is tighter than filename.
    static let pageNamePrefix = defaults.string(forKey: "pageNamePrefix") ?? ""
    static let pageNameDateFormat = defaults.string(forKey: "pageNameDateFormat") ?? "HHmmss"
    static let makeUsedIfFromServices = defaults.object(forKey: "makeUsedIfFromServices").flatMap { ($0 as? NSNumber)?.boolValue } ?? true
    static let waitSecondsBeforeOpeningPage = UInt32(max(defaults.integer(forKey: "waitSecondsBeforeOpeningPage"), 3))
    static let XcodeURL = defaults.url(forKey: "XcodePath")
    
    // constants
    static let pathExtension = "playground"
    static let contentsXcplayground = "contents.xcplayground"
    static let pagesPath = "Pages"
    static let pagePathExtension = "xcplaygroundpage"
    static let contentsSwift = "Contents.swift"
    static let regardedUnusedTimeInterval: TimeInterval = 2.0
    
    // template
    static let contentsXcplaygroundXMLString = [
        "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>",
        "<playground version='6.0' target-platform='\(targetPlatform)' requires-full-environment='true'/>"
        ].joined(separator: "\n")
    
    static let defaults = UserDefaults.standard
    static let now = Date()
    
    static let playgroundName = playgroundNamePrefix + now.stringWithFormat(playgroundNameDateFormat)
    static let playgroundPathComponent = [playgroundName, Playground.pathExtension].joined(separator: ".")
    static let pageName = Playground.sanitizePageName(pageNamePrefix + now.stringWithFormat(pageNameDateFormat))
    static let pagePathComponent = [pageName, Playground.pagePathExtension].joined(separator: ".")
    
    /// Replace some characters with "_".
    /// Restriction of Page name is tighter than filename.
    static func sanitizePageName(_ name: String) -> String {
        let regex = try! NSRegularExpression(pattern: "[\\\\:/]", options: [])
        let range = NSMakeRange(0, (name as NSString).length)
        return regex.stringByReplacingMatches(in: name, options: [], range: range, withTemplate: "_")
    }
    
    /// Contents will `contents` parameter, defaults of "contentsSwiftString" or coded default.
    /// - Parameter contents: String?
    /// - Returns: NSData from contents adding header and footer
    static func contentsSwiftData(_ contents: String?) -> Data? {
        return [
            "//: [Previous](@previous)",
            "",
            "import Foundation",
            "",
            contents ?? contentsSwiftDefault,
            "",
            "//: [Next](@next)"
            ].joined(separator: "\n").data(using: String.Encoding.utf8)
    }
    
    /// decide using which Playground and return it
    /// - Parameter fromURL: NSURL?
    /// - Returns: NSURL of Playground
    static func playgroundURL(fromURL url: URL?) throws -> URL {
        func isPlaygroundURL(_ url: URL) -> Bool {
            return url.pathExtension == Playground.pathExtension
        }
        
        func appendPlaygroundPathComponentToURL(_ url: URL) -> URL? {
            return url.appendingPathComponent(playgroundPathComponent, isDirectory: true)
        }
        
        func playgroundURLFromURL(_ url: URL) -> URL? {
            return isPlaygroundURL(url) ? url : appendPlaygroundPathComponentToURL(url)
        }
        
        var desktopURL: URL? {
            return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
        }
        
        if let playgroundURL = url.flatMap(playgroundURLFromURL) {
            return playgroundURL
        } else if let playgroundURL = defaultURL.flatMap(appendPlaygroundPathComponentToURL) {
            return playgroundURL
        } else if let playgroundURL = desktopURL.flatMap(appendPlaygroundPathComponentToURL) {
            return playgroundURL
        } else {
            throw Error.cantBuildPlaygroundURL
        }
    }
    
    /// open URL respect `XcodePath` setting
    /// - Parameter url: NSURL to open
    /// - Parameter andActivate: Bool
    /// - Returns: NSRunningApplication
    @discardableResult
    static func openURL(_ url: URL, andActivate activate: Bool = true) throws -> NSRunningApplication {
        let ws = NSWorkspace.shared()
        let options = activate ? [] : NSWorkspaceLaunchOptions.withoutActivation
        if let xcodeURL = Playground.XcodeURL {
            return try ws.open([url], withApplicationAt: xcodeURL, options: options, configuration: [:])
        } else {
            return try ws.open(url, options: options, configuration: [:])
        }
    }
}
