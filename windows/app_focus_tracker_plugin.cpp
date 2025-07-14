#include "app_focus_tracker_plugin.h"

#include <flutter/encodable_value.h>
#include <flutter/event_channel.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>
#include <psapi.h>
#include <tlhelp32.h>
#include <string>
#include <memory>
#include <map>
#include <set>
#include <vector>
#include <chrono>
#include <sstream>
#include <iostream>

namespace {

// Convert wide string to UTF-8
std::string WideToUtf8(const std::wstring& wide) {
    if (wide.empty()) return std::string();
    
    int size_needed = WideCharToMultiByte(CP_UTF8, 0, &wide[0], (int)wide.size(), NULL, 0, NULL, NULL);
    std::string result(size_needed, 0);
    WideCharToMultiByte(CP_UTF8, 0, &wide[0], (int)wide.size(), &result[0], size_needed, NULL, NULL);
    return result;
}

// Convert UTF-8 to wide string
std::wstring Utf8ToWide(const std::string& utf8) {
    if (utf8.empty()) return std::wstring();
    
    int size_needed = MultiByteToWideChar(CP_UTF8, 0, &utf8[0], (int)utf8.size(), NULL, 0);
    std::wstring result(size_needed, 0);
    MultiByteToWideChar(CP_UTF8, 0, &utf8[0], (int)utf8.size(), &result[0], size_needed);
    return result;
}

// Get process information
struct ProcessInfo {
    DWORD processId;
    std::string executablePath;
    std::string processName;
    std::string windowTitle;
    
    ProcessInfo() : processId(0) {}
};

ProcessInfo GetProcessInfoFromWindow(HWND hwnd) {
    ProcessInfo info;
    
    if (!hwnd) return info;
    
    // Get process ID
    GetWindowThreadProcessId(hwnd, &info.processId);
    
    // Get window title
    wchar_t windowTitle[256];
    if (GetWindowTextW(hwnd, windowTitle, sizeof(windowTitle) / sizeof(wchar_t))) {
        info.windowTitle = WideToUtf8(windowTitle);
    }
    
    // Get process handle
    HANDLE hProcess = OpenProcess(PROCESS_QUERY_INFORMATION | PROCESS_VM_READ, FALSE, info.processId);
    if (hProcess) {
        // Get executable path
        wchar_t executablePath[MAX_PATH];
        DWORD pathSize = sizeof(executablePath) / sizeof(wchar_t);
        if (QueryFullProcessImageNameW(hProcess, 0, executablePath, &pathSize)) {
            info.executablePath = WideToUtf8(executablePath);
            
            // Extract process name from path
            std::wstring pathWide(executablePath);
            size_t lastSlash = pathWide.find_last_of(L'\\');
            if (lastSlash != std::wstring::npos) {
                info.processName = WideToUtf8(pathWide.substr(lastSlash + 1));
            } else {
                info.processName = WideToUtf8(pathWide);
            }
        }
        
        CloseHandle(hProcess);
    }
    
    return info;
}

// Get file version information
std::string GetFileVersion(const std::string& filePath) {
    std::wstring wFilePath = Utf8ToWide(filePath);
    
    DWORD dwSize = GetFileVersionInfoSizeW(wFilePath.c_str(), NULL);
    if (dwSize == 0) return "";
    
    std::vector<BYTE> buffer(dwSize);
    if (!GetFileVersionInfoW(wFilePath.c_str(), 0, dwSize, buffer.data())) {
        return "";
    }
    
    VS_FIXEDFILEINFO* pFileInfo = nullptr;
    UINT len = 0;
    if (VerQueryValueW(buffer.data(), L"\\", (LPVOID*)&pFileInfo, &len)) {
        if (pFileInfo) {
            std::ostringstream version;
            version << HIWORD(pFileInfo->dwFileVersionMS) << "."
                   << LOWORD(pFileInfo->dwFileVersionMS) << "."
                   << HIWORD(pFileInfo->dwFileVersionLS) << "."
                   << LOWORD(pFileInfo->dwFileVersionLS);
            return version.str();
        }
    }
    
    return "";
}

} // namespace

// Configuration structure
struct FocusTrackerConfig {
    int updateIntervalMs = 1000;
    bool includeMetadata = false;
    bool includeSystemApps = false;
    std::set<std::string> excludedApps;
    std::set<std::string> includedApps;
    
    static FocusTrackerConfig FromMap(const flutter::EncodableMap& map) {
        FocusTrackerConfig config;
        
        auto it = map.find(flutter::EncodableValue("updateIntervalMs"));
        if (it != map.end() && std::holds_alternative<int>(it->second)) {
            config.updateIntervalMs = std::get<int>(it->second);
        }
        
        it = map.find(flutter::EncodableValue("includeMetadata"));
        if (it != map.end() && std::holds_alternative<bool>(it->second)) {
            config.includeMetadata = std::get<bool>(it->second);
        }
        
        it = map.find(flutter::EncodableValue("includeSystemApps"));
        if (it != map.end() && std::holds_alternative<bool>(it->second)) {
            config.includeSystemApps = std::get<bool>(it->second);
        }
        
        it = map.find(flutter::EncodableValue("excludedApps"));
        if (it != map.end() && std::holds_alternative<flutter::EncodableList>(it->second)) {
            auto list = std::get<flutter::EncodableList>(it->second);
            for (const auto& item : list) {
                if (std::holds_alternative<std::string>(item)) {
                    config.excludedApps.insert(std::get<std::string>(item));
                }
            }
        }
        
        it = map.find(flutter::EncodableValue("includedApps"));
        if (it != map.end() && std::holds_alternative<flutter::EncodableList>(it->second)) {
            auto list = std::get<flutter::EncodableList>(it->second);
            for (const auto& item : list) {
                if (std::holds_alternative<std::string>(item)) {
                    config.includedApps.insert(std::get<std::string>(item));
                }
            }
        }
        
        return config;
    }
    
    flutter::EncodableMap ToMap() const {
        flutter::EncodableMap map;
        map[flutter::EncodableValue("updateIntervalMs")] = flutter::EncodableValue(updateIntervalMs);
        map[flutter::EncodableValue("includeMetadata")] = flutter::EncodableValue(includeMetadata);
        map[flutter::EncodableValue("includeSystemApps")] = flutter::EncodableValue(includeSystemApps);
        
        flutter::EncodableList excludedList;
        for (const auto& app : excludedApps) {
            excludedList.push_back(flutter::EncodableValue(app));
        }
        map[flutter::EncodableValue("excludedApps")] = flutter::EncodableValue(excludedList);
        
        flutter::EncodableList includedList;
        for (const auto& app : includedApps) {
            includedList.push_back(flutter::EncodableValue(app));
        }
        map[flutter::EncodableValue("includedApps")] = flutter::EncodableValue(includedList);
        
        return map;
    }
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
    
    flutter::EncodableMap ToMap() const {
        flutter::EncodableMap map;
        map[flutter::EncodableValue("name")] = flutter::EncodableValue(name);
        map[flutter::EncodableValue("identifier")] = flutter::EncodableValue(identifier);
        map[flutter::EncodableValue("processId")] = flutter::EncodableValue(static_cast<int>(processId));
        
        if (!version.empty()) {
            map[flutter::EncodableValue("version")] = flutter::EncodableValue(version);
        }
        if (!iconPath.empty()) {
            map[flutter::EncodableValue("iconPath")] = flutter::EncodableValue(iconPath);
        }
        if (!executablePath.empty()) {
            map[flutter::EncodableValue("executablePath")] = flutter::EncodableValue(executablePath);
        }
        if (!metadata.empty()) {
            map[flutter::EncodableValue("metadata")] = flutter::EncodableValue(metadata);
        }
        
        return map;
    }
};

// Global variables for event handling
static AppFocusTrackerPlugin* g_plugin_instance = nullptr;
static HWINEVENTHOOK g_event_hook = nullptr;

// Window event callback
void CALLBACK WinEventProc(HWINEVENTHOOK hWinEventHook, DWORD event, HWND hwnd, 
                          LONG idObject, LONG idChild, DWORD dwEventThread, DWORD dwmsEventTime) {
    if (g_plugin_instance && event == EVENT_SYSTEM_FOREGROUND) {
        g_plugin_instance->OnWindowFocusChanged(hwnd);
    }
}

AppFocusTrackerPlugin::AppFocusTrackerPlugin() 
    : is_tracking_(false), current_process_id_(0), focus_start_time_(std::chrono::steady_clock::now()) {
    g_plugin_instance = this;
}

AppFocusTrackerPlugin::~AppFocusTrackerPlugin() {
    StopTracking();
    g_plugin_instance = nullptr;
}

void AppFocusTrackerPlugin::RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar) {
    auto plugin = std::make_unique<AppFocusTrackerPlugin>();
    
    // Register method channel
    auto method_channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
        registrar->messenger(), "app_focus_tracker_method", &flutter::StandardMethodCodec::GetInstance());
    
    method_channel->SetMethodCallHandler([plugin_ptr = plugin.get()](const auto& call, auto result) {
        plugin_ptr->HandleMethodCall(call, std::move(result));
    });
    
    // Register event channel
    auto event_channel = std::make_unique<flutter::EventChannel<flutter::EncodableValue>>(
        registrar->messenger(), "app_focus_tracker_events", &flutter::StandardMethodCodec::GetInstance());
    
    event_channel->SetStreamHandler(std::make_unique<AppFocusTrackerPlugin>(*plugin));
    
    registrar->AddPlugin(std::move(plugin));
}

void AppFocusTrackerPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
    
    const std::string& method = method_call.method_name();
    
    if (method == "getPlatformName") {
        result->Success(flutter::EncodableValue("Windows"));
    }
    else if (method == "isSupported") {
        result->Success(flutter::EncodableValue(true));
    }
    else if (method == "hasPermissions") {
        result->Success(flutter::EncodableValue(true)); // Windows generally doesn't require special permissions
    }
    else if (method == "requestPermissions") {
        result->Success(flutter::EncodableValue(true)); // Windows generally doesn't require special permissions
    }
    else if (method == "startTracking") {
        if (method_call.arguments() && std::holds_alternative<flutter::EncodableMap>(*method_call.arguments())) {
            auto args = std::get<flutter::EncodableMap>(*method_call.arguments());
            auto config_it = args.find(flutter::EncodableValue("config"));
            if (config_it != args.end() && std::holds_alternative<flutter::EncodableMap>(config_it->second)) {
                auto config_map = std::get<flutter::EncodableMap>(config_it->second);
                config_ = FocusTrackerConfig::FromMap(config_map);
                StartTracking();
                result->Success();
            } else {
                result->Error("INVALID_ARGS", "Invalid configuration");
            }
        } else {
            result->Error("INVALID_ARGS", "Configuration required");
        }
    }
    else if (method == "stopTracking") {
        StopTracking();
        result->Success();
    }
    else if (method == "isTracking") {
        result->Success(flutter::EncodableValue(is_tracking_));
    }
    else if (method == "getCurrentFocusedApp") {
        auto app_info = GetCurrentFocusedApp();
        if (app_info.processId != 0) {
            result->Success(flutter::EncodableValue(app_info.ToMap()));
        } else {
            result->Success();
        }
    }
    else if (method == "getRunningApplications") {
        bool include_system_apps = false;
        if (method_call.arguments() && std::holds_alternative<flutter::EncodableMap>(*method_call.arguments())) {
            auto args = std::get<flutter::EncodableMap>(*method_call.arguments());
            auto it = args.find(flutter::EncodableValue("includeSystemApps"));
            if (it != args.end() && std::holds_alternative<bool>(it->second)) {
                include_system_apps = std::get<bool>(it->second);
            }
        }
        auto apps = GetRunningApplications(include_system_apps);
        result->Success(flutter::EncodableValue(apps));
    }
    else if (method == "getDiagnosticInfo") {
        auto diagnostics = GetDiagnosticInfo();
        result->Success(flutter::EncodableValue(diagnostics));
    }
    else {
        result->NotImplemented();
    }
}

void AppFocusTrackerPlugin::StartTracking() {
    if (is_tracking_) return;
    
    is_tracking_ = true;
    session_id_ = GenerateSessionId();
    
    // Set up Windows event hook for foreground window changes
    g_event_hook = SetWinEventHook(
        EVENT_SYSTEM_FOREGROUND, EVENT_SYSTEM_FOREGROUND,
        NULL, WinEventProc, 0, 0,
        WINEVENT_OUTOFCONTEXT | WINEVENT_SKIPOWNPROCESS
    );
    
    // Start periodic updates timer
    update_timer_ = std::thread([this]() {
        while (is_tracking_) {
            SendPeriodicUpdate();
            std::this_thread::sleep_for(std::chrono::milliseconds(config_.updateIntervalMs));
        }
    });
    
    // Send initial focus event
    SendCurrentFocusEvent();
}

void AppFocusTrackerPlugin::StopTracking() {
    if (!is_tracking_) return;
    
    is_tracking_ = false;
    
    // Clean up event hook
    if (g_event_hook) {
        UnhookWinEvent(g_event_hook);
        g_event_hook = nullptr;
    }
    
    // Stop update timer
    if (update_timer_.joinable()) {
        update_timer_.join();
    }
    
    // Send final focus lost event
    if (current_process_id_ != 0) {
        auto current_time = std::chrono::steady_clock::now();
        auto duration = std::chrono::duration_cast<std::chrono::microseconds>(current_time - focus_start_time_).count();
        
        AppInfo app_info = CreateAppInfo(GetForegroundWindow());
        SendFocusEvent(app_info, "lost", duration);
    }
    
    current_process_id_ = 0;
    session_id_.clear();
}

void AppFocusTrackerPlugin::OnWindowFocusChanged(HWND hwnd) {
    if (!is_tracking_ || !hwnd) return;
    
    ProcessInfo proc_info = GetProcessInfoFromWindow(hwnd);
    if (proc_info.processId == 0) return;
    
    auto current_time = std::chrono::steady_clock::now();
    
    // Send focus lost event for previous app
    if (current_process_id_ != 0 && current_process_id_ != proc_info.processId) {
        auto duration = std::chrono::duration_cast<std::chrono::microseconds>(current_time - focus_start_time_).count();
        AppInfo prev_app_info = CreateAppInfo(current_focused_window_);
        SendFocusEvent(prev_app_info, "lost", duration);
    }
    
    // Update current focus
    if (current_process_id_ != proc_info.processId) {
        current_process_id_ = proc_info.processId;
        current_focused_window_ = hwnd;
        focus_start_time_ = current_time;
        
        // Send focus gained event
        AppInfo app_info = CreateAppInfo(hwnd);
        SendFocusEvent(app_info, "gained", 0);
    }
}

void AppFocusTrackerPlugin::SendCurrentFocusEvent() {
    HWND hwnd = GetForegroundWindow();
    if (!hwnd) return;
    
    ProcessInfo proc_info = GetProcessInfoFromWindow(hwnd);
    if (proc_info.processId == 0) return;
    
    current_process_id_ = proc_info.processId;
    current_focused_window_ = hwnd;
    focus_start_time_ = std::chrono::steady_clock::now();
    
    AppInfo app_info = CreateAppInfo(hwnd);
    SendFocusEvent(app_info, "gained", 0);
}

void AppFocusTrackerPlugin::SendPeriodicUpdate() {
    if (!is_tracking_ || current_process_id_ == 0) return;
    
    auto current_time = std::chrono::steady_clock::now();
    auto duration = std::chrono::duration_cast<std::chrono::microseconds>(current_time - focus_start_time_).count();
    
    AppInfo app_info = CreateAppInfo(current_focused_window_);
    SendFocusEvent(app_info, "durationUpdate", duration);
}

void AppFocusTrackerPlugin::SendFocusEvent(const AppInfo& app_info, const std::string& event_type, int64_t duration_microseconds) {
    if (!ShouldTrackApp(app_info)) return;
    
    auto current_time = std::chrono::steady_clock::now();
    auto timestamp_microseconds = std::chrono::duration_cast<std::chrono::microseconds>(
        current_time.time_since_epoch()).count();
    
    flutter::EncodableMap event;
    event[flutter::EncodableValue("appName")] = flutter::EncodableValue(app_info.name);
    event[flutter::EncodableValue("appIdentifier")] = flutter::EncodableValue(app_info.identifier);
    event[flutter::EncodableValue("timestamp")] = flutter::EncodableValue(timestamp_microseconds);
    event[flutter::EncodableValue("durationMicroseconds")] = flutter::EncodableValue(duration_microseconds);
    event[flutter::EncodableValue("processId")] = flutter::EncodableValue(static_cast<int>(app_info.processId));
    event[flutter::EncodableValue("eventType")] = flutter::EncodableValue(event_type);
    event[flutter::EncodableValue("sessionId")] = flutter::EncodableValue(session_id_);
    
    // Generate event ID
    std::ostringstream event_id;
    event_id << "evt_" << timestamp_microseconds << "_" << rand();
    event[flutter::EncodableValue("eventId")] = flutter::EncodableValue(event_id.str());
    
    if (config_.includeMetadata && !app_info.metadata.empty()) {
        event[flutter::EncodableValue("metadata")] = flutter::EncodableValue(app_info.metadata);
    }
    
    if (event_sink_) {
        event_sink_->Success(event);
    }
}

AppInfo AppFocusTrackerPlugin::CreateAppInfo(HWND hwnd) {
    AppInfo app_info;
    
    if (!hwnd) return app_info;
    
    ProcessInfo proc_info = GetProcessInfoFromWindow(hwnd);
    
    app_info.name = proc_info.windowTitle.empty() ? proc_info.processName : proc_info.windowTitle;
    app_info.identifier = proc_info.executablePath;
    app_info.processId = proc_info.processId;
    app_info.executablePath = proc_info.executablePath;
    
    // Get version information
    if (!proc_info.executablePath.empty()) {
        app_info.version = GetFileVersion(proc_info.executablePath);
    }
    
    // Build metadata
    if (config_.includeMetadata) {
        app_info.metadata[flutter::EncodableValue("processName")] = flutter::EncodableValue(proc_info.processName);
        app_info.metadata[flutter::EncodableValue("windowTitle")] = flutter::EncodableValue(proc_info.windowTitle);
        
        // Get window rectangle
        RECT rect;
        if (GetWindowRect(hwnd, &rect)) {
            flutter::EncodableMap window_rect;
            window_rect[flutter::EncodableValue("left")] = flutter::EncodableValue(rect.left);
            window_rect[flutter::EncodableValue("top")] = flutter::EncodableValue(rect.top);
            window_rect[flutter::EncodableValue("right")] = flutter::EncodableValue(rect.right);
            window_rect[flutter::EncodableValue("bottom")] = flutter::EncodableValue(rect.bottom);
            app_info.metadata[flutter::EncodableValue("windowRect")] = flutter::EncodableValue(window_rect);
        }
        
        // Check if window is maximized
        WINDOWPLACEMENT placement = { sizeof(WINDOWPLACEMENT) };
        if (GetWindowPlacement(hwnd, &placement)) {
            app_info.metadata[flutter::EncodableValue("isMaximized")] = 
                flutter::EncodableValue(placement.showCmd == SW_SHOWMAXIMIZED);
        }
    }
    
    return app_info;
}

bool AppFocusTrackerPlugin::ShouldTrackApp(const AppInfo& app_info) {
    // Check excluded apps
    if (config_.excludedApps.count(app_info.identifier) > 0) {
        return false;
    }
    
    // Check included apps (if specified)
    if (!config_.includedApps.empty() && config_.includedApps.count(app_info.identifier) == 0) {
        return false;
    }
    
    // Check system apps
    if (!config_.includeSystemApps) {
        std::set<std::string> system_apps = {
            "dwm.exe", "explorer.exe", "winlogon.exe", "csrss.exe", "smss.exe"
        };
        
        // Extract filename from path
        std::string filename = app_info.identifier;
        size_t last_slash = filename.find_last_of('\\');
        if (last_slash != std::string::npos) {
            filename = filename.substr(last_slash + 1);
        }
        
        if (system_apps.count(filename) > 0) {
            return false;
        }
    }
    
    return true;
}

AppInfo AppFocusTrackerPlugin::GetCurrentFocusedApp() {
    HWND hwnd = GetForegroundWindow();
    return CreateAppInfo(hwnd);
}

flutter::EncodableList AppFocusTrackerPlugin::GetRunningApplications(bool include_system_apps) {
    flutter::EncodableList app_list;
    
    // Create snapshot of running processes
    HANDLE hSnapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (hSnapshot == INVALID_HANDLE_VALUE) {
        return app_list;
    }
    
    PROCESSENTRY32W pe32;
    pe32.dwSize = sizeof(PROCESSENTRY32W);
    
    if (Process32FirstW(hSnapshot, &pe32)) {
        do {
            HANDLE hProcess = OpenProcess(PROCESS_QUERY_INFORMATION | PROCESS_VM_READ, FALSE, pe32.th32ProcessID);
            if (hProcess) {
                wchar_t executablePath[MAX_PATH];
                DWORD pathSize = sizeof(executablePath) / sizeof(wchar_t);
                if (QueryFullProcessImageNameW(hProcess, 0, executablePath, &pathSize)) {
                    AppInfo app_info;
                    app_info.name = WideToUtf8(pe32.szExeFile);
                    app_info.identifier = WideToUtf8(executablePath);
                    app_info.processId = pe32.th32ProcessID;
                    app_info.executablePath = WideToUtf8(executablePath);
                    app_info.version = GetFileVersion(app_info.executablePath);
                    
                    if (include_system_apps || ShouldTrackApp(app_info)) {
                        app_list.push_back(flutter::EncodableValue(app_info.ToMap()));
                    }
                }
                CloseHandle(hProcess);
            }
        } while (Process32NextW(hSnapshot, &pe32));
    }
    
    CloseHandle(hSnapshot);
    return app_list;
}

flutter::EncodableMap AppFocusTrackerPlugin::GetDiagnosticInfo() {
    flutter::EncodableMap diagnostics;
    
    diagnostics[flutter::EncodableValue("platform")] = flutter::EncodableValue("Windows");
    diagnostics[flutter::EncodableValue("isTracking")] = flutter::EncodableValue(is_tracking_);
    diagnostics[flutter::EncodableValue("hasPermissions")] = flutter::EncodableValue(true);
    diagnostics[flutter::EncodableValue("sessionId")] = flutter::EncodableValue(session_id_);
    diagnostics[flutter::EncodableValue("config")] = flutter::EncodableValue(config_.ToMap());
    
    if (current_process_id_ != 0) {
        AppInfo current_app = GetCurrentFocusedApp();
        diagnostics[flutter::EncodableValue("currentApp")] = flutter::EncodableValue(current_app.ToMap());
        
        auto current_time = std::chrono::steady_clock::now();
        auto focus_duration = std::chrono::duration_cast<std::chrono::microseconds>(current_time - focus_start_time_).count();
        diagnostics[flutter::EncodableValue("focusStartTime")] = flutter::EncodableValue(focus_duration);
    }
    
    // Windows version info
    OSVERSIONINFOEXW osvi;
    ZeroMemory(&osvi, sizeof(OSVERSIONINFOEXW));
    osvi.dwOSVersionInfoSize = sizeof(OSVERSIONINFOEXW);
    
    #pragma warning(push)
    #pragma warning(disable: 4996) // GetVersionEx is deprecated but still works
    if (GetVersionExW((OSVERSIONINFOW*)&osvi)) {
        std::ostringstream version;
        version << osvi.dwMajorVersion << "." << osvi.dwMinorVersion << "." << osvi.dwBuildNumber;
        diagnostics[flutter::EncodableValue("systemVersion")] = flutter::EncodableValue(version.str());
    }
    #pragma warning(pop)
    
    return diagnostics;
}

std::string AppFocusTrackerPlugin::GenerateSessionId() {
    auto now = std::chrono::steady_clock::now();
    auto timestamp = std::chrono::duration_cast<std::chrono::microseconds>(now.time_since_epoch()).count();
    
    std::ostringstream session_id;
    session_id << "session_" << timestamp << "_" << rand();
    return session_id.str();
}

// StreamHandler implementation
std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>>
AppFocusTrackerPlugin::OnListenInternal(
    const flutter::EncodableValue* arguments,
    std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>&& events) {
    event_sink_ = std::move(events);
    return nullptr;
}

std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>>
AppFocusTrackerPlugin::OnCancelInternal(const flutter::EncodableValue* arguments) {
    event_sink_ = nullptr;
    return nullptr;
}



