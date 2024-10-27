import Cocoa
import FlutterMacOS

public class AppFocusTrackerPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
    private var eventSink: FlutterEventSink?
    private var timer: Timer?

    private var activeAppName: String = "Unknown"
    private var activeAppDuration: TimeInterval = 0
    private var lastUpdateTime: Date = Date()

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterEventChannel(
            name: "app_focus_tracker", binaryMessenger: registrar.messenger)
        let instance = AppFocusTrackerPlugin()
        channel.setStreamHandler(instance)
    }

    public func onListen(
        withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink
    ) -> FlutterError? {
        self.eventSink = events
        startTracking()
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        stopTracking()
        self.eventSink = nil
        return nil
    }

    private func startTracking() {
        lastUpdateTime = Date()
        timer = Timer.scheduledTimer(
            timeInterval: 1.0,
            target: self,
            selector: #selector(sendAppInfo),
            userInfo: nil,
            repeats: true
        )
    }

    private func stopTracking() {
        timer?.invalidate()
        timer = nil
    }

    @objc private func sendAppInfo() {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else { return }
        let currentAppName = frontmostApp.localizedName ?? "Unknown"
        let currentTime = Date()
        let timeElapsed = currentTime.timeIntervalSince(lastUpdateTime)
        lastUpdateTime = currentTime

        if currentAppName == activeAppName {
            activeAppDuration += timeElapsed
        } else {
            if let eventSink = eventSink {
                eventSink([
                    "appName": activeAppName,
                    "duration": Int(activeAppDuration),
                ])
            }
            activeAppName = currentAppName
            activeAppDuration = timeElapsed
        }

        if let eventSink = eventSink {
            eventSink([
                "appName": activeAppName,
                "duration": Int(activeAppDuration),
            ])
        }
    }
}
