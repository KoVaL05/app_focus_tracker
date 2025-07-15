#include "app_focus_tracker_plugin.h"

#include <flutter/encodable_value.h>
#include <flutter/event_channel.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>
#include <psapi.h>
#include <tlhelp32.h>
#include <shellapi.h>
#include <string>
#include <memory>
#include <map>
#include <set>
#include <vector>
#include <chrono>
#include <sstream>
#include <iostream>
#include <algorithm>
#include <regex>
#include <UIAutomation.h>
#pragma comment(lib, "Oleacc.lib")

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

// ------------------- UIAutomation Helpers (Windows) --------------------

// Extract host from a URL string (no path/query) – returns empty on failure
static std::string HostFromUrl(const std::string& url) {
    std::regex host_re(R"((?:https?://)?([^/]+))", std::regex::icase);
    std::smatch m;
    if (std::regex_search(url, m, host_re) && m.size() > 1) {
        return m[1].str();
    }
    return "";
}

// Obtain the base URL (scheme://host[:port]) of the front-most tab in a browser
// window using UIAutomation. Returns empty string if not available.
static std::string GetBaseURLFromBrowserWindow(HWND hwnd) {
    if (!hwnd) {
        #ifdef _DEBUG
        std::cout << "[DEBUG] GetBaseURLFromBrowserWindow: hwnd is null" << std::endl;
        #endif
        return "";
    }

    bool comInit = false;
    HRESULT hr = CoInitializeEx(NULL, COINIT_MULTITHREADED);
    if (SUCCEEDED(hr)) {
        comInit = true;
    } else if (hr == RPC_E_CHANGED_MODE) {
        // Already initialised in STA – carry on.
        #ifdef _DEBUG
        std::cout << "[DEBUG] GetBaseURLFromBrowserWindow: COM already initialized" << std::endl;
        #endif
    } else {
        #ifdef _DEBUG
        std::cout << "[DEBUG] GetBaseURLFromBrowserWindow: COM initialization failed: " << hr << std::endl;
        #endif
    }

    std::string result;
    int elementsFound = 0;
    int elementsProcessed = 0;

    IUIAutomation* automation = nullptr;
    hr = CoCreateInstance(__uuidof(CUIAutomation), nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&automation));
    if (!SUCCEEDED(hr)) {
        #ifdef _DEBUG
        std::cout << "[DEBUG] GetBaseURLFromBrowserWindow: Failed to create UIAutomation instance: " << hr << std::endl;
        #endif
        if (comInit) CoUninitialize();
        return "";
    }

    IUIAutomationElement* root = nullptr;
    hr = automation->ElementFromHandle(hwnd, &root);
    if (!SUCCEEDED(hr) || !root) {
        #ifdef _DEBUG
        std::cout << "[DEBUG] GetBaseURLFromBrowserWindow: Failed to get element from window handle: " << hr << std::endl;
        #endif
        automation->Release();
        if (comInit) CoUninitialize();
        return "";
    }

    // Build OR condition: ControlType == Edit OR ControlType == Document
    VARIANT vEdit; vEdit.vt = VT_I4; vEdit.lVal = UIA_EditControlTypeId;
    VARIANT vDoc;  vDoc.vt = VT_I4; vDoc.lVal = UIA_DocumentControlTypeId;
    IUIAutomationCondition *condEdit = nullptr, *condDoc = nullptr, *orCond = nullptr;
    
    bool conditionsCreated = SUCCEEDED(automation->CreatePropertyCondition(UIA_ControlTypePropertyId, vEdit, &condEdit)) &&
                           SUCCEEDED(automation->CreatePropertyCondition(UIA_ControlTypePropertyId, vDoc, &condDoc)) &&
                           SUCCEEDED(automation->CreateOrCondition(condEdit, condDoc, &orCond));
    
    if (!conditionsCreated) {
        #ifdef _DEBUG
        std::cout << "[DEBUG] GetBaseURLFromBrowserWindow: Failed to create automation conditions" << std::endl;
        #endif
    } else {
        IUIAutomationElementArray* elements = nullptr;
        hr = root->FindAll(TreeScope_Subtree, orCond, &elements);
        if (SUCCEEDED(hr) && elements) {
            elements->get_Length(&elementsFound);
            #ifdef _DEBUG
            std::cout << "[DEBUG] GetBaseURLFromBrowserWindow: Found " << elementsFound << " elements" << std::endl;
            #endif
            
            for (int i = 0; i < elementsFound; ++i) {
                IUIAutomationElement* el = nullptr;
                if (SUCCEEDED(elements->GetElement(i, &el)) && el) {
                    elementsProcessed++;
                    
                    // Get element info for debugging
                    #ifdef _DEBUG
                    BSTR elementName = nullptr;
                    if (SUCCEEDED(el->get_CurrentName(&elementName)) && elementName) {
                        std::cout << "[DEBUG] Processing element " << i << ": " << WideToUtf8(elementName) << std::endl;
                        SysFreeString(elementName);
                    }
                    #endif
                    
                    // Try ValuePattern first
                    IUIAutomationValuePattern* vp = nullptr;
                    if (SUCCEEDED(el->GetCurrentPattern(UIA_ValuePatternId, reinterpret_cast<IUnknown**>(&vp))) && vp) {
                        BSTR bstr;
                        if (SUCCEEDED(vp->get_CurrentValue(&bstr)) && bstr && SysStringLen(bstr) > 0) {
                            std::wstring w(bstr, SysStringLen(bstr));
                            std::string candidate = WideToUtf8(w);
                            #ifdef _DEBUG
                            std::cout << "[DEBUG] ValuePattern result: " << candidate << std::endl;
                            #endif
                            // Only accept if it looks like a URL
                            if (candidate.find("http") == 0 || candidate.find("https") == 0 || 
                                candidate.find("www.") != std::string::npos ||
                                candidate.find(".com") != std::string::npos ||
                                candidate.find(".org") != std::string::npos ||
                                candidate.find(".net") != std::string::npos) {
                                result = candidate;
                                SysFreeString(bstr);
                                vp->Release();
                                el->Release();
                                break;
                            }
                            SysFreeString(bstr);
                        }
                        vp->Release();
                    }

                    // Fallback to Name property if still empty
                    if (result.empty()) {
                        BSTR nameBstr;
                        if (SUCCEEDED(el->get_CurrentName(&nameBstr)) && nameBstr && SysStringLen(nameBstr) > 0) {
                            std::wstring w(nameBstr, SysStringLen(nameBstr));
                            std::string candidate = WideToUtf8(w);
                            #ifdef _DEBUG
                            std::cout << "[DEBUG] Name property result: " << candidate << std::endl;
                            #endif
                            // Only accept if it looks like a URL
                            if (candidate.find("http") == 0 || candidate.find("https") == 0 || 
                                candidate.find("www.") != std::string::npos ||
                                candidate.find(".com") != std::string::npos ||
                                candidate.find(".org") != std::string::npos ||
                                candidate.find(".net") != std::string::npos) {
                                result = candidate;
                                SysFreeString(nameBstr);
                                el->Release();
                                break;
                            }
                            SysFreeString(nameBstr);
                        }
                    }
                    el->Release();
                }
            }
            elements->Release();
        } else {
            #ifdef _DEBUG
            std::cout << "[DEBUG] GetBaseURLFromBrowserWindow: FindAll failed or returned null: " << hr << std::endl;
            #endif
        }
        
        if (condEdit) condEdit->Release();
        if (condDoc) condDoc->Release();
        if (orCond) orCond->Release();
    }
    
    root->Release();
    automation->Release();

    if (comInit) CoUninitialize();

    #ifdef _DEBUG
    std::cout << "[DEBUG] GetBaseURLFromBrowserWindow: Processed " << elementsProcessed << "/" << elementsFound 
              << " elements, result: '" << result << "'" << std::endl;
    #endif

    // Reduce to base origin (scheme://host[:port])
    if (!result.empty()) {
        std::regex full_re(R"(^([a-zA-Z][a-zA-Z0-9+.-]*://)?([^/]+))");
        std::smatch m;
        if (std::regex_search(result, m, full_re) && m.size() > 2) {
            std::string scheme = m[1].str();
            std::string host = m[2].str();
            if (scheme.empty()) scheme = "https://";
            std::string baseUrl = scheme + host; // no trailing slash
            #ifdef _DEBUG
            std::cout << "[DEBUG] GetBaseURLFromBrowserWindow: Final base URL: " << baseUrl << std::endl;
            #endif
            return baseUrl;
        } else {
            #ifdef _DEBUG
            std::cout << "[DEBUG] GetBaseURLFromBrowserWindow: Regex failed to match URL pattern" << std::endl;
            #endif
        }
    }
    return "";
}
// ------------------- end helpers --------------------
// Add helper structures and functions for browser tab extraction
// Browser tab information structure
struct BrowserTabInfo {
    std::string domain;
    std::string url;
    std::string title;
    std::string browserType;
    bool valid;
    BrowserTabInfo() : valid(false) {}
};

// Detect whether a process corresponds to a common desktop browser
static bool IsBrowserProcess(const std::string& process_name,
                             const std::string& executable_path) {
    static const std::set<std::string> kBrowserExecutables = {
        "chrome.exe", "msedge.exe", "firefox.exe", "brave.exe",
        "opera.exe", "safari.exe", "chromium.exe"
    };

    // Normalise to lowercase for comparison
    std::string lowered = process_name;
    std::transform(lowered.begin(), lowered.end(), lowered.begin(), ::tolower);
    if (kBrowserExecutables.count(lowered) > 0) {
        return true;
    }

    // Fallback: look for browser identifiers in executable path
    std::string path_lower = executable_path;
    std::transform(path_lower.begin(), path_lower.end(), path_lower.begin(), ::tolower);
    for (const auto& key : {"chrome", "edge", "firefox", "brave", "opera", "safari", "chromium"}) {
        if (path_lower.find(key) != std::string::npos) {
            return true;
        }
    }
    return false;
}

// Try to extract tab info (domain/title) from a window title string.
static BrowserTabInfo ExtractBrowserTabInfo(const std::string& window_title,
                                            const std::string& process_name) {
    BrowserTabInfo info;

    #ifdef _DEBUG
    std::cout << "[DEBUG] ExtractBrowserTabInfo: Processing window_title='" << window_title 
              << "', process_name='" << process_name << "'" << std::endl;
    #endif

    std::string proc_lower = process_name;
    std::transform(proc_lower.begin(), proc_lower.end(), proc_lower.begin(), ::tolower);
    if (proc_lower.find("chrome") != std::string::npos) {
        info.browserType = "chrome";
    } else if (proc_lower.find("edge") != std::string::npos) {
        info.browserType = "edge";
    } else if (proc_lower.find("firefox") != std::string::npos) {
        info.browserType = "firefox";
    } else if (proc_lower.find("brave") != std::string::npos) {
        info.browserType = "brave";
    } else if (proc_lower.find("opera") != std::string::npos) {
        info.browserType = "opera";
    } else if (proc_lower.find("safari") != std::string::npos) {
        info.browserType = "safari";
    } else {
        info.browserType = "browser";
    }

    #ifdef _DEBUG
    std::cout << "[DEBUG] ExtractBrowserTabInfo: Detected browser type: " << info.browserType << std::endl;
    #endif

    // Common patterns: "<page title> - <Browser Name>" or vice-versa.
    // We capture everything before the last hyphen as title if the suffix matches a browser name.
    std::regex pattern(R"((.+?)\s*-\s*(Google Chrome|Microsoft Edge|Brave|Mozilla Firefox|Opera|Safari))",
                       std::regex::icase);
    std::smatch match;
    std::string page_title = window_title;
    if (std::regex_match(window_title, match, pattern) && match.size() > 1) {
        page_title = match[1].str();
        #ifdef _DEBUG
        std::cout << "[DEBUG] ExtractBrowserTabInfo: Extracted page title from pattern: '" << page_title << "'" << std::endl;
        #endif
    } else {
        #ifdef _DEBUG
        std::cout << "[DEBUG] ExtractBrowserTabInfo: No browser pattern matched, using full title" << std::endl;
        #endif
    }
    info.title = page_title;

    // Extract domain from title (look for something that looks like a hostname)
    std::regex domain_regex(R"(([a-zA-Z0-9.-]+\.[a-zA-Z]{2,}))");
    std::smatch domain_match;
    if (std::regex_search(page_title, domain_match, domain_regex) && domain_match.size() > 1) {
        info.domain = domain_match[1].str();
        info.url = "https://" + info.domain;
        info.valid = true;
        #ifdef _DEBUG
        std::cout << "[DEBUG] ExtractBrowserTabInfo: Found domain via regex: '" << info.domain 
                  << "', constructed URL: '" << info.url << "'" << std::endl;
        #endif
    } else {
        #ifdef _DEBUG
        std::cout << "[DEBUG] ExtractBrowserTabInfo: No domain found in title via regex" << std::endl;
        #endif
        
        // Try alternative patterns for domain extraction
        std::vector<std::regex> fallback_patterns = {
            std::regex(R"(https?://([^/\s]+))", std::regex::icase),  // Full URL
            std::regex(R"(www\.([^/\s]+))", std::regex::icase),      // www.domain.com
            std::regex(R"(([a-zA-Z0-9-]+\.(com|org|net|edu|gov|co\.uk|io|dev))", std::regex::icase)  // Common TLDs
        };
        
        for (size_t i = 0; i < fallback_patterns.size() && !info.valid; ++i) {
            std::smatch fallback_match;
            if (std::regex_search(page_title, fallback_match, fallback_patterns[i]) && fallback_match.size() > 1) {
                std::string extracted = fallback_match[1].str();
                // Clean up common prefixes
                if (extracted.find("www.") == 0) {
                    extracted = extracted.substr(4);
                }
                info.domain = extracted;
                info.url = "https://" + info.domain;
                info.valid = true;
                #ifdef _DEBUG
                std::cout << "[DEBUG] ExtractBrowserTabInfo: Found domain via fallback pattern " << i 
                          << ": '" << info.domain << "'" << std::endl;
                #endif
                break;
            }
        }
        
        if (!info.valid) {
            #ifdef _DEBUG
            std::cout << "[DEBUG] ExtractBrowserTabInfo: No domain found via any pattern" << std::endl;
            #endif
        }
    }

    #ifdef _DEBUG
    std::cout << "[DEBUG] ExtractBrowserTabInfo: Final result - domain='" << info.domain 
              << "', url='" << info.url << "', title='" << info.title 
              << "', browserType='" << info.browserType << "', valid=" << (info.valid ? "true" : "false") << std::endl;
    #endif

    return info;
}

// Implementation of FocusTrackerConfig methods
FocusTrackerConfig FocusTrackerConfig::FromMap(const flutter::EncodableMap& map) {
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
    
    it = map.find(flutter::EncodableValue("enableBrowserTabTracking"));
    if (it != map.end() && std::holds_alternative<bool>(it->second)) {
        config.enableBrowserTabTracking = std::get<bool>(it->second);
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

flutter::EncodableMap FocusTrackerConfig::ToMap() const {
    flutter::EncodableMap map;
    map[flutter::EncodableValue("updateIntervalMs")] = flutter::EncodableValue(updateIntervalMs);
    map[flutter::EncodableValue("includeMetadata")] = flutter::EncodableValue(includeMetadata);
    map[flutter::EncodableValue("includeSystemApps")] = flutter::EncodableValue(includeSystemApps);
    map[flutter::EncodableValue("enableBrowserTabTracking")] = flutter::EncodableValue(enableBrowserTabTracking);
    
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

// Implementation of AppInfo methods
flutter::EncodableMap AppInfo::ToMap() const {
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
        // Check if we can access window information (basic permission check)
        HWND testWindow = GetForegroundWindow();
        if (testWindow != NULL) {
            DWORD processId;
            if (GetWindowThreadProcessId(testWindow, &processId)) {
                result->Success(flutter::EncodableValue(true));
            } else {
                result->Success(flutter::EncodableValue(false));
            }
        } else {
            result->Success(flutter::EncodableValue(false));
        }
    }
    else if (method == "requestPermissions") {
        // On Windows, try to set up event hooks to verify permissions
        HWINEVENTHOOK testHook = SetWinEventHook(
            EVENT_SYSTEM_FOREGROUND, EVENT_SYSTEM_FOREGROUND,
            NULL, NULL, 0, 0,
            WINEVENT_OUTOFCONTEXT | WINEVENT_SKIPOWNPROCESS
        );
        
        if (testHook != NULL) {
            UnhookWinEvent(testHook);
            result->Success(flutter::EncodableValue(true));
        } else {
            // If hooks fail, it might be due to UAC or antivirus
            result->Success(flutter::EncodableValue(false));
        }
    }
    else if (method == "openSystemSettings") {
        // On Windows, open the Privacy & Security settings
        ShellExecuteA(NULL, "open", "ms-settings:privacy", NULL, NULL, SW_SHOW);
        result->Success();
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
    else if (method == "debugUrlExtraction") {
        // Debug method to test URL extraction on current focused browser
        HWND hwnd = GetForegroundWindow();
        flutter::EncodableMap debug_info;
        
        if (hwnd) {
            ProcessInfo proc_info = GetProcessInfoFromWindow(hwnd);
            debug_info[flutter::EncodableValue("processName")] = flutter::EncodableValue(proc_info.processName);
            debug_info[flutter::EncodableValue("windowTitle")] = flutter::EncodableValue(proc_info.windowTitle);
            debug_info[flutter::EncodableValue("executablePath")] = flutter::EncodableValue(proc_info.executablePath);
            
            bool is_browser = IsBrowserProcess(proc_info.processName, proc_info.executablePath);
            debug_info[flutter::EncodableValue("isBrowser")] = flutter::EncodableValue(is_browser);
            
            if (is_browser) {
                // Test UIAutomation extraction
                std::string uia_url = GetBaseURLFromBrowserWindow(hwnd);
                debug_info[flutter::EncodableValue("uiAutomationUrl")] = flutter::EncodableValue(uia_url);
                
                // Test window title extraction
                BrowserTabInfo tab_info = ExtractBrowserTabInfo(proc_info.windowTitle, proc_info.processName);
                flutter::EncodableMap tab_debug;
                tab_debug[flutter::EncodableValue("domain")] = flutter::EncodableValue(tab_info.domain);
                tab_debug[flutter::EncodableValue("url")] = flutter::EncodableValue(tab_info.url);
                tab_debug[flutter::EncodableValue("title")] = flutter::EncodableValue(tab_info.title);
                tab_debug[flutter::EncodableValue("browserType")] = flutter::EncodableValue(tab_info.browserType);
                tab_debug[flutter::EncodableValue("valid")] = flutter::EncodableValue(tab_info.valid);
                debug_info[flutter::EncodableValue("titleExtraction")] = flutter::EncodableValue(tab_debug);
            }
        } else {
            debug_info[flutter::EncodableValue("error")] = flutter::EncodableValue("No foreground window");
        }
        
        result->Success(flutter::EncodableValue(debug_info));
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
    
    // Start browser tab tracking if metadata and browser tab tracking are enabled
    if (config_.includeMetadata && config_.enableBrowserTabTracking) {
        StartBrowserTabTracking();
    }
    
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
    
    // Stop browser tab tracking
    StopBrowserTabTracking();
    
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

// Browser Tab Change Detection

void AppFocusTrackerPlugin::StartBrowserTabTracking() {
    browser_tab_check_timer_ = std::thread([this]() {
        while (is_tracking_) {
            CheckForBrowserTabChanges();
            std::this_thread::sleep_for(std::chrono::milliseconds(500)); // Check every 500ms
        }
    });
}

void AppFocusTrackerPlugin::StopBrowserTabTracking() {
    if (browser_tab_check_timer_.joinable()) {
        browser_tab_check_timer_.join();
    }
    last_browser_tab_info_.clear();
}

void AppFocusTrackerPlugin::CheckForBrowserTabChanges() {
    if (!is_tracking_ || current_process_id_ == 0) return;
    
    AppInfo current_app = CreateAppInfo(current_focused_window_);
    
    // Check if current app is a browser
    auto is_browser_it = current_app.metadata.find(flutter::EncodableValue("isBrowser"));
    if (is_browser_it == current_app.metadata.end() || 
        !std::holds_alternative<bool>(is_browser_it->second) || 
        !std::get<bool>(is_browser_it->second)) {
        // Not a browser, clear last tab info
        last_browser_tab_info_.clear();
        return;
    }
    
    // Get current browser tab info
    auto browser_tab_it = current_app.metadata.find(flutter::EncodableValue("browserTab"));
    if (browser_tab_it == current_app.metadata.end() || 
        !std::holds_alternative<flutter::EncodableMap>(browser_tab_it->second)) {
        last_browser_tab_info_.clear();
        return;
    }
    
    flutter::EncodableMap current_tab_map = std::get<flutter::EncodableMap>(browser_tab_it->second);
    
    // Build comparison key prioritising domain/url; titles change frequently.
    std::string current_tab_info;
    auto domain_it = current_tab_map.find(flutter::EncodableValue("domain"));
    if (domain_it != current_tab_map.end() && std::holds_alternative<std::string>(domain_it->second)) {
        current_tab_info = std::get<std::string>(domain_it->second);
    } else {
        auto url_it = current_tab_map.find(flutter::EncodableValue("url"));
        if (url_it != current_tab_map.end() && std::holds_alternative<std::string>(url_it->second)) {
            current_tab_info = std::get<std::string>(url_it->second);
        }
    }
    // If still empty fall back to a sanitized title (remove digits to reduce churn)
    if (current_tab_info.empty()) {
        auto title_it = current_tab_map.find(flutter::EncodableValue("title"));
        if (title_it != current_tab_map.end() && std::holds_alternative<std::string>(title_it->second)) {
            std::string raw_title = std::get<std::string>(title_it->second);
            current_tab_info.reserve(raw_title.size());
            for (char c : raw_title) {
                if (!(c >= '0' && c <= '9') && c != '.' && c != ',') {
                    current_tab_info.push_back(c);
                }
            }
        }
    }
    
    // Check if tab info has changed
    auto last_tab_it = last_browser_tab_info_.find(current_app.identifier);
    if (last_tab_it != last_browser_tab_info_.end()) {
        if (last_tab_it->second != current_tab_info) {
            // Tab has changed, send tab change event
            SendBrowserTabChangeEvent(current_app, last_tab_it->second, current_tab_info);
            last_tab_it->second = current_tab_info;
        }
    } else {
        // First time seeing this tab, just store it
        last_browser_tab_info_[current_app.identifier] = current_tab_info;
    }
}

void AppFocusTrackerPlugin::SendBrowserTabChangeEvent(const AppInfo& app_info, const std::string& previous_tab_info, const std::string& current_tab_info) {
    // Treat tab change within the same browser window as a distinct focus
    // transition so that downstream duration calculations stay accurate.

    auto current_time = std::chrono::steady_clock::now();

    // Calculate how long the previous tab was focused.
    auto duration = std::chrono::duration_cast<std::chrono::microseconds>(current_time - focus_start_time_).count();

    // Emit a focus-lost event for the old tab (using accumulated duration).
    SendFocusEvent(app_info, "lost", duration);

    // Reset the internal timer so subsequent durationUpdate events measure the
    // time spent on the newly selected tab.
    focus_start_time_ = current_time;

    // Emit a focus-gained event for the new tab.
    SendFocusEvent(app_info, "gained", 0);
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
        // Check if application is a browser and extract tab info
        if (IsBrowserProcess(proc_info.processName, proc_info.executablePath)) {
            BrowserTabInfo tab = ExtractBrowserTabInfo(proc_info.windowTitle, proc_info.processName);

            // Try to get accurate base-URL via UIAutomation
            std::string baseUrl = GetBaseURLFromBrowserWindow(hwnd);
            if (!baseUrl.empty()) {
                tab.url = baseUrl;
                tab.domain = HostFromUrl(baseUrl);
                tab.valid = true;
            }
            app_info.metadata[flutter::EncodableValue("isBrowser")] = flutter::EncodableValue(true);
            if (tab.valid) {
                flutter::EncodableMap tab_map;
                tab_map[flutter::EncodableValue("domain")] = flutter::EncodableValue(tab.domain);
                tab_map[flutter::EncodableValue("url")] = flutter::EncodableValue(tab.url);
                tab_map[flutter::EncodableValue("title")] = flutter::EncodableValue(tab.title);
                tab_map[flutter::EncodableValue("browserType")] = flutter::EncodableValue(tab.browserType);
                app_info.metadata[flutter::EncodableValue("browserTab")] = flutter::EncodableValue(tab_map);
            }
        } else {
            app_info.metadata[flutter::EncodableValue("isBrowser")] = flutter::EncodableValue(false);
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
    // Check actual permissions
    HWND testWindow = GetForegroundWindow();
    bool hasWindowAccess = (testWindow != NULL);
    HWINEVENTHOOK testHook = SetWinEventHook(
        EVENT_SYSTEM_FOREGROUND, EVENT_SYSTEM_FOREGROUND,
        NULL, NULL, 0, 0,
        WINEVENT_OUTOFCONTEXT | WINEVENT_SKIPOWNPROCESS
    );
    bool hasHookAccess = (testHook != NULL);
    if (testHook != NULL) {
        UnhookWinEvent(testHook);
    }
    
    diagnostics[flutter::EncodableValue("hasPermissions")] = flutter::EncodableValue(hasWindowAccess && hasHookAccess);
    diagnostics[flutter::EncodableValue("hasWindowAccess")] = flutter::EncodableValue(hasWindowAccess);
    diagnostics[flutter::EncodableValue("hasHookAccess")] = flutter::EncodableValue(hasHookAccess);
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



