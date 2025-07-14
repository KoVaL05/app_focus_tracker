#ifndef FLUTTER_PLUGIN_APP_FOCUS_TRACKER_PLUGIN_C_API_H_
#define FLUTTER_PLUGIN_APP_FOCUS_TRACKER_PLUGIN_C_API_H_

#include <flutter_plugin_registrar.h>

#ifdef __cplusplus
extern "C" {
#endif

void AppFocusTrackerPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar);

#ifdef __cplusplus
}  // extern "C"
#endif

#endif  // FLUTTER_PLUGIN_APP_FOCUS_TRACKER_PLUGIN_C_API_H_
