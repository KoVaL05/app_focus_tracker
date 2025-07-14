import Cocoa
import FlutterMacOS
import ApplicationServices

public class AppFocusTrackerPlugin: NSObject, FlutterPlugin {
    private var eventSink: FlutterEventSink?
    private var currentFocusedApp: AppInfo?
    private var focusStartTime: Date?
    private var isTracking = false
    private var updateTimer: Timer?
    private var config: FocusTrackerConfig?
    private var sessionId: String?
    
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
    }
    
    private func stopPeriodicUpdates() {
        updateTimer?.invalidate()
        updateTimer = nil
    }
    
    @objc private func sendPeriodicUpdate() {
        guard isTracking,
              let currentApp = currentFocusedApp,
              let startTime = focusStartTime else { return }
        
        let duration = Date().timeIntervalSince(startTime)
        sendFocusEvent(for: currentApp, eventType: .durationUpdate, duration: duration)
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
        
        var metadata: [String: Any] = [:]
        metadata["bundleURL"] = app.bundleURL?.path
        metadata["executableURL"] = app.executableURL?.path
        metadata["launchDate"] = app.launchDate?.timeIntervalSince1970
        metadata["isTerminated"] = app.isTerminated
        metadata["isHidden"] = app.isHidden
        metadata["activationPolicy"] = app.activationPolicy.rawValue
        
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
            name: name,
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

private struct FocusTrackerConfig {
    let updateIntervalMs: Int
    let includeMetadata: Bool
    let includeSystemApps: Bool
    let excludedApps: Set<String>
    let includedApps: Set<String>
    
    init(updateIntervalMs: Int = 1000,
         includeMetadata: Bool = false,
         includeSystemApps: Bool = false,
         excludedApps: Set<String> = [],
         includedApps: Set<String> = []) {
        self.updateIntervalMs = updateIntervalMs
        self.includeMetadata = includeMetadata
        self.includeSystemApps = includeSystemApps
        self.excludedApps = excludedApps
        self.includedApps = includedApps
    }
    
    static func fromJson(_ data: [String: Any]) -> FocusTrackerConfig {
        let updateIntervalMs = data["updateIntervalMs"] as? Int ?? 1000
        let includeMetadata = data["includeMetadata"] as? Bool ?? false
        let includeSystemApps = data["includeSystemApps"] as? Bool ?? false
        let excludedApps = Set((data["excludedApps"] as? [String]) ?? [])
        let includedApps = Set((data["includedApps"] as? [String]) ?? [])
        
        return FocusTrackerConfig(
            updateIntervalMs: updateIntervalMs,
            includeMetadata: includeMetadata,
            includeSystemApps: includeSystemApps,
            excludedApps: excludedApps,
            includedApps: includedApps
        )
    }
    
    func toJson() -> [String: Any] {
        return [
            "updateIntervalMs": updateIntervalMs,
            "includeMetadata": includeMetadata,
            "includeSystemApps": includeSystemApps,
            "excludedApps": Array(excludedApps),
            "includedApps": Array(includedApps)
        ]
    }
}
