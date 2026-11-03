#pragma once

#include <windows.h>

#include <functional>

// Posts tasks back to the thread that started this dispatcher (the
// Flutter platform thread). MediaEngine EventNotify callbacks arrive on
// a Media Foundation worker thread; sending to the EventSink there
// trips the engine's 'non-platform thread' check (data loss/crash),
// so tasks are marshalled through a message-only window pumped by the
// platform thread.
class PlatformDispatch {
 public:
  // Call once on the platform thread (plugin registration) to
  // create the dispatch window.
  static void EnsureStarted();

  // Thread-safe: queues task onto the platform thread. The task is
  // dropped if the window is not ready or already destroyed (the
  // plugin then no longer needs to deliver events).
  static void Post(std::function<void()> task);

 private:
  static LRESULT CALLBACK WndProc(HWND hwnd, UINT msg, WPARAM wparam,
                                  LPARAM lparam);
};
