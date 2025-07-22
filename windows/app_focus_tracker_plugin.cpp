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
#include <cctype>
#include <regex>
// Compile-time switch: enable advanced URL extraction via UIAutomation (Windows only).
// Set to 1 if you want to experiment with UIAutomation; 0 keeps it disabled and
// avoids unused-function warnings during normal builds.
#define ENABLE_UIAUTOMATION 0

#include <UIAutomation.h>
#pragma comment(lib, "Oleacc.lib")

namespace {

// Debug output helper function
void DebugLog(const std::string& message) {
    std::cout << "[DEBUG] " << message << std::endl;
    OutputDebugStringA(("[DEBUG] " + message + "\n").c_str());
}

// Convert Win32 error code to readable string
std::string Win32ErrorMessage(DWORD error_code) {
    char* msg_buf = nullptr;
    size_t size = FormatMessageA(
        FORMAT_MESSAGE_ALLOCATE_BUFFER | FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS,
        NULL,
        error_code,
        MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT),
        (LPSTR)&msg_buf,
        0,
        NULL);
    std::string message;
    if (size && msg_buf) {
        message.assign(msg_buf, size);
        // Trim trailing CR/LF
        while (!message.empty() && (message.back() == '\n' || message.back() == '\r')) {
            message.pop_back();
        }
        LocalFree(msg_buf);
    } else {
        message = "Unknown error";
    }
    return message;
}

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
    } else {
        DWORD err = GetLastError();
        DebugLog("OpenProcess failed for PID " + std::to_string(info.processId) + ": " + std::to_string(err) + " (" + Win32ErrorMessage(err) + ")");
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
#if ENABLE_UIAUTOMATION
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
        std::cout << "[DEBUG] GetBaseURLFromBrowserWindow: hwnd is null" << std::endl;
        return "";
    }

    // Add exception handling wrapper around entire UIAutomation section
    try {
        bool comInit = false;
        // UI Automation clients must be single-threaded apartment (STA) COM objects.
        HRESULT hr = CoInitializeEx(NULL, COINIT_APARTMENTTHREADED);
        if (SUCCEEDED(hr)) {
            comInit = true;
        } else if (hr == RPC_E_CHANGED_MODE) {
            // This means the thread was already initialized as MTA.
            // UI Automation will likely fail, but we should not crash.
            std::cout << "[DEBUG] GetBaseURLFromBrowserWindow: COM already initialized as MTA, UI Automation will not work" << std::endl;
            return "";  // Return early to avoid UIAutomation issues
        } else {
            std::cout << "[DEBUG] GetBaseURLFromBrowserWindow: COM initialization failed: " << hr << std::endl;
            return "";
        }

        std::string result;
        int elementsFound = 0;
        int elementsProcessed = 0;

        IUIAutomation* automation = nullptr;
        hr = CoCreateInstance(__uuidof(CUIAutomation), nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&automation));
        if (!SUCCEEDED(hr)) {
            std::cout << "[DEBUG] GetBaseURLFromBrowserWindow: Failed to create UIAutomation instance: " << hr << std::endl;
            if (comInit) CoUninitialize();
            return "";
        }

        IUIAutomationElement* root = nullptr;
        hr = automation->ElementFromHandle(hwnd, &root);
        if (!SUCCEEDED(hr) || !root) {
            std::cout << "[DEBUG] GetBaseURLFromBrowserWindow: Failed to get element from window handle: " << hr << std::endl;
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
            std::cout << "[DEBUG] GetBaseURLFromBrowserWindow: Failed to create automation conditions" << std::endl;
        } else {
            IUIAutomationElementArray* elements = nullptr;
            hr = root->FindAll(TreeScope_Subtree, orCond, &elements);
            if (SUCCEEDED(hr) && elements) {
                elements->get_Length(&elementsFound);
                std::cout << "[DEBUG] GetBaseURLFromBrowserWindow: Found " << elementsFound << " elements" << std::endl;
                
                // Limit the number of elements we process to avoid performance issues
                int maxElements = (std::min)(elementsFound, 50);
                
                for (int i = 0; i < maxElements; ++i) {
                    IUIAutomationElement* el = nullptr;
                    if (SUCCEEDED(elements->GetElement(i, &el)) && el) {
                        elementsProcessed++;
                        
                        try {
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
                                try {
                                    BSTR bstr = nullptr;
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
                                } catch (...) {
                                    std::cout << "[DEBUG] GetBaseURLFromBrowserWindow: Exception in ValuePattern processing" << std::endl;
                                }
                                vp->Release();
                            }

                            // Fallback to Name property if still empty
                            if (result.empty()) {
                                try {
                                    BSTR nameBstr = nullptr;
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
                                } catch (...) {
                                    std::cout << "[DEBUG] GetBaseURLFromBrowserWindow: Exception in Name property processing" << std::endl;
                                }
                            }
                        } catch (...) {
                            std::cout << "[DEBUG] GetBaseURLFromBrowserWindow: Exception processing element " << i << std::endl;
                        }
                        
                        el->Release();
                    }
                }
                elements->Release();
            } else {
                std::cout << "[DEBUG] GetBaseURLFromBrowserWindow: FindAll failed or returned null: " << hr << std::endl;
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
            try {
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
            } catch (...) {
                std::cout << "[DEBUG] GetBaseURLFromBrowserWindow: Exception in regex processing" << std::endl;
            }
        }
        return "";
    } catch (...) {
        std::cout << "[DEBUG] GetBaseURLFromBrowserWindow: Critical exception caught - UIAutomation failed" << std::endl;
        return "";
    }
}
#endif // ENABLE_UIAUTOMATION
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
    std::transform(lowered.begin(), lowered.end(), lowered.begin(), [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
    if (kBrowserExecutables.count(lowered) > 0) {
        return true;
    }

    // Fallback: look for browser identifiers in executable path
    std::string path_lower = executable_path;
    std::transform(path_lower.begin(), path_lower.end(), path_lower.begin(), [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
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
    std::transform(proc_lower.begin(), proc_lower.end(), proc_lower.begin(), [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
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

    // Improved patterns for different browsers
    std::string page_title = window_title;
    
    try {
        // Chrome: "Page Title - Google Chrome"
        std::regex chrome_pattern(R"((.+?)\s*-\s*Google Chrome)", std::regex::icase);
        // Edge: "Page Title - Microsoft​ Edge" or "Page Title - Profile N - Microsoft​ Edge"
        std::regex edge_pattern(R"((.+?)\s*-\s*(?:Profile \d+\s*-\s*)?Microsoft[​\s]*Edge)", std::regex::icase);
        // Generic pattern for other browsers
        std::regex generic_pattern(R"((.+?)\s*-\s*(Brave|Mozilla Firefox|Firefox|Opera|Safari))", std::regex::icase);
        
        std::smatch match;
        if (std::regex_match(window_title, match, chrome_pattern) && match.size() > 1) {
            page_title = match[1].str();
            #ifdef _DEBUG
            std::cout << "[DEBUG] ExtractBrowserTabInfo: Extracted from Chrome pattern: '" << page_title << "'" << std::endl;
            #endif
        } else if (std::regex_match(window_title, match, edge_pattern) && match.size() > 1) {
            page_title = match[1].str();
            #ifdef _DEBUG
            std::cout << "[DEBUG] ExtractBrowserTabInfo: Extracted from Edge pattern: '" << page_title << "'" << std::endl;
            #endif
        } else if (std::regex_match(window_title, match, generic_pattern) && match.size() > 1) {
            page_title = match[1].str();
            #ifdef _DEBUG
            std::cout << "[DEBUG] ExtractBrowserTabInfo: Extracted from generic pattern: '" << page_title << "'" << std::endl;
            #endif
        } else {
            #ifdef _DEBUG
            std::cout << "[DEBUG] ExtractBrowserTabInfo: No pattern matched, using full title" << std::endl;
            #endif
        }
    } catch (...) {
        #ifdef _DEBUG
        std::cout << "[DEBUG] ExtractBrowserTabInfo: Regex processing failed, using full title" << std::endl;
        #endif
        page_title = window_title;
    }
    // Clean up the extracted title
    // Remove common artifacts and trim whitespace
    std::string cleaned_title = page_title;
    
    try {
        // Remove common prefixes/suffixes
        std::vector<std::string> artifacts_to_remove = {
            " - New Tab", " - New tab", " (Private)", " (Incognito)", 
            " - InPrivate", " - Private browsing"
        };
        
        for (const auto& artifact : artifacts_to_remove) {
            try {
                size_t pos = cleaned_title.find(artifact);
                if (pos != std::string::npos) {
                    cleaned_title = cleaned_title.substr(0, pos);
                }
            } catch (...) {
                // Continue with next artifact
                continue;
            }
        }
        
        // Trim whitespace
        try {
            cleaned_title.erase(0, cleaned_title.find_first_not_of(" \t\n\r"));
            cleaned_title.erase(cleaned_title.find_last_not_of(" \t\n\r") + 1);
        } catch (...) {
            // If trimming fails, just use the title as-is
        }
    } catch (...) {
        #ifdef _DEBUG
        std::cout << "[DEBUG] ExtractBrowserTabInfo: Exception in title cleanup, using original" << std::endl;
        #endif
        cleaned_title = page_title;
    }
    
    info.title = cleaned_title;

    // Extract domain from title (look for something that looks like a hostname)
    try {
        std::regex domain_regex(R"(([a-zA-Z0-9.-]+\.[a-zA-Z]{2,}))");
        std::smatch domain_match;
        if (std::regex_search(cleaned_title, domain_match, domain_regex) && domain_match.size() > 1) {
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
            try {
                std::vector<std::regex> fallback_patterns = {
                    std::regex(R"(https?://([^/\s]+))", std::regex::icase),  // Full URL: https://example.com
                    std::regex(R"(www\.([^/\s\-]+))", std::regex::icase),    // www.domain.com
                    std::regex(R"(([a-zA-Z0-9-]+\.(com|org|net|edu|gov|co\.uk|io|dev|app|info|biz|me|tv))", std::regex::icase),  // Extended TLDs
                    std::regex(R"(\b([a-zA-Z0-9-]+\.[a-zA-Z]{2,}\.[a-zA-Z]{2,})\b)", std::regex::icase),  // country domains like example.co.uk
                    std::regex(R"(\b([a-zA-Z0-9-]+\.[a-zA-Z]{2,})\b)", std::regex::icase)  // Basic domain pattern
                };
                
                for (size_t i = 0; i < fallback_patterns.size() && !info.valid; ++i) {
                    try {
                        std::smatch fallback_match;
                        if (std::regex_search(cleaned_title, fallback_match, fallback_patterns[i]) && fallback_match.size() > 1) {
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
                    } catch (...) {
                        #ifdef _DEBUG
                        std::cout << "[DEBUG] ExtractBrowserTabInfo: Exception in fallback pattern " << i << std::endl;
                        #endif
                        continue;
                    }
                }
            } catch (...) {
                #ifdef _DEBUG
                std::cout << "[DEBUG] ExtractBrowserTabInfo: Exception creating fallback patterns" << std::endl;
                #endif
            }
            
            if (!info.valid) {
                #ifdef _DEBUG
                std::cout << "[DEBUG] ExtractBrowserTabInfo: No domain found via any pattern" << std::endl;
                #endif
            }
        }
    } catch (...) {
        #ifdef _DEBUG
        std::cout << "[DEBUG] ExtractBrowserTabInfo: Exception in domain extraction, skipping" << std::endl;
        #endif
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
        DebugLog("WinEventProc: Foreground window changed to hwnd: " + std::to_string((uintptr_t)hwnd));
        g_plugin_instance->OnWindowFocusChanged(hwnd);
    }
}

// Add after global variables
static const wchar_t kMsgWindowClassName[] = L"AppFocusTrackerMsgWnd";

// ------------------ Message Window for Main-Thread Dispatch -------------

LRESULT CALLBACK AppFocusTrackerPlugin::MessageWndProc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp) {
    if (msg == kFlushMessageId) {
        DebugLog("MessageWndProc: Received flush message");
        if (g_plugin_instance) {
            g_plugin_instance->FlushEventQueue();
        }
        return 0;
    }
    return DefWindowProc(hwnd, msg, wp, lp);
}

void AppFocusTrackerPlugin::CreateMessageWindow() {
    DebugLog("CreateMessageWindow: Creating message window");
    
    // Register class if not already registered
    static bool class_registered = false;
    if (!class_registered) {
        WNDCLASSW wc = {};
        wc.lpfnWndProc = MessageWndProc;
        wc.lpszClassName = kMsgWindowClassName;
        wc.hInstance = GetModuleHandle(nullptr);
        
        ATOM result = RegisterClassW(&wc);
        if (result == 0) {
            // Registration failed, but we'll try to continue
            DebugLog("Failed to register message window class: " + std::to_string(GetLastError()));
        } else {
            class_registered = true;
            DebugLog("Successfully registered message window class");
        }
    }
    
    if (class_registered) {
        message_window_ = CreateWindowExW(0, kMsgWindowClassName, L"", 0, 0, 0, 0, 0,
                                          HWND_MESSAGE, nullptr, nullptr, nullptr);
        if (!message_window_) {
            DebugLog("Failed to create message window: " + std::to_string(GetLastError()));
        } else {
            DebugLog("Successfully created message window: " + std::to_string((uintptr_t)message_window_));
        }
    }
}

void AppFocusTrackerPlugin::DestroyMessageWindow() {
    if (message_window_) {
        DestroyWindow(message_window_);
        message_window_ = nullptr;
    }
}

bool AppFocusTrackerPlugin::IsOnPlatformThread() const {
    // Check if we're on the platform thread by comparing thread IDs
    DWORD current_thread_id = GetCurrentThreadId();
    bool is_platform_thread = (current_thread_id == platform_thread_id_);
    
    DebugLog("IsOnPlatformThread: Current thread ID: " + std::to_string(current_thread_id) + 
             ", Platform thread ID: " + std::to_string(platform_thread_id_) + 
             ", Is platform thread: " + (is_platform_thread ? "true" : "false"));
    
    return is_platform_thread;
}

void AppFocusTrackerPlugin::SendEventDirectly(const flutter::EncodableMap& event) {
    // This method should only be called from the platform thread
    DebugLog("SendEventDirectly: Attempting to send event directly");
    
    std::lock_guard<std::mutex> lock(event_sink_mutex_);
    if (event_sink_) {
        try {
            event_sink_->Success(event);
            DebugLog("SendEventDirectly: Successfully sent event");
        } catch (...) {
            // Handle any exceptions that might occur during event sending
            DebugLog("Exception occurred while sending event directly");
        }
    } else {
        DebugLog("SendEventDirectly: Event sink is null");
    }
}

void AppFocusTrackerPlugin::FlushEventQueue() {
    // This method is called from the platform thread via the message window
    DebugLog("FlushEventQueue: Processing queued events");
    
    std::queue<flutter::EncodableMap> local_queue;
    {
        std::lock_guard<std::mutex> lock(event_queue_mutex_);
        std::swap(local_queue, event_queue_);
    }
    
    DebugLog("FlushEventQueue: Processing " + std::to_string(local_queue.size()) + " events");
    
    // Process all queued events on the platform thread
    while (!local_queue.empty()) {
        const auto& event = local_queue.front();
        {
            std::lock_guard<std::mutex> lock(event_sink_mutex_);
            if (event_sink_) {
                try {
                    event_sink_->Success(event);
                    DebugLog("FlushEventQueue: Successfully sent event");
                } catch (...) {
                    // Handle any exceptions that might occur during event sending
                    // This prevents crashes if the event sink becomes invalid
                    DebugLog("FlushEventQueue: Exception occurred while sending event");
                }
            } else {
                DebugLog("FlushEventQueue: Event sink is null");
            }
        }
        local_queue.pop();
    }
}

AppFocusTrackerPlugin::AppFocusTrackerPlugin() 
    : is_tracking_(false), current_process_id_(0), focus_start_time_(std::chrono::steady_clock::now()),
      should_process_events_(false) {
    DebugLog("========================================");
    DebugLog("App Focus Tracker Plugin: Constructor called");
    DebugLog("========================================");
    
    // Capture the platform thread ID
    platform_thread_id_ = GetCurrentThreadId();
    DebugLog("Platform thread ID captured: " + std::to_string(platform_thread_id_));
    
    g_plugin_instance = this;
    CreateMessageWindow();
    
    DebugLog("AppFocusTrackerPlugin: Constructor completed");
}

AppFocusTrackerPlugin::~AppFocusTrackerPlugin() {
    std::cout << "[DEBUG] AppFocusTrackerPlugin: Destructor called" << std::endl;
    
    StopTracking();
    DestroyMessageWindow();
    g_plugin_instance = nullptr;
    
    std::cout << "[DEBUG] AppFocusTrackerPlugin: Destructor completed" << std::endl;
}

void AppFocusTrackerPlugin::RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar) {
    DebugLog("RegisterWithRegistrar: Registering plugin");
    
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
    
    // Forward declaration of wrapper class
    class AppFocusTrackerStreamHandler : public flutter::StreamHandler<flutter::EncodableValue> {
    public:
        AppFocusTrackerStreamHandler(AppFocusTrackerPlugin* plugin) : plugin_(plugin) {}
        ~AppFocusTrackerStreamHandler() override = default;

        std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>> OnListenInternal(
            const flutter::EncodableValue* arguments,
            std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>&& events) override {
            return plugin_->OnListenInternal(arguments, std::move(events));
        }

        std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>> OnCancelInternal(const flutter::EncodableValue* arguments) override {
            return plugin_->OnCancelInternal(arguments);
        }

    private:
        AppFocusTrackerPlugin* plugin_;
    };

    event_channel->SetStreamHandler(std::make_unique<AppFocusTrackerStreamHandler>(plugin.get()));
    
    registrar->AddPlugin(std::move(plugin));
    
    DebugLog("RegisterWithRegistrar: Plugin registered successfully");
}

void AppFocusTrackerPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
    
    const std::string& method = method_call.method_name();
    
    std::cout << "[DEBUG] HandleMethodCall: Method '" << method << "' called" << std::endl;
    
    if (method == "getPlatformName") {
        std::cout << "[DEBUG] HandleMethodCall: getPlatformName called" << std::endl;
        
        result->Success(flutter::EncodableValue("Windows"));
    }
    else if (method == "isSupported") {
        std::cout << "[DEBUG] HandleMethodCall: isSupported called" << std::endl;
        
        result->Success(flutter::EncodableValue(true));
    }
    else if (method == "hasPermissions") {
        std::cout << "[DEBUG] HandleMethodCall: hasPermissions called" << std::endl;
        
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
        std::cout << "[DEBUG] HandleMethodCall: requestPermissions called" << std::endl;
        
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
        std::cout << "[DEBUG] HandleMethodCall: openSystemSettings called" << std::endl;
        
        // On Windows, open the Privacy & Security settings
        ShellExecuteA(NULL, "open", "ms-settings:privacy", NULL, NULL, SW_SHOW);
        result->Success();
    }
    else if (method == "startTracking") {
        DebugLog("HandleMethodCall: startTracking called");
        
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
        std::cout << "[DEBUG] HandleMethodCall: stopTracking called" << std::endl;
        
        StopTracking();
        result->Success();
    }
    else if (method == "isTracking") {
        std::cout << "[DEBUG] HandleMethodCall: isTracking called, returning: " << (is_tracking_ ? "true" : "false") << std::endl;
        
        result->Success(flutter::EncodableValue(is_tracking_));
    }
    else if (method == "getCurrentFocusedApp") {
        std::cout << "[DEBUG] HandleMethodCall: getCurrentFocusedApp called" << std::endl;
        
        auto app_info = GetCurrentFocusedApp();
        if (app_info.processId != 0) {
            result->Success(flutter::EncodableValue(app_info.ToMap()));
        } else {
            result->Success();
        }
    }
    else if (method == "getRunningApplications") {
        std::cout << "[DEBUG] HandleMethodCall: getRunningApplications called" << std::endl;
        
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
        std::cout << "[DEBUG] HandleMethodCall: getDiagnosticInfo called" << std::endl;
        
        auto diagnostics = GetDiagnosticInfo();
        result->Success(flutter::EncodableValue(diagnostics));
    }
    else if (method == "debugUrlExtraction") {
        std::cout << "[DEBUG] HandleMethodCall: debugUrlExtraction called" << std::endl;
        
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
                // UIAutomation extraction disabled on Windows due to stability issues
                debug_info[flutter::EncodableValue("uiAutomationUrl")] = flutter::EncodableValue("DISABLED_ON_WINDOWS");
                debug_info[flutter::EncodableValue("uiAutomationNote")] = flutter::EncodableValue("UIAutomation disabled due to browser security restrictions causing crashes");
                
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
        std::cout << "[DEBUG] HandleMethodCall: Unknown method: " << method << std::endl;
        
        result->NotImplemented();
    }
}

void AppFocusTrackerPlugin::StartTracking() {
    if (is_tracking_) return;
    
    DebugLog("StartTracking: Starting focus tracking");
    
    is_tracking_ = true;
    session_id_ = GenerateSessionId();
    
    // Set up Windows event hook for foreground window changes
    g_event_hook = SetWinEventHook(
        EVENT_SYSTEM_FOREGROUND, EVENT_SYSTEM_FOREGROUND,
        NULL, WinEventProc, 0, 0,
        WINEVENT_OUTOFCONTEXT | WINEVENT_SKIPOWNPROCESS
    );
    
    DebugLog("StartTracking: Event hook created: " + std::string(g_event_hook ? "success" : "failed"));
    
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
    
    DebugLog("StartTracking: Focus tracking started successfully");
}

void AppFocusTrackerPlugin::StopTracking() {
    if (!is_tracking_) return;
    
    std::cout << "[DEBUG] StopTracking: Stopping focus tracking" << std::endl;
    
    is_tracking_ = false;
    
    // Clean up event queue
    {
        std::lock_guard<std::mutex> lock(event_queue_mutex_);
        std::queue<flutter::EncodableMap> empty;
        std::swap(event_queue_, empty);
    }
    
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
    
    std::cout << "[DEBUG] StopTracking: Focus tracking stopped successfully" << std::endl;
}

void AppFocusTrackerPlugin::OnWindowFocusChanged(HWND hwnd) {
    if (!is_tracking_ || !hwnd) return;
    
    bool on_platform_thread = IsOnPlatformThread();
    DebugLog("OnWindowFocusChanged: Window focus changed to hwnd: " + std::to_string((uintptr_t)hwnd) + 
             ", on platform thread: " + (on_platform_thread ? "true" : "false"));
    
    ProcessInfo proc_info = GetProcessInfoFromWindow(hwnd);
    if (proc_info.processId == 0) return;
    
    auto current_time = std::chrono::steady_clock::now();
    
    // Send focus lost event for previous app
    if (current_process_id_ != 0 && current_process_id_ != proc_info.processId) {
        auto duration = std::chrono::duration_cast<std::chrono::microseconds>(current_time - focus_start_time_).count();
        AppInfo prev_app_info = CreateAppInfo(current_focused_window_, !on_platform_thread);
        SendFocusEvent(prev_app_info, "lost", duration);
    }
    
    // Update current focus
    if (current_process_id_ != proc_info.processId) {
        current_process_id_ = proc_info.processId;
        current_focused_window_ = hwnd;
        focus_start_time_ = current_time;
        
        // Send focus gained event
        AppInfo app_info = CreateAppInfo(hwnd, !on_platform_thread);
        SendFocusEvent(app_info, "gained", 0);
    }
}

void AppFocusTrackerPlugin::SendCurrentFocusEvent() {
    DebugLog("SendCurrentFocusEvent: Getting current focused window");
    
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
    
    DebugLog("SendPeriodicUpdate: Sending periodic update");
    
    auto current_time = std::chrono::steady_clock::now();
    auto duration = std::chrono::duration_cast<std::chrono::microseconds>(current_time - focus_start_time_).count();
    
    AppInfo app_info = CreateAppInfo(current_focused_window_, true); // true = from_background_thread
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
    
    // Get basic app info without UI Automation (safe for background threads)
    HWND hwnd = current_focused_window_;
    if (!hwnd) return;
    
    ProcessInfo proc_info = GetProcessInfoFromWindow(hwnd);
    if (proc_info.processId == 0) return;
    
    // Check if current app is a browser
    if (!IsBrowserProcess(proc_info.processName, proc_info.executablePath)) {
        // Not a browser, clear last tab info
        last_browser_tab_info_.clear();
        return;
    }
    
    // For browser tab tracking, we'll use window title extraction only
    // UI Automation will be handled in the main thread when CreateAppInfo is called
    BrowserTabInfo tab_info = ExtractBrowserTabInfo(proc_info.windowTitle, proc_info.processName);
    
    // Build comparison key
    std::string current_tab_info;
    if (!tab_info.domain.empty()) {
        current_tab_info = tab_info.domain;
    } else if (!tab_info.url.empty()) {
        current_tab_info = tab_info.url;
    } else if (!tab_info.title.empty()) {
        // Fall back to sanitized title (remove numbers, dots, commas that might change frequently)
        std::string raw_title = tab_info.title;
        current_tab_info.reserve(raw_title.size());
        for (char c : raw_title) {
            if (!(c >= '0' && c <= '9') && c != '.' && c != ',') {
                current_tab_info.push_back(c);
            }
        }
    } else {
        // Last resort: use window title directly
        current_tab_info = proc_info.windowTitle;
    }
    
    // Check if tab info has changed
    auto last_tab_it = last_browser_tab_info_.find(proc_info.executablePath);
    if (last_tab_it != last_browser_tab_info_.end()) {
        if (last_tab_it->second != current_tab_info) {
            // Tab has changed, send tab change event
            // Create a basic AppInfo for the event
            AppInfo app_info;
            app_info.name = proc_info.windowTitle.empty() ? proc_info.processName : proc_info.windowTitle;
            app_info.identifier = proc_info.executablePath;
            app_info.processId = proc_info.processId;
            app_info.executablePath = proc_info.executablePath;
            
            // Add basic browser metadata
            app_info.metadata[flutter::EncodableValue("isBrowser")] = flutter::EncodableValue(true);
            app_info.metadata[flutter::EncodableValue("processName")] = flutter::EncodableValue(proc_info.processName);
            app_info.metadata[flutter::EncodableValue("windowTitle")] = flutter::EncodableValue(proc_info.windowTitle);
            
            if (tab_info.valid) {
                flutter::EncodableMap tab_map;
                tab_map[flutter::EncodableValue("domain")] = flutter::EncodableValue(tab_info.domain);
                tab_map[flutter::EncodableValue("url")] = flutter::EncodableValue(tab_info.url);
                tab_map[flutter::EncodableValue("title")] = flutter::EncodableValue(tab_info.title);
                tab_map[flutter::EncodableValue("browserType")] = flutter::EncodableValue(tab_info.browserType);
                app_info.metadata[flutter::EncodableValue("browserTab")] = flutter::EncodableValue(tab_map);
            }
            
            SendBrowserTabChangeEvent(app_info, last_tab_it->second, current_tab_info);
            last_tab_it->second = current_tab_info;
        }
    } else {
        // First time seeing this tab, just store it
        last_browser_tab_info_[proc_info.executablePath] = current_tab_info;
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
    
    DebugLog("SendFocusEvent: Creating event for " + app_info.name + " (" + event_type + ")");
    
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
    
    // Queue the event for processing on the main thread
    QueueEvent(event);
}

void AppFocusTrackerPlugin::QueueEvent(const flutter::EncodableMap& event) {
    // Check if we're already on the platform thread
    if (IsOnPlatformThread()) {
        DebugLog("QueueEvent: Already on platform thread, sending directly");
        // We're on the platform thread, send directly
        SendEventDirectly(event);
        return;
    }
    
    DebugLog("QueueEvent: Queuing event from background thread");
    
    {
        std::lock_guard<std::mutex> lock(event_queue_mutex_);
        event_queue_.push(event);

        // Guard against unbounded queue growth
        static const size_t kMaxQueueSize = 1000;
        if (event_queue_.size() > kMaxQueueSize) {
            size_t to_drop = event_queue_.size() - kMaxQueueSize;
            DebugLog("Event queue exceeded " + std::to_string(kMaxQueueSize) + " items; dropping " + std::to_string(to_drop) + " oldest events");
            while (to_drop-- > 0 && !event_queue_.empty()) {
                event_queue_.pop();
            }
        }
    }

    // Notify the message window (which lives on the platform/UI thread) to flush the queue.
    if (message_window_ != nullptr) {
        BOOL result = PostMessage(message_window_, kFlushMessageId, 0, 0);
        if (!result) {
            DWORD err = GetLastError();
            DebugLog("PostMessage failed (" + std::to_string(err) + "), scheduling retry");

            // Schedule a lightweight retry using a one-shot timer so we don't block
            // the background thread and avoid tight retry loops.
            constexpr UINT_PTR kRetryTimerId = 0xAF01; // arbitrary, unique per-class
            constexpr UINT kRetryDelayMs = 20;         // small delay before retrying

            auto hwndCopy = message_window_;

            // Use a static callback function for SetTimer
            // Define a traditional function pointer that can be used with SetTimer
            class TimerCallbackHelper {
            public:
                static VOID CALLBACK TimerProc(HWND hwnd, UINT /*msg*/, UINT_PTR id, DWORD /*time*/) {
                    constexpr UINT_PTR kRetryTimerId = 0xAF01;
                    if (id != kRetryTimerId) return;
                    KillTimer(hwnd, kRetryTimerId);
                    constexpr UINT kFlushMessageId = WM_APP + 0x40; // same as in header
                    BOOL ok = PostMessage(hwnd, kFlushMessageId, 0, 0);
                    if (!ok) {
                        DebugLog("Retry PostMessage failed again: " + std::to_string(GetLastError()));
                    } else {
                        DebugLog("Retry PostMessage succeeded");
                    }
                }
            };

            // SetTimer must be called on the same thread that owns message_window_.
            // We therefore post a WM_NULL to that window which sets the timer.
            PostMessage(message_window_, WM_NULL, 0, 0);

            // Set the timer directly — if called from a background thread, Windows will
            // route the WM_TIMER to the message_window_ thread because the HWND owns it.
            if (!SetTimer(message_window_, kRetryTimerId, kRetryDelayMs, TimerCallbackHelper::TimerProc)) {
                DebugLog("SetTimer for PostMessage retry failed: " + std::to_string(GetLastError()));
            }
        } else {
            DebugLog("Successfully posted flush message to window");
        }
    } else {
        DebugLog("Message window is null, cannot post flush message");
        // Don't fallback to direct sending - this would cause the threading error
    }
}

#if 0
void AppFocusTrackerPlugin::ProcessEventQueue() {}
void AppFocusTrackerPlugin::SendEventOnMainThread(const flutter::EncodableMap& event) {}
#endif

#if 0
void AppFocusTrackerPlugin::ProcessEventQueue() {
    // Removed – no longer used.
}
#endif

#if 0
void AppFocusTrackerPlugin::SendEventOnMainThread(const flutter::EncodableMap& event) {
    // Removed – no longer used.
}
#endif

AppInfo AppFocusTrackerPlugin::CreateAppInfo(HWND hwnd, bool from_background_thread) {
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
        try {
            app_info.metadata[flutter::EncodableValue("processName")] = flutter::EncodableValue(proc_info.processName);
            app_info.metadata[flutter::EncodableValue("windowTitle")] = flutter::EncodableValue(proc_info.windowTitle);
            
            // Get window rectangle
            try {
                RECT rect;
                if (GetWindowRect(hwnd, &rect)) {
                    flutter::EncodableMap window_rect;
                    window_rect[flutter::EncodableValue("left")] = flutter::EncodableValue(rect.left);
                    window_rect[flutter::EncodableValue("top")] = flutter::EncodableValue(rect.top);
                    window_rect[flutter::EncodableValue("right")] = flutter::EncodableValue(rect.right);
                    window_rect[flutter::EncodableValue("bottom")] = flutter::EncodableValue(rect.bottom);
                    app_info.metadata[flutter::EncodableValue("windowRect")] = flutter::EncodableValue(window_rect);
                }
            } catch (...) {
                DebugLog("CreateAppInfo: Exception getting window rectangle");
            }
            
            // Check if window is maximized
            try {
                WINDOWPLACEMENT placement = { sizeof(WINDOWPLACEMENT) };
                if (GetWindowPlacement(hwnd, &placement)) {
                    app_info.metadata[flutter::EncodableValue("isMaximized")] = 
                        flutter::EncodableValue(placement.showCmd == SW_SHOWMAXIMIZED);
                }
            } catch (...) {
                DebugLog("CreateAppInfo: Exception getting window placement");
            }
        } catch (...) {
            DebugLog("CreateAppInfo: Exception building basic metadata");
        }
    }
    
    // Check if application is a browser and extract tab info
    // This should happen regardless of metadata settings
    try {
        if (IsBrowserProcess(proc_info.processName, proc_info.executablePath)) {
            DebugLog("CreateAppInfo: Processing browser - " + proc_info.processName);
            
            BrowserTabInfo tab;
            try {
                tab = ExtractBrowserTabInfo(proc_info.windowTitle, proc_info.processName);
            } catch (...) {
                DebugLog("CreateAppInfo: Exception in ExtractBrowserTabInfo, using defaults");
                tab.browserType = "browser";
                tab.title = proc_info.windowTitle;
                tab.valid = false;
            }

            // Disable UIAutomation for all browsers on Windows due to stability issues
            // Modern browsers often block UIAutomation access, causing crashes
            // We'll rely on window title extraction instead, which is more reliable
            // Note: macOS uses a different API (Accessibility API) which works fine
             #if ENABLE_UIAUTOMATION
             if (!from_background_thread) {
                std::string baseUrl = GetBaseURLFromBrowserWindow(hwnd);
                if (!baseUrl.empty()) {
                    tab.url = baseUrl;
                    tab.domain = HostFromUrl(baseUrl);
                    tab.valid = true;
                }
             }
             #endif
            
            // Only add browser metadata if metadata is enabled
            if (config_.includeMetadata) {
                try {
                    app_info.metadata[flutter::EncodableValue("isBrowser")] = flutter::EncodableValue(true);
                    
                    if (tab.valid && !tab.domain.empty()) {
                        flutter::EncodableMap tab_map;
                        tab_map[flutter::EncodableValue("domain")] = flutter::EncodableValue(tab.domain);
                        tab_map[flutter::EncodableValue("url")] = flutter::EncodableValue(tab.url);
                        tab_map[flutter::EncodableValue("title")] = flutter::EncodableValue(tab.title);
                        tab_map[flutter::EncodableValue("browserType")] = flutter::EncodableValue(tab.browserType);
                        app_info.metadata[flutter::EncodableValue("browserTab")] = flutter::EncodableValue(tab_map);
                        DebugLog("CreateAppInfo: Added browser tab metadata");
                    } else {
                        // Still add basic browser info even if tab extraction failed
                        flutter::EncodableMap basic_tab_map;
                        basic_tab_map[flutter::EncodableValue("browserType")] = flutter::EncodableValue(tab.browserType);
                        basic_tab_map[flutter::EncodableValue("title")] = flutter::EncodableValue(tab.title);
                        app_info.metadata[flutter::EncodableValue("browserTab")] = flutter::EncodableValue(basic_tab_map);
                        DebugLog("CreateAppInfo: Added basic browser metadata only");
                    }
                } catch (...) {
                    DebugLog("CreateAppInfo: Exception adding browser metadata to map");
                    // Continue without browser-specific metadata
                }
            }
        } else {
            // Only add isBrowser=false if metadata is enabled
            if (config_.includeMetadata) {
                try {
                    app_info.metadata[flutter::EncodableValue("isBrowser")] = flutter::EncodableValue(false);
                } catch (...) {
                    DebugLog("CreateAppInfo: Exception setting isBrowser=false");
                }
            }
        }
    } catch (...) {
        DebugLog("CreateAppInfo: Critical exception in browser processing, continuing without browser metadata");
        if (config_.includeMetadata) {
            try {
                app_info.metadata[flutter::EncodableValue("isBrowser")] = flutter::EncodableValue(false);
            } catch (...) {
                // Even this failed, continue without any metadata
            }
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
            } else {
                DWORD err = GetLastError();
                DebugLog("OpenProcess failed in snapshot loop for PID " + std::to_string(pe32.th32ProcessID) + ": " + std::to_string(err) + " (" + Win32ErrorMessage(err) + ")");
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
    // This is called on the platform thread
    DebugLog("OnListenInternal: Setting up event sink");
    
    std::lock_guard<std::mutex> lock(event_sink_mutex_);
    event_sink_ = std::move(events);
    
    // If we have any queued events, flush them now
    FlushEventQueue();
    
    DebugLog("OnListenInternal: Event sink setup complete");
    
    return nullptr;
}

std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>>
AppFocusTrackerPlugin::OnCancelInternal(const flutter::EncodableValue* arguments) {
    // This is called on the platform thread
    std::cout << "[DEBUG] OnCancelInternal: Clearing event sink" << std::endl;
    
    std::lock_guard<std::mutex> lock(event_sink_mutex_);
    event_sink_ = nullptr;
    return nullptr;
}



