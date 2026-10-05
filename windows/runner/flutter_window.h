#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <flutter/encodable_value.h>

#include <memory>

#include "win32_window.h"
#include "glass_backdrop.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> theme_channel_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> lifecycle_channel_;
  bool close_ready_ = false;
  bool close_pending_ = false;
  bool close_approved_ = false;
  void ApplyTheme();
  COLORREF caption_color_ = RGB(255, 255, 255);
  COLORREF text_color_ = RGB(20, 20, 20);
  BOOL dark_mode_ = FALSE;
  bool has_theme_ = false;
  bool glass_mode_ = false;
  bool backdrop_applied_ = false;
  GlassBackdrop glass_backdrop_;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
