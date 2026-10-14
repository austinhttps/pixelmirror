#include "win32_window.h"

#include <flutter_windows.h>
#include "resource.h"

namespace {

constexpr const wchar_t kWindowClassName[] = L"FLUTTER_RUNNER_WIN32_WINDOW";

class WindowClassRegistrar {
 public:
  ~WindowClassRegistrar() {
    UnregisterClassW(kWindowClassName, nullptr);
  }

  static WindowClassRegistrar* GetInstance() {
    static WindowClassRegistrar instance;
    return &instance;
  }

  void Register(WNDPROC wnd_proc) {
    if (registered_) return;
    WNDCLASSW window_class{};
    window_class.hCursor = LoadCursor(nullptr, IDC_ARROW);
    window_class.lpszClassName = kWindowClassName;
    window_class.style = CS_HREDRAW | CS_VREDRAW;
    window_class.cbClsExtra = 0;
    window_class.cbWndExtra = 0;
    window_class.hInstance = GetModuleHandle(nullptr);
    window_class.hIcon = LoadIcon(window_class.hInstance, MAKEINTRESOURCE(IDI_APP_ICON));
    window_class.lpfnWndProc = wnd_proc;
    RegisterClassW(&window_class);
    registered_ = true;
  }

 private:
  WindowClassRegistrar() = default;
  bool registered_ = false;
};

}  // namespace

Win32Window::Win32Window() {}
Win32Window::~Win32Window() {
  Destroy();
}

bool Win32Window::Create(const std::wstring& title,
                         const Point& origin,
                         const Size& size) {
  Destroy();

  WindowClassRegistrar::GetInstance()->Register(WndProc);

  const POINT target_point = {static_cast<LONG>(origin.x),
                              static_cast<LONG>(origin.y)};
  HMONITOR monitor = MonitorFromPoint(target_point, MONITOR_DEFAULTTONEAREST);
  UINT dpi = FlutterDesktopGetDpiForMonitor(monitor);
  double scale_factor = dpi / 96.0;

  HWND window = CreateWindowExW(
      WS_EX_APPWINDOW, kWindowClassName, title.c_str(),
      WS_OVERLAPPEDWINDOW,
      origin.x, origin.y,
      static_cast<int>(size.width * scale_factor),
      static_cast<int>(size.height * scale_factor),
      nullptr, nullptr, GetModuleHandle(nullptr), this);

  if (!window) return false;

  return OnCreate();
}

bool Win32Window::Show() {
  return ShowWindow(window_handle_, SW_SHOWNORMAL);
}

void Win32Window::Destroy() {
  if (window_handle_) {
    DestroyWindow(window_handle_);
    window_handle_ = nullptr;
  }
}

HWND Win32Window::GetHandle() const {
  return window_handle_;
}

void Win32Window::SetQuitOnClose(bool quit_on_close) {
  quit_on_close_ = quit_on_close;
}

RECT Win32Window::GetClientArea() const {
  RECT frame;
  GetClientRect(window_handle_, &frame);
  return frame;
}

bool Win32Window::OnCreate() {
  return true;
}

void Win32Window::OnDestroy() {}

LRESULT CALLBACK Win32Window::WndProc(HWND const window,
                                      UINT const message,
                                      WPARAM const wparam,
                                      LPARAM const lparam) noexcept {
  if (message == WM_NCCREATE) {
    auto window_struct = reinterpret_cast<CREATESTRUCT*>(lparam);
    SetWindowLongPtr(window, GWLP_USERDATA,
                     reinterpret_cast<LONG_PTR>(window_struct->lpCreateParams));
    auto that = static_cast<Win32Window*>(window_struct->lpCreateParams);
    that->window_handle_ = window;
  } else if (Win32Window* that = reinterpret_cast<Win32Window*>(
                 GetWindowLongPtr(window, GWLP_USERDATA))) {
    return that->MessageHandler(window, message, wparam, lparam);
  }
  return DefWindowProc(window, message, wparam, lparam);
}

LRESULT Win32Window::MessageHandler(HWND window,
                                    UINT const message,
                                    WPARAM const wparam,
                                    LPARAM const lparam) noexcept {
  switch (message) {
    case WM_DESTROY:
      window_handle_ = nullptr;
      OnDestroy();
      if (quit_on_close_) {
        PostQuitMessage(0);
      }
      return 0;
  }
  return DefWindowProc(window, message, wparam, lparam);
}
