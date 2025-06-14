#ifndef FLUTTER_PLUGIN_FLUTTER_P2P_CONNECTION_PLUGIN_H_
#define FLUTTER_PLUGIN_FLUTTER_P2P_CONNECTION_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <memory>

namespace flutter_p2p_connection {

class FlutterP2pConnectionPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  FlutterP2pConnectionPlugin();

  virtual ~FlutterP2pConnectionPlugin();

  // Disallow copy and assign.
  FlutterP2pConnectionPlugin(const FlutterP2pConnectionPlugin&) = delete;
  FlutterP2pConnectionPlugin& operator=(const FlutterP2pConnectionPlugin&) = delete;

  // Called when a method is called on this plugin's channel from Dart.
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
};

}  // namespace flutter_p2p_connection

#endif  // FLUTTER_PLUGIN_FLUTTER_P2P_CONNECTION_PLUGIN_H_
