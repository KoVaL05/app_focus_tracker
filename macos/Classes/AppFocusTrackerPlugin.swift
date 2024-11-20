import Cocoa
import FlutterMacOS

public class AppFocusTrackerPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
    private var eventSink: FlutterEventSink?
    private var timer: Timer?
    private var activeAppName: String = "Unknown"

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
        timer = Timer.scheduledTimer(
            timeInterval: 60.0,
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

        if currentAppName != activeAppName {
            // Reset duration for the new app focus
            activeAppName = currentAppName
        }

        // Send event with a duration of 1 for each second in focus
        if let eventSink = eventSink {
            eventSink([
                "appName": activeAppName,
                "duration": 60,
            ])
        }
    }
}
