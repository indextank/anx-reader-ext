#include "platform_dispatch.h"

#include <atomic>
#include <mutex>

namespace {

constexpr UINT kMsgPostedTask = WM_APP + 1;

const wchar_t kClassName[] = L"audioplayers_platform_dispatch";

std::mutex g_mutex;
HWND g_hwnd = nullptr;
std::atomic<bool> g_failed{false};

}  // namespace

// static
void PlatformDispatch::EnsureStarted() {
  std::lock_guard<std::mutex> lock(g_mutex);
  if (g_hwnd != nullptr || g_failed.load()) return;

  WNDCLASS wc = {};
  wc.lpfnWndProc = PlatformDispatch::WndProc;
  wc.hInstance = GetModuleHandle(nullptr);
  wc.lpszClassName = kClassName;
  RegisterClass(&wc);

  // Message-only window: invisible, not in z-order, only carries
  // dispatched messages.
  g_hwnd = CreateWindowEx(0, kClassName, L"", 0, 0, 0, 0, 0, HWND_MESSAGE,
                          nullptr, wc.hInstance, nullptr);
  if (g_hwnd == nullptr) {
    g_failed.store(true);
  }
}

// static
void PlatformDispatch::Post(std::function<void()> task) {
  std::lock_guard<std::mutex> lock(g_mutex);
  if (g_hwnd == nullptr) return;
  auto* owned = new std::function<void()>(std::move(task));
  if (!PostMessage(g_hwnd, kMsgPostedTask, 0,
                   reinterpret_cast<LPARAM>(owned))) {
    delete owned;
  }
}

// static
LRESULT CALLBACK PlatformDispatch::WndProc(HWND hwnd, UINT msg, WPARAM wparam,
                                           LPARAM lparam) {
  if (msg == kMsgPostedTask) {
    auto* owned = reinterpret_cast<std::function<void()>*>(lparam);
    // Scope so the task is destroyed before returning to avoid
    // re-entrancy issues if the task itself posts again.
    {
      std::unique_ptr<std::function<void()>> holder(owned);
      (*holder)();
    }
    return 0;
  }
  if (msg == WM_DESTROY) {
    std::lock_guard<std::mutex> lock(g_mutex);
    if (g_hwnd == hwnd) g_hwnd = nullptr;
    return 0;
  }
  return DefWindowProc(hwnd, msg, wparam, lparam);
}
