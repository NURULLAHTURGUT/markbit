#include "glass_backdrop.h"

#include <d2d1effects.h>
#include <dwmapi.h>
#include <dispatcherqueue.h>
#include <windows.graphics.effects.interop.h>
#include <windows.ui.composition.interop.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Graphics.Effects.h>
#include <winrt/Windows.System.h>
#include <winrt/Windows.UI.Composition.h>
#include <winrt/Windows.UI.Composition.Desktop.h>

namespace {
namespace Effects = winrt::Windows::Graphics::Effects;
namespace Foundation = winrt::Windows::Foundation;
namespace Composition = winrt::Windows::UI::Composition;
namespace AbiEffects = ABI::Windows::Graphics::Effects;

// Describe a single Direct2D Gaussian blur to the Windows compositor.
struct DesktopBlur : winrt::implements<DesktopBlur, Effects::IGraphicsEffect,
    Effects::IGraphicsEffectSource, AbiEffects::IGraphicsEffectD2D1Interop> {
  explicit DesktopBlur(Effects::IGraphicsEffectSource const& input) : input_(input) {}
  winrt::hstring Name() const { return L"DesktopBlur"; }
  void Name(winrt::hstring const&) {}
  HRESULT __stdcall GetEffectId(GUID* value) noexcept override {
    if (!value) return E_POINTER;
    *value = CLSID_D2D1GaussianBlur;
    return S_OK;
  }
  HRESULT __stdcall GetNamedPropertyMapping(LPCWSTR, UINT*,
      AbiEffects::GRAPHICS_EFFECT_PROPERTY_MAPPING*) noexcept override { return E_NOTIMPL; }
  HRESULT __stdcall GetPropertyCount(UINT* value) noexcept override {
    if (!value) return E_POINTER;
    *value = 3;
    return S_OK;
  }
  HRESULT __stdcall GetProperty(UINT index,
      ABI::Windows::Foundation::IPropertyValue** value) noexcept override {
    if (!value) return E_POINTER;
    *value = nullptr;
    try {
      Foundation::IInspectable property{nullptr};
      switch (index) {
        case 0: property = Foundation::PropertyValue::CreateSingle(4.0f); break;
        case 1: property = Foundation::PropertyValue::CreateUInt32(D2D1_GAUSSIANBLUR_OPTIMIZATION_BALANCED); break;
        case 2: property = Foundation::PropertyValue::CreateUInt32(D2D1_BORDER_MODE_HARD); break;
        default: return E_INVALIDARG;
      }
      winrt::copy_to_abi(property.as<Foundation::IPropertyValue>(),
                         *reinterpret_cast<void**>(value));
      return S_OK;
    } catch (...) { return winrt::to_hresult(); }
  }
  HRESULT __stdcall GetSourceCount(UINT* value) noexcept override {
    if (!value) return E_POINTER;
    *value = 1;
    return S_OK;
  }
  HRESULT __stdcall GetSource(UINT index, AbiEffects::IGraphicsEffectSource** value) noexcept override {
    if (!value) return E_POINTER;
    *value = nullptr;
    if (index != 0) return E_INVALIDARG;
    winrt::copy_to_abi(input_, *reinterpret_cast<void**>(value));
    return S_OK;
  }
 private:
  Effects::IGraphicsEffectSource input_;
};
}  // namespace

struct GlassBackdrop::Impl {
  HWND background = nullptr;
  bool initialized = false;
  winrt::Windows::System::DispatcherQueueController queue{nullptr};
  Composition::Compositor compositor{nullptr};
  Composition::Desktop::DesktopWindowTarget target{nullptr};
  Composition::SpriteVisual visual{nullptr};
  ~Impl() {
    try { if (target) target.Close(); } catch (...) {}
    target = nullptr;
    visual = nullptr;
    compositor = nullptr;
    if (background) DestroyWindow(background);
    queue = nullptr;
    if (initialized) winrt::uninit_apartment();
  }
};

GlassBackdrop::GlassBackdrop() : impl_(std::make_unique<Impl>()) {}
GlassBackdrop::~GlassBackdrop() = default;

bool GlassBackdrop::Enable(HWND window) {
  try {
    if (!impl_->target || !impl_->visual) {
      if (!impl_->initialized) {
        winrt::init_apartment(winrt::apartment_type::single_threaded);
        impl_->initialized = true;
      }
      if (!winrt::Windows::System::DispatcherQueue::GetForCurrentThread()) {
        DispatcherQueueOptions options{sizeof(DispatcherQueueOptions), DQTYPE_THREAD_CURRENT, DQTAT_COM_STA};
        winrt::check_hresult(CreateDispatcherQueueController(options,
            reinterpret_cast<ABI::Windows::System::IDispatcherQueueController**>(winrt::put_abi(impl_->queue))));
      }
      impl_->compositor = Composition::Compositor();
      const wchar_t* class_name = L"MarkbitGlassBackdrop";
      WNDCLASSW window_class{};
      window_class.lpfnWndProc = DefWindowProcW;
      window_class.hInstance = GetModuleHandleW(nullptr);
      window_class.lpszClassName = class_name;
      RegisterClassW(&window_class);
      impl_->background = CreateWindowExW(
          WS_EX_NOREDIRECTIONBITMAP | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE,
          class_name, L"Markbit glass background", WS_POPUP,
          0, 0, 1, 1, nullptr, nullptr, window_class.hInstance, nullptr);
      if (!impl_->background) winrt::throw_last_error();
      const BOOL host = TRUE;
      winrt::check_hresult(DwmSetWindowAttribute(impl_->background, DWMWA_USE_HOSTBACKDROPBRUSH, &host, sizeof(host)));
      winrt::check_hresult(impl_->compositor.as<ABI::Windows::UI::Composition::Desktop::ICompositorDesktopInterop>()
          ->CreateDesktopWindowTarget(impl_->background, FALSE,
              reinterpret_cast<ABI::Windows::UI::Composition::Desktop::IDesktopWindowTarget**>(winrt::put_abi(impl_->target))));
      auto source = Composition::CompositionEffectSourceParameter(L"Desktop");
      auto description = winrt::make<DesktopBlur>(source);
      auto brush = impl_->compositor.CreateEffectFactory(description).CreateBrush();
      brush.SetSourceParameter(L"Desktop", impl_->compositor.CreateHostBackdropBrush());
      impl_->visual = impl_->compositor.CreateSpriteVisual();
      impl_->visual.RelativeSizeAdjustment({1.0f, 1.0f});
      impl_->visual.Brush(brush);
    }
    impl_->target.Root(impl_->visual);
    Update(window);
    return true;
  } catch (...) {
    Disable();
    try { if (impl_->target) impl_->target.Close(); } catch (...) {}
    impl_->target = nullptr;
    impl_->visual = nullptr;
    impl_->compositor = nullptr;
    if (impl_->background) { DestroyWindow(impl_->background); impl_->background = nullptr; }
    OutputDebugStringW(L"Markbit: custom desktop blur unavailable; keeping real transparency.\n");
    return false;
  }
}

void GlassBackdrop::Disable() noexcept {
  if (impl_->background) ShowWindow(impl_->background, SW_HIDE);
  try { if (impl_->target) impl_->target.Root(nullptr); } catch (...) {}
}

void GlassBackdrop::Update(HWND window) noexcept {
  if (!impl_->background) return;
  if (!IsWindowVisible(window) || IsIconic(window)) {
    ShowWindow(impl_->background, SW_HIDE);
    return;
  }
  RECT area{};
  GetClientRect(window, &area);
  POINT origin{0, 0};
  ClientToScreen(window, &origin);
  SetWindowPos(impl_->background, window, origin.x, origin.y,
               area.right, area.bottom, SWP_NOACTIVATE | SWP_SHOWWINDOW);
}
