import Cocoa
import FlutterMacOS
import ApplicationServices

// MARK: - Browser Detection Helpers

private let kBrowserBundleIdentifiers: Set<String> = [
    "com.google.Chrome",
    "com.microsoft.edgemac",
    "org.mozilla.firefox",
    "com.brave.Browser",
    "com.operasoftware.Opera",
    "com.apple.Safari"
]

private func isBrowserApp(_ app: NSRunningApplication) -> Bool {
    guard let bundleId = app.bundleIdentifier else { return false }
    return kBrowserBundleIdentifiers.contains(bundleId)
}

private func browserType(for bundleId: String?) -> String {
    switch bundleId {
    case "com.google.Chrome": return "chrome"
    case "com.microsoft.edgemac": return "edge"
    case "org.mozilla.firefox": return "firefox"
    case "com.brave.Browser": return "brave"
    case "com.operasoftware.Opera": return "opera"
    case "com.apple.Safari": return "safari"
    default: return "browser"
    }
}

// MARK: - URL Extraction via AppleScript (macOS Browsers)

/// Attempt to obtain the full URL of the front-most tab for common macOS browsers
/// using AppleScript. Returns `nil` if the browser is not supported, the script
/// fails, or the URL is empty.
private func frontTabURL(for bundleId: String?) -> String? {
    guard let bundleId = bundleId else { 
        #if DEBUG
        print("[DEBUG] frontTabURL: bundleId is nil")
        #endif
        return nil 
    }

    #if DEBUG
    print("[DEBUG] frontTabURL: Processing bundleId: \(bundleId)")
    #endif

    // Map bundle identifier → AppleScript application name and script snippet
    let mapping: [String: (appName: String, script: String)] = [
        "com.google.Chrome":      ("Google Chrome", "return URL of active tab of front window"),
        "com.microsoft.edgemac":  ("Microsoft Edge", "return URL of active tab of front window"),
        "com.brave.Browser":      ("Brave Browser", "return URL of active tab of front window"),
        // Safari's scripting interface is different
        "com.apple.Safari":       ("Safari", "return URL of front document")
    ]

    guard let entry = mapping[bundleId] else { 
        #if DEBUG
        print("[DEBUG] frontTabURL: No AppleScript mapping found for bundleId: \(bundleId)")
        #endif
        return nil 
    }

    let source = """
    tell application \"\(entry.appName)\"
      try
        if (count of windows) = 0 then return ""
        \(entry.script)
      on error errMsg number errNum
        return "ERROR:" & errMsg & ":" & (errNum as string)
      end try
    end tell
    """

    #if DEBUG
    print("[DEBUG] frontTabURL: Executing AppleScript for \(entry.appName)")
    #endif

    var errorInfo: NSDictionary?
    if let script = NSAppleScript(source: source) {
        let output = script.executeAndReturnError(&errorInfo)
        
        if let errorDict = errorInfo {
            #if DEBUG
            print("[DEBUG] frontTabURL: AppleScript error: \(errorDict)")
            #endif
            return nil
        }
        
        if let urlString = output.stringValue, !urlString.isEmpty {
            #if DEBUG
            print("[DEBUG] frontTabURL: AppleScript returned: '\(urlString)'")
            #endif
            
            // Check if it's an error message
            if urlString.hasPrefix("ERROR:") {
                #if DEBUG
                print("[DEBUG] frontTabURL: AppleScript returned error: \(urlString)")
                #endif
                return nil
            }
            
            if let base = sanitizeURL(urlString) { 
                #if DEBUG
                print("[DEBUG] frontTabURL: Sanitized URL: '\(base)'")
                #endif
                return base 
            } else {
                #if DEBUG
                print("[DEBUG] frontTabURL: Failed to sanitize URL: '\(urlString)'")
                #endif
            }
        } else {
            #if DEBUG
            print("[DEBUG] frontTabURL: AppleScript returned empty or nil string")
            #endif
        }
    } else {
        #if DEBUG
        print("[DEBUG] frontTabURL: Failed to create NSAppleScript")
        #endif
    }

    // Fallback: try Accessibility tree (AXWebArea -> AXURL)
    #if DEBUG
    print("[DEBUG] frontTabURL: Falling back to Accessibility API")
    #endif
    
    if let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier {
        if let axURL = urlFromAXTree(for: pid) {
            #if DEBUG
            print("[DEBUG] frontTabURL: Accessibility API returned: '\(axURL)'")
            #endif
            return axURL
        } else {
            #if DEBUG
            print("[DEBUG] frontTabURL: Accessibility API returned nil")
            #endif
        }
    } else {
        #if DEBUG
        print("[DEBUG] frontTabURL: Could not get frontmost application PID")
        #endif
    }

    #if DEBUG
    print("[DEBUG] frontTabURL: All methods failed, returning nil")
    #endif
    return nil
}

/// Reduce full URL to base origin
private func sanitizeURL(_ urlString: String) -> String? {
    if let parsed = URL(string: urlString), let host = parsed.host {
        var base = ""
        if let scheme = parsed.scheme { base = "\(scheme)://\(host)" } else { base = host }
        if let port = parsed.port { base += ":\(port)" }
        return base
    }
    if let range = urlString.range(of: "[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}", options: .regularExpression) {
        return "https://" + urlString[range]
    }
    return nil
}

/// Traverse Accessibility tree to find AXWebArea and fetch AXURL.
private func urlFromAXTree(for pid: pid_t) -> String? {
    #if DEBUG
    print("[DEBUG] urlFromAXTree: Starting traversal for PID: \(pid)")
    #endif
    
    let appElement = AXUIElementCreateApplication(pid)
    var window: CFTypeRef?
    let result = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &window)
    
    guard result == .success, let win = window else { 
        #if DEBUG
        print("[DEBUG] urlFromAXTree: Failed to get focused window, result: \(result.rawValue)")
        #endif
        return nil 
    }
    
    #if DEBUG
    print("[DEBUG] urlFromAXTree: Successfully got focused window, starting traversal")
    #endif
    
    if let urlString = traverseForAXURL(element: win as! AXUIElement) {
        #if DEBUG
        print("[DEBUG] urlFromAXTree: Found URL in AX tree: '\(urlString)'")
        #endif
        return sanitizeURL(urlString)
    } else {
        #if DEBUG
        print("[DEBUG] urlFromAXTree: No URL found in AX tree")
        #endif
    }
    return nil
}

private func traverseForAXURL(element: AXUIElement) -> String? {
    // Check if element is AXWebArea and has AXURL
    var role: CFTypeRef?
    if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role) == .success,
       let roleStr = role as? String {
        
        #if DEBUG
        // Only log web areas to reduce noise
        if roleStr == "AXWebArea" {
            print("[DEBUG] traverseForAXURL: Found AXWebArea element")
        }
        #endif
        
        if roleStr == "AXWebArea" {
            var urlVal: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXURLAttribute as CFString, &urlVal) == .success,
               let urlStr = urlVal as? String, !urlStr.isEmpty {
                #if DEBUG
                print("[DEBUG] traverseForAXURL: AXWebArea has AXURL: '\(urlStr)'")
                #endif
                return urlStr
            } else {
                #if DEBUG
                print("[DEBUG] traverseForAXURL: AXWebArea found but no AXURL attribute")
                #endif
            }
        }
    }

    // Recurse into children
    var children: CFTypeRef?
    if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success,
       let arr = children as? [AXUIElement] {
        
        #if DEBUG
        // Only log if we have a reasonable number of children to avoid spam
        if arr.count > 0 && arr.count < 20 {
            print("[DEBUG] traverseForAXURL: Examining \(arr.count) child elements")
        }
        #endif
        
        for child in arr {
            if let found = traverseForAXURL(element: child) { 
                return found 
            }
        }
    }
    return nil
}
// Retrieve the window title of the focused window for a given app
private func windowTitle(for app: NSRunningApplication) -> String? {
    let axApp = AXUIElementCreateApplication(app.processIdentifier)
    var value: CFTypeRef?
    let result = AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &value)
    guard result == .success, let window = value else {
        return nil
    }
    var titleValue: CFTypeRef?
    if AXUIElementCopyAttributeValue(window as! AXUIElement, kAXTitleAttribute as CFString, &titleValue) == .success,
       let title = titleValue as? String {
        return title
    }
    return nil
}

// Extract cleaned page title from a raw window title string
private func cleanedPageTitle(from windowTitle: String) -> String {
    let patterns = [
        "(.+?)\\s*-\\s*Google Chrome",
        "(.+?)\\s*-\\s*Microsoft Edge",
        "(.+?)\\s*-\\s*Brave",
        "(.+?)\\s*-\\s*Mozilla Firefox",
        "(.+?)\\s*-\\s*Opera",
        "(.+?)\\s*-\\s*Safari"
    ]
    for pattern in patterns {
        if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
            if let match = regex.firstMatch(in: windowTitle, options: [], range: NSRange(windowTitle.startIndex..., in: windowTitle)), match.numberOfRanges > 1 {
                let range = match.range(at: 1)
                if let swiftRange = Range(range, in: windowTitle) {
                    return String(windowTitle[swiftRange]).trimmingCharacters(in: .whitespaces)
                }
            }
        }
    }
    return windowTitle
}

// Extract domain from title if any
private func extractDomain(from title: String) -> String? {
    let pattern = "(?:https?://)?(?:www\\.)?([a-zA-Z0-9.-]+\\.[a-zA-Z]{2,})"
    guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
    if let match = regex.firstMatch(in: title, options: [], range: NSRange(title.startIndex..., in: title)), match.numberOfRanges > 1 {
        let range = match.range(at: 1)
        if let swiftRange = Range(range, in: title) {
            return String(title[swiftRange])
        }
    }
    return nil
}

// MARK: - Focus Tracker Configuration

private struct FocusTrackerConfig {
    let updateIntervalMs: Int
    let includeMetadata: Bool
    let includeSystemApps: Bool
    let enableBrowserTabTracking: Bool
    let excludedApps: Set<String>
    let includedApps: Set<String>
    let enableBatching: Bool
    let maxBatchSize: Int
    let maxBatchWaitMs: Int
    
    static func fromJson(_ json: [String: Any]) -> FocusTrackerConfig {
        return FocusTrackerConfig(
            updateIntervalMs: json["updateIntervalMs"] as? Int ?? 1000,
            includeMetadata: json["includeMetadata"] as? Bool ?? false,
            includeSystemApps: json["includeSystemApps"] as? Bool ?? false,
            enableBrowserTabTracking: json["enableBrowserTabTracking"] as? Bool ?? false,
            excludedApps: Set((json["excludedApps"] as? [String]) ?? []),
            includedApps: Set((json["includedApps"] as? [String]) ?? []),
            enableBatching: json["enableBatching"] as? Bool ?? false,
            maxBatchSize: json["maxBatchSize"] as? Int ?? 10,
            maxBatchWaitMs: json["maxBatchWaitMs"] as? Int ?? 5000
        )
    }
    
    func toJson() -> [String: Any] {
        return [
            "updateIntervalMs": updateIntervalMs,
            "includeMetadata": includeMetadata,
            "includeSystemApps": includeSystemApps,
            "enableBrowserTabTracking": enableBrowserTabTracking,
            "excludedApps": Array(excludedApps),
            "includedApps": Array(includedApps),
            "enableBatching": enableBatching,
            "maxBatchSize": maxBatchSize,
            "maxBatchWaitMs": maxBatchWaitMs
        ]
    }
}

extension FocusTrackerConfig {
    /// Convenience initializer used when only the `includeSystemApps` flag needs to be specified.
    /// All other values are set to sensible defaults.
    init(includeSystemApps: Bool) {
        self.init(
            updateIntervalMs: 1000,
            includeMetadata: false,
            includeSystemApps: includeSystemApps,
            enableBrowserTabTracking: false,
            excludedApps: [],
            includedApps: [],
            enableBatching: false,
            maxBatchSize: 10,
            maxBatchWaitMs: 5000
        )
    }
}

// MARK: - Browser Tab Info Model

private struct BrowserTabInfo {
    let domain: String?
    let url: String?
    let title: String
    let browserType: String
    
    init(domain: String?, url: String?, title: String, browserType: String) {
        self.domain = domain
        self.url = url
        self.title = title
        self.browserType = browserType
    }
    
    static func fromJson(_ json: [String: Any]) -> BrowserTabInfo? {
        guard let title = json["title"] as? String,
              let browserType = json["browserType"] as? String else {
            return nil
        }
        
        return BrowserTabInfo(
            domain: json["domain"] as? String,
            url: json["url"] as? String,
            title: title,
            browserType: browserType
        )
    }
    
    func toJson() -> [String: Any] {
        var json: [String: Any] = [
            "title": title,
            "browserType": browserType
        ]
        
        if let domain = domain { json["domain"] = domain }
        if let url = url { json["url"] = url }
        
        return json
    }
}

public class AppFocusTrackerPlugin: NSObject, FlutterPlugin {
    private var eventSink: FlutterEventSink?
    private var currentFocusedApp: AppInfo?
    private var focusStartTime: Date?
    private var isTracking = false
    private var updateTimer: Timer?
    private var config: FocusTrackerConfig?
    private var sessionId: String?
    
    // Browser tab tracking
    private var lastBrowserTabInfo: [String: Any]?
    private var browserTabCheckTimer: Timer?
    
    // Event channel for streaming focus events
    private var eventChannel: FlutterEventChannel?
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = AppFocusTrackerPlugin()
        
        // Register method channel for platform interface calls
        let methodChannel = FlutterMethodChannel(
            name: "app_focus_tracker_method",
            binaryMessenger: registrar.messenger
        )
        registrar.addMethodCallDelegate(instance, channel: methodChannel)
        
        // Register event channel for focus event streaming
        instance.eventChannel = FlutterEventChannel(
            name: "app_focus_tracker_events",
            binaryMessenger: registrar.messenger
        )
        instance.eventChannel?.setStreamHandler(instance)
    }
    
    // MARK: - Method Channel Handling
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "getPlatformName":
            result("macOS")
            
        case "isSupported":
            result(true)
            
        case "hasPermissions":
            result(hasAccessibilityPermissions())
            
        case "requestPermissions":
            requestAccessibilityPermissions()
            result(hasAccessibilityPermissions())
            
        case "openSystemSettings":
            openSystemPreferences()
            result(nil)
            
        case "startTracking":
            if let args = call.arguments as? [String: Any],
               let configData = args["config"] as? [String: Any] {
                let config = parseFocusTrackerConfig(configData)
                startTracking(with: config, result: result)
            } else {
                result(FlutterError(code: "INVALID_ARGS", message: "Invalid configuration", details: nil))
            }
            
        case "stopTracking":
            stopTracking()
            result(nil)
            
        case "isTracking":
            result(isTracking)
            
        case "getCurrentFocusedApp":
            getCurrentFocusedApp(result: result)
            
        case "getRunningApplications":
            let includeSystemApps = (call.arguments as? [String: Any])?["includeSystemApps"] as? Bool ?? false
            getRunningApplications(includeSystemApps: includeSystemApps, result: result)
            
        case "getDiagnosticInfo":
            getDiagnosticInfo(result: result)
            
        case "debugUrlExtraction":
            debugUrlExtraction(result: result)
            
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    // MARK: - Permission Handling
    
    private func hasAccessibilityPermissions() -> Bool {
        return AXIsProcessTrusted()
    }
    
    private func requestAccessibilityPermissions() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true]
        AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
    
    private func openSystemPreferences() {
        // Open System Preferences to the Accessibility section
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        } else {
            // Fallback: open general System Preferences
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Library/PreferencePanes/Security.prefPane"))
        }
    }
    
    // MARK: - Focus Tracking Implementation
    
    private func startTracking(with config: FocusTrackerConfig, result: @escaping FlutterResult) {
        guard hasAccessibilityPermissions() else {
            result(FlutterError(
                code: "PERMISSION_DENIED",
                message: "Accessibility permissions are required for focus tracking",
                details: nil
            ))
            return
        }
        
        guard !isTracking else {
            result(FlutterError(
                code: "ALREADY_TRACKING",
                message: "Focus tracking is already active",
                details: nil
            ))
            return
        }
        
        self.config = config
        self.sessionId = generateSessionId()
        self.isTracking = true
        
        setupFocusNotifications()
        startPeriodicUpdates()
        
        // Send initial focus event for currently active app
        sendCurrentFocusEvent()
        
        result(nil)
    }
    
    private func stopTracking() {
        guard isTracking else { return }
        
        isTracking = false
        removeFocusNotifications()
        stopPeriodicUpdates()
        
        // Send final focus lost event
        if let currentApp = currentFocusedApp, let startTime = focusStartTime {
            sendFocusEvent(for: currentApp, eventType: .lost, duration: Date().timeIntervalSince(startTime))
        }
        
        currentFocusedApp = nil
        focusStartTime = nil
        sessionId = nil
        config = nil
    }
    
    private func setupFocusNotifications() {
        // Register for app activation notifications
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(appDidActivate(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        
        // Register for app deactivation notifications
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(appDidDeactivate(_:)),
            name: NSWorkspace.didDeactivateApplicationNotification,
            object: nil
        )
    }
    
    private func removeFocusNotifications() {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        stopPeriodicUpdates()
    }
    
    @objc private func appDidActivate(_ notification: Notification) {
        guard isTracking else { return }
        
        if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
            handleAppFocusGained(app)
        }
    }
    
    @objc private func appDidDeactivate(_ notification: Notification) {
        guard isTracking else { return }
        
        if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
            handleAppFocusLost(app)
        }
    }
    
    private func handleAppFocusGained(_ app: NSRunningApplication) {
        let appInfo = createAppInfo(from: app)
        
        // Send focus lost event for previous app
        if let currentApp = currentFocusedApp, let startTime = focusStartTime {
            let duration = Date().timeIntervalSince(startTime)
            sendFocusEvent(for: currentApp, eventType: .lost, duration: duration)
        }
        
        // Update current focus
        currentFocusedApp = appInfo
        focusStartTime = Date()
        
        // Send focus gained event
        sendFocusEvent(for: appInfo, eventType: .gained, duration: 0)
    }
    
    private func handleAppFocusLost(_ app: NSRunningApplication) {
        guard let currentApp = currentFocusedApp,
              currentApp.identifier == app.bundleIdentifier else { return }
        
        if let startTime = focusStartTime {
            let duration = Date().timeIntervalSince(startTime)
            sendFocusEvent(for: currentApp, eventType: .lost, duration: duration)
        }
        
        currentFocusedApp = nil
        focusStartTime = nil
    }
    
    private func startPeriodicUpdates() {
        guard let config = config else { return }
        
        let interval = TimeInterval(config.updateIntervalMs) / 1000.0
        updateTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.sendPeriodicUpdate()
        }
        
        // Start browser tab change detection if enabled
        if config.includeMetadata && config.enableBrowserTabTracking {
            startBrowserTabTracking()
        }
    }
    
    private func stopPeriodicUpdates() {
        updateTimer?.invalidate()
        updateTimer = nil
        
        // Stop browser tab tracking
        stopBrowserTabTracking()
    }
    
    @objc private func sendPeriodicUpdate() {
        guard isTracking,
              let currentApp = currentFocusedApp,
              let startTime = focusStartTime else { return }
        
        let duration = Date().timeIntervalSince(startTime)
        sendFocusEvent(for: currentApp, eventType: .durationUpdate, duration: duration)
    }
    
    // MARK: - Browser Tab Change Detection
    
    private func startBrowserTabTracking() {
        // Check for browser tab changes every 500ms when a browser is focused
        browserTabCheckTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkForBrowserTabChanges()
        }
    }
    
    private func stopBrowserTabTracking() {
        browserTabCheckTimer?.invalidate()
        browserTabCheckTimer = nil
        lastBrowserTabInfo = nil
    }
    
    private func checkForBrowserTabChanges() {
        // Ensure we are actively tracking
        guard isTracking else {
            lastBrowserTabInfo = nil
            return
        }

        // Re-evaluate the front-most application on every tick so that we
        // capture tab title changes that occur without a full app focus
        // change (e.g. switching tabs in the same browser window).
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else {
            lastBrowserTabInfo = nil
            return
        }

        // Build a fresh AppInfo snapshot for the current front-most app.
        let currentApp = createAppInfo(from: frontmostApp)

        // Only proceed if the focused application is a recognised browser.
        guard currentApp.isBrowser else {
            lastBrowserTabInfo = nil
            return
        }

        // Get current browser tab info
        guard let currentTabInfo = currentApp.browserTab else {
            lastBrowserTabInfo = nil
            return
        }
        
        // Check if tab info has changed
        if let lastTab = lastBrowserTabInfo {
            let currentTab = currentTabInfo.toJson()
            
            // Compare tab information
            if !tabsAreEqual(lastTab, currentTab) {
                // Tab has changed, send tab change event
                sendBrowserTabChangeEvent(
                    for: currentApp,
                    previousTab: lastTab,
                    currentTab: currentTab
                )
                lastBrowserTabInfo = currentTab
            }
        } else {
            // First time seeing this tab, just store it
            lastBrowserTabInfo = currentTabInfo.toJson()
        }
    }
    
    private func tabsAreEqual(_ tab1: [String: Any], _ tab2: [String: Any]) -> Bool {
        // Prefer comparing by domain (or url) because page titles can change
        // frequently within the same tab (e.g., live-price updates) and we do
        // not want to treat those as separate focus events.

        if let d1 = tab1["domain"] as? String, !d1.isEmpty,
           let d2 = tab2["domain"] as? String, !d2.isEmpty {
            return d1 == d2
        }

        if let u1 = tab1["url"] as? String, !u1.isEmpty,
           let u2 = tab2["url"] as? String, !u2.isEmpty {
            return u1 == u2
        }

        // Fallback: if neither domain nor url exists, fall back to full title
        // but strip dynamic parts like numbers to reduce false positives.
        let sanitize: (String) -> String = { str in
            // Remove all digits and commas/dots that typically vary in live titles
            return str.replacingOccurrences(of: "[0-9.,]+", with: "", options: .regularExpression)
                      .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let title1 = sanitize(tab1["title"] as? String ?? "")
        let title2 = sanitize(tab2["title"] as? String ?? "")
        return title1 == title2
    }
    
    private func sendBrowserTabChangeEvent(for app: AppInfo, previousTab: [String: Any], currentTab: [String: Any]) {
        // Treat tab change as a focus switch within the same application.

        // Send focus-lost event for the previous tab using the last known
        // focused app metadata (if available).
        if let startTime = focusStartTime {
            let duration = Date().timeIntervalSince(startTime)
            sendFocusEvent(for: currentFocusedApp ?? app, eventType: .lost, duration: duration)
        }

        // Update internal focus tracking to point at the new tab.
        currentFocusedApp = app
        focusStartTime = Date()

        // Send focus-gained event for the newly selected tab.
        sendFocusEvent(for: app, eventType: .gained, duration: 0)
    }
    
    private func sendCurrentFocusEvent() {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else { return }
        
        let appInfo = createAppInfo(from: frontmostApp)
        currentFocusedApp = appInfo
        focusStartTime = Date()
        
        sendFocusEvent(for: appInfo, eventType: .gained, duration: 0)
    }
    
    private func sendFocusEvent(for appInfo: AppInfo, eventType: FocusEventType, duration: TimeInterval) {
        guard let config = config,
              shouldTrackApp(appInfo, config: config) else { return }
        
        let durationMicroseconds = Int(duration * 1_000_000)
        let timestamp = Date()
        
        let focusEvent = FocusEvent(
            appName: appInfo.name,
            appIdentifier: appInfo.identifier,
            timestamp: timestamp,
            durationMicroseconds: durationMicroseconds,
            processId: appInfo.processId,
            eventType: eventType,
            sessionId: sessionId,
            metadata: config.includeMetadata ? appInfo.metadata : nil
        )
        
        eventSink?(focusEvent.toJson())
    }
    
    // MARK: - App Information Extraction
    
    private func createAppInfo(from app: NSRunningApplication) -> AppInfo {
        let name = app.localizedName ?? app.bundleIdentifier ?? "Unknown"
        let identifier = app.bundleIdentifier ?? app.executableURL?.path ?? "unknown"
        let processId = Int(app.processIdentifier)
        
        let rawWindowTitle = windowTitle(for: app)
        let displayName: String
        if let wTitle = rawWindowTitle, !wTitle.isEmpty {
            displayName = wTitle
        } else {
            displayName = name
        }
        var metadata: [String: Any] = [:]
        metadata["bundleURL"] = app.bundleURL?.path
        metadata["executableURL"] = app.executableURL?.path
        metadata["launchDate"] = app.launchDate?.timeIntervalSince1970
        metadata["isTerminated"] = app.isTerminated
        metadata["isHidden"] = app.isHidden
        metadata["activationPolicy"] = app.activationPolicy.rawValue
        if let w = rawWindowTitle { metadata["windowTitle"] = w }

        let browserFlag = isBrowserApp(app)
        metadata["isBrowser"] = browserFlag
        if browserFlag, let wTitle = rawWindowTitle {
            let pageTitle = cleanedPageTitle(from: wTitle)

            // Try high-accuracy URL via AppleScript first
            let fullURL = frontTabURL(for: app.bundleIdentifier)

            // Derive domain
            var derivedDomain: String? = nil
            if let u = fullURL, let host = URL(string: u)?.host {
                derivedDomain = host
            } else {
                derivedDomain = extractDomain(from: pageTitle)
            }

            // Build tab metadata
            var tabInfo: [String: Any] = [
                "title": pageTitle,
                "browserType": browserType(for: app.bundleIdentifier)
            ]

            if let url = fullURL { tabInfo["url"] = url }
            if let d = derivedDomain { tabInfo["domain"] = d }

            metadata["browserTab"] = tabInfo
        }

        // Get app version if available
        var version: String?
        if let bundleURL = app.bundleURL,
           let bundle = Bundle(url: bundleURL) {
            version = bundle.infoDictionary?["CFBundleShortVersionString"] as? String
            metadata["bundleVersion"] = bundle.infoDictionary?["CFBundleVersion"]
        }

        // Get app icon path if available
        var iconPath: String?
        if let bundleURL = app.bundleURL {
            let iconFile = bundleURL.appendingPathComponent("Contents/Resources/AppIcon.icns")
            if FileManager.default.fileExists(atPath: iconFile.path) {
                iconPath = iconFile.path
            }
        }

        return AppInfo(
            name: displayName,
            identifier: identifier,
            processId: processId,
            version: version,
            iconPath: iconPath,
            executablePath: app.executableURL?.path,
            metadata: metadata
        )
    }
    
    private func shouldTrackApp(_ appInfo: AppInfo, config: FocusTrackerConfig) -> Bool {
        // Check excluded apps
        if config.excludedApps.contains(appInfo.identifier) {
            return false
        }
        
        // Check included apps (if specified)
        if !config.includedApps.isEmpty && !config.includedApps.contains(appInfo.identifier) {
            return false
        }
        
        // Check system apps
        if !config.includeSystemApps {
            // Filter out common system apps
            let systemApps = [
                "com.apple.finder",
                "com.apple.dock",
                "com.apple.systempreferences",
                "com.apple.controlstrip",
                "com.apple.notificationcenterui"
            ]
            if systemApps.contains(appInfo.identifier) {
                return false
            }
        }
        
        return true
    }
    
    // MARK: - Platform Interface Methods
    
    private func getCurrentFocusedApp(result: @escaping FlutterResult) {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else {
            result(nil)
            return
        }
        
        let appInfo = createAppInfo(from: frontmostApp)
        result(appInfo.toJson())
    }
    
    private func getRunningApplications(includeSystemApps: Bool, result: @escaping FlutterResult) {
        let runningApps = NSWorkspace.shared.runningApplications
        var appInfoList: [[String: Any]] = []
        
        for app in runningApps {
            let appInfo = createAppInfo(from: app)
            
            if !includeSystemApps {
                let config = FocusTrackerConfig(includeSystemApps: false)
                if !shouldTrackApp(appInfo, config: config) {
                    continue
                }
            }
            
            appInfoList.append(appInfo.toJson())
        }
        
        result(appInfoList)
    }
    
    private func getDiagnosticInfo(result: @escaping FlutterResult) {
        var diagnostics: [String: Any] = [:]
        
        diagnostics["platform"] = "macOS"
        diagnostics["isTracking"] = isTracking
        diagnostics["hasPermissions"] = hasAccessibilityPermissions()
        diagnostics["sessionId"] = sessionId
        diagnostics["config"] = config?.toJson()
        diagnostics["currentApp"] = currentFocusedApp?.toJson()
        diagnostics["focusStartTime"] = focusStartTime?.timeIntervalSince1970
        diagnostics["systemVersion"] = ProcessInfo.processInfo.operatingSystemVersionString
        
        result(diagnostics)
    }
    
    private func debugUrlExtraction(result: @escaping FlutterResult) {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else {
            result(["error": "No frontmost application"])
            return
        }
        
        var debugInfo: [String: Any] = [:]
        
        debugInfo["bundleIdentifier"] = frontmostApp.bundleIdentifier
        debugInfo["processName"] = frontmostApp.localizedName
        debugInfo["processId"] = frontmostApp.processIdentifier
        
        let isBrowser = isBrowserApp(frontmostApp)
        debugInfo["isBrowser"] = isBrowser
        
        if isBrowser {
            // Test AppleScript extraction
            let applescriptUrl = frontTabURL(for: frontmostApp.bundleIdentifier)
            debugInfo["applescriptUrl"] = applescriptUrl
            
            // Test Accessibility API extraction
            let axUrl = urlFromAXTree(for: frontmostApp.processIdentifier)
            debugInfo["accessibilityUrl"] = axUrl
            
            // Test window title extraction
            if let windowTitle = windowTitle(for: frontmostApp) {
                debugInfo["windowTitle"] = windowTitle
                
                let pageTitle = cleanedPageTitle(from: windowTitle)
                let extractedDomain = extractDomain(from: pageTitle)
                
                debugInfo["titleExtraction"] = [
                    "rawTitle": windowTitle,
                    "cleanedTitle": pageTitle,
                    "extractedDomain": extractedDomain,
                    "browserType": browserType(for: frontmostApp.bundleIdentifier)
                ]
            } else {
                debugInfo["windowTitle"] = nil
                debugInfo["titleExtraction"] = ["error": "Could not get window title"]
            }
        }
        
        result(debugInfo)
    }
    
    // MARK: - Helper Methods
    
    private func parseFocusTrackerConfig(_ data: [String: Any]) -> FocusTrackerConfig {
        return FocusTrackerConfig.fromJson(data)
    }
    
    private func generateSessionId() -> String {
        return "session_\(Date().timeIntervalSince1970)_\(arc4random())"
    }
}

// MARK: - FlutterStreamHandler

extension AppFocusTrackerPlugin: FlutterStreamHandler {
    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = events
        return nil
    }
    
    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        self.eventSink = nil
        return nil
    }
}

// MARK: - Data Models

private struct AppInfo {
    let name: String
    let identifier: String
    let processId: Int?
    let version: String?
    let iconPath: String?
    let executablePath: String?
    let metadata: [String: Any]?
    
    var isBrowser: Bool {
        return (metadata?["isBrowser"] as? Bool) ?? false
    }
    
    var browserTab: BrowserTabInfo? {
        guard let tabData = metadata?["browserTab"] as? [String: Any] else { return nil }
        return BrowserTabInfo.fromJson(tabData)
    }
    
    func toJson() -> [String: Any] {
        var json: [String: Any] = [
            "name": name,
            "identifier": identifier
        ]
        
        if let processId = processId { json["processId"] = processId }
        if let version = version { json["version"] = version }
        if let iconPath = iconPath { json["iconPath"] = iconPath }
        if let executablePath = executablePath { json["executablePath"] = executablePath }
        if let metadata = metadata { json["metadata"] = metadata }
        
        return json
    }
}

private struct FocusEvent {
    let appName: String
    let appIdentifier: String?
    let timestamp: Date
    let durationMicroseconds: Int
    let processId: Int?
    let eventType: FocusEventType
    let sessionId: String?
    let metadata: [String: Any]?
    
    func toJson() -> [String: Any] {
        var json: [String: Any] = [
            "appName": appName,
            "timestamp": Int(timestamp.timeIntervalSince1970 * 1_000_000),
            "durationMicroseconds": durationMicroseconds,
            "eventType": eventType.rawValue,
            "eventId": "evt_\(Int(timestamp.timeIntervalSince1970 * 1_000_000))_\(arc4random())"
        ]
        
        if let appIdentifier = appIdentifier { json["appIdentifier"] = appIdentifier }
        if let processId = processId { json["processId"] = processId }
        if let sessionId = sessionId { json["sessionId"] = sessionId }
        if let metadata = metadata { json["metadata"] = metadata }
        
        return json
    }
}

private enum FocusEventType: String {
    case gained = "gained"
    case lost = "lost"
    case durationUpdate = "durationUpdate"
}
