#include "app_focus_tracker_plugin.h"
#include <windows.h>
#include <string>
#include <chrono>
#include <thread>

namespace {

std::string GetWindowTitle(HWND hwnd) {
    char window_title[256];
    GetWindowTextA(hwnd, window_title, sizeof(window_title));
    return std::string(window_title);
}

}  // namespace

AppFocusTrackerPlugin::AppFocusTrackerPlugin() {}

AppFocusTrackerPlugin::~AppFocusTrackerPlugin() {
    StopTracking();
}

std::string AppFocusTrackerPlugin::GetActiveWindowTitle() {
    HWND hwnd = GetForegroundWindow();
    return GetWindowTitle(hwnd);
}

void AppFocusTrackerPlugin::StartTracking() {
    is_tracking_ = true;
    tracking_thread_ = std::thread([this]() {
        std::string activeAppName = "Unknown";

        while (is_tracking_) {
            std::string currentAppName = GetActiveWindowTitle();

            if (currentAppName != activeAppName) {
                activeAppName = currentAppName;
            }

            if (event_sink_) {
                flutter::EncodableMap event;
                event[flutter::EncodableValue("appName")] = flutter::EncodableValue(activeAppName);
                event[flutter::EncodableValue("duration")] = flutter::EncodableValue(1);
                event_sink_->Success(event);
            }

            std::this_thread::sleep_for(std::chrono::seconds(1));
        }
    });
}

void AppFocusTrackerPlugin::StopTracking() {
    is_tracking_ = false;
    if (tracking_thread_.joinable()) {
        tracking_thread_.join();
    }
}

std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>> AppFocusTrackerPlugin::OnListenInternal(
    const flutter::EncodableValue* arguments,
    std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>&& events) {
    event_sink_ = std::move(events);
    StartTracking();
    return nullptr;
}

std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>> AppFocusTrackerPlugin::OnCancelInternal(
    const flutter::EncodableValue* arguments) {
    StopTracking();
    event_sink_ = nullptr;
    return nullptr;
}

void AppFocusTrackerPlugin::RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar) {
    auto plugin = std::make_unique<AppFocusTrackerPlugin>();

    auto event_channel = std::make_unique<flutter::EventChannel<flutter::EncodableValue>>(
        registrar->messenger(), "app_focus_tracker", &flutter::StandardMethodCodec::GetInstance());

    event_channel->SetStreamHandler(plugin.get());
    registrar->AddPlugin(std::move(plugin));
}
