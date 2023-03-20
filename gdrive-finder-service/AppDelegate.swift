import SwiftUI
import os

class AppDelegate: NSObject, NSApplicationDelegate {
    var openedWithURL = false
    
    // Entry point when the application gets called by clicking on a gdrive:// url
    func application(_ application: NSApplication, open urls: [URL]) {
        openedWithURL = true
        
        for url in urls {
            handleGDriveURL(url)
        }
    }
    
    // Entry point when the application gets called by the context menu item under services
    @objc func handleFileService(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSDictionary?>) {
        guard let types = pboard.types, types.contains(.fileURL) else { return }

        if let urls = pboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
            for url in urls {
                if let customUrlScheme = transformFilePath(url.path) {
                    print(customUrlScheme)
                    
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(customUrlScheme, forType: .string)
                } else {
                    errorAlert(text: "Not a gdrive folder")
                }
            }
        }
    }
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        print("App launched")
    
        if !openedWithURL && !isInDebugMode() {
            print("Terminating because not launched by URL or Xcode")
            NSApp.terminate(nil)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        return true
    }
    
    func transformFilePath(_ path: String) -> String? {
        let components = path.components(separatedBy: "/")
        if let index = components.firstIndex(of: "CloudStorage") {
            let newPathComponents = ["gdrive:/"] + components[index...]
            let newPath = newPathComponents.joined(separator: "/")
            
            // Create a custom CharacterSet for encoding
            var customAllowedCharacters = CharacterSet.urlHostAllowed
            customAllowedCharacters.insert(charactersIn: ":/")
            
            return newPath.addingPercentEncoding(withAllowedCharacters: customAllowedCharacters)
        }
        return nil
    }
    
    func handleGDriveURL(_ url: URL) {
        // Convert the "gdrive://" URL back to the local file path
        if let localFilePath = gdriveURLToLocalFilePath(url) {
            print("Local file path:", localFilePath)
            let fileURL = localFilePath
            // Open the file in Finder
            NSWorkspace.shared.selectFile(fileURL.path, inFileViewerRootedAtPath: "")
            NSApp.terminate(nil)
        } else {
            print("Failed to convert GDrive URL to local file path")
        }
    }
    
    func isInDebugMode() -> Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    func errorAlert(text: String) {
        let alert = NSAlert()
        alert.messageText = "Error occured!"
        alert.informativeText = text
        alert.alertStyle = .critical
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
    
    func findMatchingGoogleDriveFolder(in cloudStorageDirectory: URL, domain: String) -> URL? {
        let fileManager = FileManager.default
        guard let contents = try? fileManager.contentsOfDirectory(at: cloudStorageDirectory, includingPropertiesForKeys: nil, options: []) else {
            return nil
        }

        for url in contents {
            print(url, domain)
            if url.lastPathComponent.contains(domain) {
                return url
            }
        }

        return nil
    }
    
    func gdriveURLToLocalFilePath(_ gdriveURL: URL) -> URL? {
        let urlString = gdriveURL.absoluteString
        let pattern = "gdrive://CloudStorage/(GoogleDrive-[^/]+)"
        let regex = try? NSRegularExpression(pattern: pattern, options: [])
        
        guard let match = regex?.firstMatch(in: urlString, options: [], range: NSRange(location: 0, length: urlString.utf16.count)),
              let matchedRange = Range(match.range(at: 1), in: urlString) else {
            print("No match found in gdrive URL")
            return nil
        }
        
        let googleDriveFolderName = String(urlString[matchedRange])
        let domain = googleDriveFolderName.components(separatedBy: "@").last?.removingPercentEncoding
        
        guard let unwrappedDomain = domain else {
            print("No domain found")
            return nil
        }
        
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
        let cloudStorageDirectory = homeDirectory.appendingPathComponent("Library/CloudStorage")
        
        guard let googleDriveFolder = findMatchingGoogleDriveFolder(in: cloudStorageDirectory, domain: unwrappedDomain) else {
            print("No matching Google Drive folder found")
            return nil
        }
        
        print("Google Drive folder found:", googleDriveFolder)
        
        let pathComponents = urlString[matchedRange.upperBound...]
            .split(separator: "/", omittingEmptySubsequences: false)
            .map { String($0) }
            .filter { !$0.isEmpty }
        
        let localFilePath = pathComponents.reduce(googleDriveFolder) { url, component in
            url.appendingPathComponent(component.removingPercentEncoding ?? component)
        }
        
        print("Local file path:", localFilePath)
        
        return localFilePath
    }
}
