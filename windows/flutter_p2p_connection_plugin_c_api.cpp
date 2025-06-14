#include "include/flutter_p2p_connection/flutter_p2p_connection_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "flutter_p2p_connection_plugin.h"

void FlutterP2pConnectionPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  flutter_p2p_connection::FlutterP2pConnectionPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
