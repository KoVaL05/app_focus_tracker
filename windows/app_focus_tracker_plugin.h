#ifndef FLUTTER_PLUGIN_APP_FOCUS_TRACKER_PLUGIN_H_
#define FLUTTER_PLUGIN_APP_FOCUS_TRACKER_PLUGIN_H_

#include <flutter/encodable_value.h>
#include <flutter/event_channel.h>
#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <windows.h>
#include <memory>
#include <string>
#include <thread>
#include <chrono>

// Forward declarations
struct FocusTrackerConfig;
struct AppInfo;

class AppFocusTrackerPlugin : public flutter::Plugin, 
                             public flutter::StreamHandler<flutter::EncodableValue> {
public:
    static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);

    AppFocusTrackerPlugin();
    virtual ~AppFocusTrackerPlugin();

    // Method channel handler
    void HandleMethodCall(
        const flutter::MethodCall<flutter::EncodableValue>& method_call,
        std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

    // Event callback for window focus changes
    void OnWindowFocusChanged(HWND hwnd);

private:
    // Event sink for streaming focus events
    std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> event_sink_;
    
    // Tracking state
    bool is_tracking_ = false;
    DWORD current_process_id_ = 0;
    HWND current_focused_window_ = nullptr;
    std::chrono::steady_clock::time_point focus_start_time_;
    std::string session_id_;
    
    // Configuration
    FocusTrackerConfig config_;
    
    // Background thread for periodic updates
    std::thread update_timer_;

    // Core tracking methods
    void StartTracking();
    void StopTracking();
    void SendCurrentFocusEvent();
    void SendPeriodicUpdate();
    void SendFocusEvent(const AppInfo& app_info, const std::string& event_type, int64_t duration_microseconds);
    
    // App information methods
    AppInfo CreateAppInfo(HWND hwnd);
    bool ShouldTrackApp(const AppInfo& app_info);
    AppInfo GetCurrentFocusedApp();
    flutter::EncodableList GetRunningApplications(bool include_system_apps);
    
    // Utility methods
    flutter::EncodableMap GetDiagnosticInfo();
    std::string GenerateSessionId();

    // StreamHandler methods
    std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>> OnListenInternal(
        const flutter::EncodableValue* arguments, 
        std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>&& events) override;
    std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>> OnCancelInternal(
        const flutter::EncodableValue* arguments) override;
};

#endif  // FLUTTER_PLUGIN_APP_FOCUS_TRACKER_PLUGIN_H_
