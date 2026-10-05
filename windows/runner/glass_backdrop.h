#pragma once
#include <windows.h>
#include <memory>

// A desktop-sampling blur with an explicit radius, without Acrylic's opaque
// luminosity/tint recipe. It sits underneath Flutter's native child window.
class GlassBackdrop {
 public:
  GlassBackdrop();
  ~GlassBackdrop();
  bool Enable(HWND window);
  void Update(HWND window) noexcept;
  void Disable() noexcept;
 private:
  struct Impl;
  std::unique_ptr<Impl> impl_;
};
