#ifndef FLUTTER_PLUGIN_APP_FOCUS_TRACKER_PLUGIN_C_API_H_
#define FLUTTER_PLUGIN_APP_FOCUS_TRACKER_PLUGIN_C_API_H_

#include <flutter_plugin_registrar.h>

#ifdef __cplusplus
extern "C" {
#endif

// Ensure FLUTTER_PLUGIN_EXPORT is defined
#ifndef FLUTTER_PLUGIN_EXPORT
#if defined(_WIN32)
#define FLUTTER_PLUGIN_EXPORT __declspec(dllexport)
#else
#define FLUTTER_PLUGIN_EXPORT __attribute__((visibility("default")))
#endif
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
