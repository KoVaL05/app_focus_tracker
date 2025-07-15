#ifndef FLUTTER_PLUGIN_APP_FOCUS_TRACKER_PLUGIN_C_API_H_
#define FLUTTER_PLUGIN_APP_FOCUS_TRACKER_PLUGIN_C_API_H_

#include <flutter/plugin_registrar_windows.h>

#ifdef __cplusplus
extern "C" {
#endif

FLUTTER_PLUGIN_EXPORT void AppFocusTrackerPluginRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar);

// Deprecated alias kept for backward compatibility. Will be removed in future major version.
FLUTTER_PLUGIN_EXPORT void AppFocusTrackerPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar);

#ifdef __cplusplus
}  // extern "C"
#endif

#endif  // FLUTTER_PLUGIN_APP_FOCUS_TRACKER_PLUGIN_C_API_H_
