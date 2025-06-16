#include "pch.h"
#include "flutter_p2p_connection_plugin.h"
#include "constants.h"
#include "utils.h"

namespace flutter_p2p_connection {

void FlutterP2pConnectionPlugin::RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar) {
    auto plugin = std::make_unique<FlutterP2pConnectionPlugin>(registrar);
    auto channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
        registrar->messenger(), Constants::METHOD_CHANNEL_NAME,
        &flutter::StandardMethodCodec::GetInstance());

    channel->SetMethodCallHandler(
        [plugin_pointer = plugin.get()](const auto& call, auto result) {
            plugin_pointer->HandleMethodCall(call, std::move(result));
        });

    registrar->AddPlugin(std::move(plugin));
}

FlutterP2pConnectionPlugin::FlutterP2pConnectionPlugin(flutter::PluginRegistrarWindows* registrar)
    : registrar_(registrar) {
    // Initialize COM for WinRT and other COM-based APIs on this thread.
    winrt::init_apartment();

    // TODO: Instantiate manager classes here, passing the registrar or messenger
    // service_manager_ = std::make_unique<ServiceManager>(registrar);
    // ble_manager_ = std::make_unique<BleManager>(registrar);
}

FlutterP2pConnectionPlugin::~FlutterP2pConnectionPlugin() {
    // TODO: Clean up resources if needed
    // ble_manager_->Dispose();
    winrt::uninit_apartment();
}

void FlutterP2pConnectionPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {

    const std::string& method = method_call.method_name();

    if (method == "getPlatformVersion") {
        OSVERSIONINFOEXW os_info = { sizeof(os_info) };
        if (RtlGetVersion(&os_info) == 0) {
            std::wstringstream ss;
            ss << L"Windows " << os_info.dwMajorVersion << L"." << os_info.dwMinorVersion << L" Build " << os_info.dwBuildNumber;
            result->Success(flutter::EncodableValue(utils::wstring_to_string(ss.str())));
        } else {
            result->Error("VERSION_ERROR", "Failed to get Windows version.");
        }
    }
    // TODO: Route method calls to the appropriate manager class
    /*
    else if (method == "checkBluetoothEnabled") {
        service_manager_->CheckBluetoothEnabled(std::move(result));
    }
    else if (method.rfind("ble#", 0) == 0) {
        ble_manager_->HandleMethodCall(method, method_call.arguments(), std::move(result));
    }
    */
    else {
        result->NotImplemented();
    }
}

} 