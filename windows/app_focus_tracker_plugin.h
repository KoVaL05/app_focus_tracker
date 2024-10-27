#ifndef FLUTTER_PLUGIN_APP_FOCUS_TRACKER_PLUGIN_H_
#define FLUTTER_PLUGIN_APP_FOCUS_TRACKER_PLUGIN_H_

#include <flutter/event_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <memory>
#include <string>
#include <thread>

class AppFocusTrackerPlugin : public flutter::Plugin, public flutter::StreamHandler<flutter::EncodableValue> {
public:
    static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);

    AppFocusTrackerPlugin();
    virtual ~AppFocusTrackerPlugin();

private:
    std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> event_sink_;
    std::thread tracking_thread_;
    bool is_tracking_ = false;

    std::string GetActiveWindowTitle();
    void StartTracking();
    void StopTracking();

    // StreamHandler methods
    std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>> OnListenInternal(
        const flutter::EncodableValue* arguments, std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>&& events) override;
    std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>> OnCancelInternal(const flutter::EncodableValue* arguments) override;
};

#endif  // FLUTTER_PLUGIN_APP_FOCUS_TRACKER_PLUGIN_H_
