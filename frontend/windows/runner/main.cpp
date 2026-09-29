#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <fstream>
#include <string>

#include "../../third_party/desktop_multi_window/windows/include/desktop_multi_window/desktop_multi_window_plugin.h"
#include "flutter_window.h"
#include "utils.h"

namespace {

void TraceShutdown(const wchar_t* event) {
  wchar_t temp_path[MAX_PATH];
  const DWORD length = ::GetTempPathW(MAX_PATH, temp_path);
  if (length == 0 || length >= MAX_PATH) {
    return;
  }
  std::wstring path(temp_path);
  path += L"UniversityPath_shutdown_trace.log";
  std::wofstream file(path, std::ios::app);
  if (file.is_open()) {
    file << ::GetTickCount64() << L" native: " << event << L"\n";
  }
}

// desktop_multi_window keeps auxiliary Flutter engines in this process. When
// the main message loop ends, close their native top-level windows immediately
// rather than leaving them visible during engine teardown.
BOOL CALLBACK CloseAuxiliaryWindows(HWND hwnd, LPARAM main_window) {
  if (hwnd != reinterpret_cast<HWND>(main_window)) {
    ::DestroyWindow(hwnd);
  }
  return TRUE;
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  int exit_code = EXIT_SUCCESS;
  {
    flutter::DartProject project(L"data");

    std::vector<std::string> command_line_arguments =
        GetCommandLineArguments();

    project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

    FlutterWindow window(project);
    Win32Window::Point origin(10, 10);
    Win32Window::Size size(1440, 900);
    if (!window.Create(L"university_path_frontend", origin, size)) {
      exit_code = EXIT_FAILURE;
    } else {
      window.SetQuitOnClose(true);
      TraceShutdown(L"main message loop started");

      ::MSG msg;
      while (::GetMessage(&msg, nullptr, 0, 0)) {
        ::TranslateMessage(&msg);
        ::DispatchMessage(&msg);
        // A child may have queued its engine for release while handling this
        // message. Release only after dispatch has returned to the main loop.
        DesktopMultiWindowCleanupClosedWindows();
      }

      TraceShutdown(L"main message loop ended");
      ::EnumThreadWindows(
          ::GetCurrentThreadId(), CloseAuxiliaryWindows,
          reinterpret_cast<LPARAM>(window.GetHandle()));
      DesktopMultiWindowCleanupClosedWindows();
      TraceShutdown(L"queued auxiliary Flutter engines released");
      TraceShutdown(L"auxiliary native windows destroyed");
    }
  }
  TraceShutdown(L"main Flutter engine destroyed");

  ::CoUninitialize();
  return exit_code;
}
