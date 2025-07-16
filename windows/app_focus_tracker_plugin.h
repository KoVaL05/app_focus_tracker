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
#include <set>
#include <map>
#include <queue>
#include <mutex>
#include <condition_variable>

// Configuration structure
struct FocusTrackerConfig {
    int updateIntervalMs = 1000;
    bool includeMetadata = false;
    bool includeSystemApps = false;
    bool enableBrowserTabTracking = false;
    std::set<std::string> excludedApps;
    std::set<std::string> includedApps;
    
    static FocusTrackerConfig FromMap(const flutter::EncodableMap& map);
    flutter::EncodableMap ToMap() const;
};

// App information structure
struct AppInfo {
    std::string name;
    std::string identifier;
    DWORD processId;
    std::string version;
    std::string iconPath;
    std::string executablePath;
    flutter::EncodableMap metadata;
    
    flutter::EncodableMap ToMap() const;
};

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
    
    // Browser tab tracking
    std::map<std::string, std::string> last_browser_tab_info_;
    std::thread browser_tab_check_timer_;

    // Thread-safe event queue for background thread events
    std::queue<flutter::EncodableMap> event_queue_;
    std::mutex event_queue_mutex_;
    std::condition_variable event_queue_cv_;
    HWND message_window_ = nullptr;
    std::thread event_processor_thread_; // (may be unused after refactor)
    bool should_process_events_ = false;
    std::mutex event_sink_mutex_; // Protect event_sink_ access
    DWORD platform_thread_id_ = 0; // Store the platform thread ID

    static constexpr UINT kFlushMessageId = WM_APP + 0x40;

    // Core tracking methods
    void StartTracking();
    void StopTracking();
    void SendCurrentFocusEvent();
    void SendPeriodicUpdate();
    void SendFocusEvent(const AppInfo& app_info, const std::string& event_type, int64_t duration_microseconds);
    
    // Browser tab change detection
    void StartBrowserTabTracking();
    void StopBrowserTabTracking();
    void CheckForBrowserTabChanges();
    void SendBrowserTabChangeEvent(const AppInfo& app_info, const std::string& previous_tab_info, const std::string& current_tab_info);
    
    // App information methods
    AppInfo CreateAppInfo(HWND hwnd, bool from_background_thread = false);
    bool ShouldTrackApp(const AppInfo& app_info);
    AppInfo GetCurrentFocusedApp();
    flutter::EncodableList GetRunningApplications(bool include_system_apps);
    
    // Utility methods
    flutter::EncodableMap GetDiagnosticInfo();
    std::string GenerateSessionId();

    // Event processing methods
    void QueueEvent(const flutter::EncodableMap& event);
    void FlushEventQueue();
    static LRESULT CALLBACK MessageWndProc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp);
    void CreateMessageWindow();
    void DestroyMessageWindow();
    bool IsOnPlatformThread() const;
    void SendEventDirectly(const flutter::EncodableMap& event);

    // StreamHandler methods
    std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>> OnListenInternal(
        const flutter::EncodableValue* arguments, 
        std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>&& events) override;
    std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>> OnCancelInternal(
        const flutter::EncodableValue* arguments) override;
};

#endif  // FLUTTER_PLUGIN_APP_FOCUS_TRACKER_PLUGIN_H_
