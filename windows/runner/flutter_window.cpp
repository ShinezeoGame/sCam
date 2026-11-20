#include "flutter_window.h"

#include <flutter/standard_method_codec.h>

#include <optional>
#include <string>
#include <variant>

#include "flutter/generated_plugin_registrant.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());

  // Canal « scam/systeme » : alerte (la fenêtre clignote dans la barre des tâches et
  // Windows joue son son de notification), veille empêchée pendant que la webcam filme,
  // batterie d'un portable.
  system_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "scam/systeme",
      &flutter::StandardMethodCodec::GetInstance());
  system_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        if (call.method_name() == "alerte") {
          FLASHWINFO flash = {};
          flash.cbSize = sizeof(flash);
          flash.hwnd = GetHandle();
          flash.dwFlags = FLASHW_ALL | FLASHW_TIMERNOFG;
          ::FlashWindowEx(&flash);
          ::MessageBeep(MB_ICONEXCLAMATION);
          result->Success();
        } else if (call.method_name() == "serviceDemarrer") {
          // Caméra (webcam du PC) : l'ordinateur ne se met pas en veille tant qu'elle filme.
          // L'écran, lui, peut s'éteindre.
          const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
          bool camera = false;
          if (args) {
            auto it = args->find(flutter::EncodableValue("mode"));
            if (it != args->end()) {
              const auto* mode = std::get_if<std::string>(&it->second);
              camera = mode && *mode == "camera";
            }
          }
          ::SetThreadExecutionState(camera ? (ES_CONTINUOUS | ES_SYSTEM_REQUIRED) : ES_CONTINUOUS);
          result->Success();
        } else if (call.method_name() == "serviceArreter") {
          ::SetThreadExecutionState(ES_CONTINUOUS);
          result->Success();
        } else if (call.method_name() == "batterie") {
          // Portable : charge et secteur. Un PC fixe n'a pas de batterie (aucune valeur).
          flutter::EncodableMap battery;
          SYSTEM_POWER_STATUS power;
          if (::GetSystemPowerStatus(&power) && power.BatteryLifePercent <= 100 &&
              (power.BatteryFlag & 128) == 0) {
            battery[flutter::EncodableValue("niveau")] =
                flutter::EncodableValue(static_cast<int>(power.BatteryLifePercent));
            battery[flutter::EncodableValue("enCharge")] =
                flutter::EncodableValue(power.ACLineStatus == 1);
          }
          result->Success(flutter::EncodableValue(battery));
        } else {
          result->NotImplemented();
        }
      });
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  system_channel_ = nullptr;
  ::SetThreadExecutionState(ES_CONTINUOUS);
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
