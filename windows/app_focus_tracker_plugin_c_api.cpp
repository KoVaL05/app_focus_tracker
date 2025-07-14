#include "include/app_focus_tracker/app_focus_tracker_plugin_c_api.h"
#include "app_focus_tracker_plugin.h"

void AppFocusTrackerPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
    AppFocusTrackerPlugin::RegisterWithRegistrar(
        flutter::PluginRegistrarManager::GetInstance()
            ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
