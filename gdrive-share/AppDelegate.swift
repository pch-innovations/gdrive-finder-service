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
        
        NSApp.terminate(nil)
    }
    
    // Entry point when the application gets called by the context menu item under services
    @objc func handleFileService(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSDictionary?>) {
        openedWithURL = true
        
        guard let types = pboard.types, types.contains(.fileURL) else { return }

        if let urls = pboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
            for url in urls {
                if let customUrlScheme = transformFilePath(url.path) {
                    print(customUrlScheme)
                    
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(customUrlScheme, forType: .string)
                } else {
                    errorAlert(text: "Not a GDrive folder: " + url.absoluteString)
                }
            }
        }
        
        NSApp.terminate(nil)
    }
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        os_log("App launched")
        
        if !isInDebugMode() {
            let timeoutDuration: TimeInterval = 5
            Timer.scheduledTimer(withTimeInterval: timeoutDuration, repeats: false) { _ in
                os_log("Auto-Terminating gdrive-finder-service")
                NSApp.terminate(self)
            }
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
        os_log("Handling URL")
        // Convert the "gdrive://" URL back to the local file path
        if let localFilePath = gdriveURLToLocalFilePath(url) {
            print("Local file path:", localFilePath)
            let fileURL = localFilePath
            // Open the file in Finder
            if FileManager.default.fileExists(atPath: fileURL.path) {
                NSWorkspace.shared.selectFile(fileURL.path, inFileViewerRootedAtPath: "")
            } else {
                errorAlert(text: "Could not find '" + fileURL.absoluteString + "' on your device")
            }
        } else {
            errorAlert(text: "Could not convert '" + url.absoluteString + "' to local GDrive path")
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
        alert.messageText = "Oops!"
        alert.informativeText = text
        alert.alertStyle = .warning
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
        let domain = googleDriveFolderName.removingPercentEncoding?.components(separatedBy: "@").last
        
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
        
        // The following method does the following:
        // The top level directory "Shared Drives" can be translated into different languages, depending on the users language settings
        // So in order to circumvent having to know the specific translation of that directory
        // We iterate throught the top level directories after the google drive account folder and just try our path
        // with every folder in it and see if the file / folder is accesible
        // We drop the first part of our path component which is the language sensitive "Shared Drives"
        guard let sharedDrivesFolder = findSharedDrivesFolder(in: googleDriveFolder, withPathComponents: Array(pathComponents.dropFirst())) else {
            print("No matching Shared Drives folder found")
            return nil
        }
        
        let localFilePath = sharedDrivesFolder
        
        print("Local file path:", localFilePath)
        
        return localFilePath
    }
    
    func findSharedDrivesFolder(in googleDriveFolder: URL, withPathComponents pathComponents: [String]) -> URL? {
        let fileManager = FileManager.default
        do {
            let topLevelDirectories = try fileManager.contentsOfDirectory(at: googleDriveFolder, includingPropertiesForKeys: nil)

            for topLevelDirectory in topLevelDirectories {
                let potentialPath = pathComponents.reduce(topLevelDirectory) { url, component in
                    url.appendingPathComponent(component.removingPercentEncoding ?? component)
                }
                
                if fileManager.fileExists(atPath: potentialPath.path) {
                    return potentialPath
                }
            }
        } catch {
            print("Failed to enumerate directory:", error)
        }
        
        return nil
    }
}
