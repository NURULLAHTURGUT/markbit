#include "flutter_window.h"

#include <optional>
#include <dwmapi.h>
#include <flutter/standard_method_codec.h>
#include <flutter/method_result_functions.h>

#include "flutter/generated_plugin_registrant.h"

namespace {
// Native transparency lets the controlled desktop blur show through Flutter.
bool SetGlassComposition(HWND window, bool enabled) {
  struct Accent {
    int state;
    int flags;
    DWORD tint;
    int animation;
  };
  struct CompositionAttribute {
    int attribute;
    void* value;
    SIZE_T size;
  };
  using SetComposition = BOOL(WINAPI*)(HWND, CompositionAttribute*);
  const auto user32 = GetModuleHandleW(L"user32.dll");
  const auto set_composition = user32 ? reinterpret_cast<SetComposition>(
      GetProcAddress(user32, "SetWindowCompositionAttribute")) : nullptr;
  if (!set_composition) return false;
  Accent accent{enabled ? 2 : 0, 2, 0, 0};
  CompositionAttribute attribute{19, &accent, sizeof(accent)};
  return set_composition(window, &attribute) != FALSE;
}
}  // namespace

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
  lifecycle_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "markbit/lifecycle",
      &flutter::StandardMethodCodec::GetInstance());
  lifecycle_channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    if (call.method_name() == "ready") { close_ready_ = true; result->Success(); }
    else result->NotImplemented();
  });
  SetChildContent(flutter_controller_->view()->GetNativeWindow());
  theme_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "markbit/window_theme",
      &flutter::StandardMethodCodec::GetInstance());
  theme_channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    if (call.method_name() == "setTitle") {
      const auto* title = std::get_if<std::string>(call.arguments());
      if (!title) { result->Error("arguments", "Expected a title"); return; }
      const int length = MultiByteToWideChar(CP_UTF8, 0, title->c_str(), -1, nullptr, 0);
      std::wstring wide(length > 0 ? length : 1, L'\0');
      if (length > 0) MultiByteToWideChar(CP_UTF8, 0, title->c_str(), -1, wide.data(), length);
      SetWindowText(GetHandle(), wide.c_str());
      result->Success();
      return;
    }
    if (call.method_name() != "setTheme") { result->NotImplemented(); return; }
    const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
    if (!args) { result->Error("arguments", "Expected theme colors"); return; }
    auto color = [args](const char* key, COLORREF fallback) {
      const auto entry = args->find(flutter::EncodableValue(key));
      if (entry == args->end()) return fallback;
      int64_t value = 0;
      if (const auto* value32 = std::get_if<int32_t>(&entry->second)) value = *value32;
      else if (const auto* value64 = std::get_if<int64_t>(&entry->second)) value = *value64;
      else return fallback;
      return RGB((value >> 16) & 255, (value >> 8) & 255, value & 255);
    };
    caption_color_ = color("background", caption_color_);
    text_color_ = color("foreground", text_color_);
    const auto dark = args->find(flutter::EncodableValue("dark"));
    if (dark != args->end()) {
      if (const auto* value = std::get_if<bool>(&dark->second)) dark_mode_ = *value;
    }
    has_theme_ = true;
    const auto glass = args->find(flutter::EncodableValue("glass"));
    glass_mode_ = glass != args->end() &&
                  std::get_if<bool>(&glass->second) &&
                  std::get<bool>(glass->second);
    ApplyTheme();
    result->Success(flutter::EncodableValue(backdrop_applied_));
  });

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
  glass_backdrop_.Disable();
  lifecycle_channel_ = nullptr;
  theme_channel_ = nullptr;
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

void FlutterWindow::ApplyTheme() {
  const HWND hwnd = GetHandle();
  const DWM_SYSTEMBACKDROP_TYPE none = DWMSBT_NONE;
  DwmSetWindowAttribute(hwnd, DWMWA_SYSTEMBACKDROP_TYPE, &none, sizeof(none));
  const BOOL host_backdrop = glass_mode_ ? TRUE : FALSE;
  DwmSetWindowAttribute(hwnd, DWMWA_USE_HOSTBACKDROPBRUSH, &host_backdrop, sizeof(host_backdrop));
  const bool accent_applied = SetGlassComposition(hwnd, glass_mode_);
  backdrop_applied_ = glass_mode_ && accent_applied;
  if (backdrop_applied_) backdrop_applied_ = glass_backdrop_.Enable(hwnd);
  if (!backdrop_applied_) {
    glass_backdrop_.Disable();
    SetGlassComposition(hwnd, false);
  }
  // Full negative margins are only for the system brush. Keep the ordinary
  // client frame when using the blur composition accent.
  const MARGINS margins = backdrop_applied_ && !accent_applied
      ? MARGINS{-1, -1, -1, -1} : MARGINS{0, 0, 1, 0};
  if (FAILED(DwmExtendFrameIntoClientArea(hwnd, &margins))) backdrop_applied_ = false;
  const COLORREF caption = backdrop_applied_
      ? (dark_mode_ ? RGB(30, 36, 44) : RGB(226, 231, 236))
      : caption_color_;
  DwmSetWindowAttribute(hwnd, DWMWA_USE_IMMERSIVE_DARK_MODE, &dark_mode_, sizeof(dark_mode_));
  DwmSetWindowAttribute(hwnd, DWMWA_CAPTION_COLOR, &caption, sizeof(caption));
  DwmSetWindowAttribute(hwnd, DWMWA_TEXT_COLOR, &text_color_, sizeof(text_color_));
  DwmSetWindowAttribute(hwnd, DWMWA_BORDER_COLOR, &caption_color_, sizeof(caption_color_));
  RedrawWindow(hwnd, nullptr, nullptr, RDW_FRAME | RDW_INVALIDATE);
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (message == WM_CLOSE && close_ready_ && !close_approved_ && lifecycle_channel_) {
    if (close_pending_) return 0;
    close_pending_ = true;
    EnableWindow(hwnd, FALSE);
    lifecycle_channel_->InvokeMethod("requestClose", nullptr,
      std::make_unique<flutter::MethodResultFunctions<flutter::EncodableValue>>(
        [this, hwnd](const flutter::EncodableValue* result) {
          close_pending_ = false;
          if (result && std::get_if<bool>(result) && std::get<bool>(*result)) {
            close_approved_ = true;
            PostMessage(hwnd, WM_CLOSE, 0, 0);
          } else { EnableWindow(hwnd, TRUE); }
        },
        [this, hwnd](const std::string&, const std::string&, const flutter::EncodableValue*) {
          close_pending_ = false;
          EnableWindow(hwnd, TRUE);
        },
        [this, hwnd]() { close_pending_ = false; EnableWindow(hwnd, TRUE); }));
    return 0;
  }
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

  const LRESULT result = Win32Window::MessageHandler(hwnd, message, wparam, lparam);
  if (glass_mode_ && (message == WM_WINDOWPOSCHANGED || message == WM_SIZE ||
                      message == WM_SHOWWINDOW || message == WM_ACTIVATE)) {
    glass_backdrop_.Update(hwnd);
  }
  if (has_theme_ && (message == WM_SETTINGCHANGE || message == WM_THEMECHANGED ||
                    message == WM_DWMCOLORIZATIONCOLORCHANGED ||
                    message == WM_DWMCOMPOSITIONCHANGED)) ApplyTheme();
  return result;
}
