#include "include/app_focus_tracker/app_focus_tracker_plugin_c_api.h"
#include "app_focus_tracker_plugin.h"

// Ensure the registration functions are exported from the DLL
#ifndef FLUTTER_PLUGIN_EXPORT
#define FLUTTER_PLUGIN_EXPORT
#endif

FLUTTER_PLUGIN_EXPORT void AppFocusTrackerPluginRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
    AppFocusTrackerPlugin::RegisterWithRegistrar(
        flutter::PluginRegistrarManager::GetInstance()
            ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}

// Deprecated alias for backward compatibility
FLUTTER_PLUGIN_EXPORT void AppFocusTrackerPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
    AppFocusTrackerPluginRegisterWithRegistrar(registrar);
}
