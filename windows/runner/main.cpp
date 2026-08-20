#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

// Global named mutex: single-instance enforcement + installer detection.
// Must match the AppMutex value in setup.iss.
static const wchar_t* kAppMutexName = L"JerrySuite_App_Mutex_8E7B3C2A";

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Create a global named mutex for single-instance behavior and to let the
  // Inno Setup installer detect a running instance via AppMutex.
  // Skip in debug mode (IsDebuggerPresent) so flutter run hot-restart works.
  HANDLE hMutex = nullptr;
  bool singleInstance = !::IsDebuggerPresent();
  if (singleInstance) {
    hMutex = ::CreateMutexW(nullptr, TRUE, kAppMutexName);
    if (hMutex == nullptr || ::GetLastError() == ERROR_ALREADY_EXISTS) {
      // Another instance is running; activate its window and exit.
      if (hMutex) ::CloseHandle(hMutex);
      HWND existing = ::FindWindowW(nullptr, L"Jerry Suite");
      if (existing) {
        ::ShowWindow(existing, SW_RESTORE);
        ::SetForegroundWindow(existing);
      }
      return EXIT_SUCCESS;
    }
  }

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(100, 100);
  Win32Window::Size size(800, 600);
  if (!window.Create(L"Jerry Suite", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(false);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
