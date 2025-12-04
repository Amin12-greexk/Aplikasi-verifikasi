#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>
#include <string>
#include <powrprof.h>

#pragma comment(lib, "powrprof.lib")

#include "flutter_window.h"
#include "utils.h"

// Helper function to check if service mode is enabled
bool IsServiceMode(const std::vector<std::string>& args) {
  for (const auto& arg : args) {
    if (arg == "--service-mode") {
      return true;
    }
  }
  return false;
}

// Prevent system sleep
void PreventSystemSleep() {
  EXECUTION_STATE previousState = SetThreadExecutionState(
      ES_CONTINUOUS | ES_SYSTEM_REQUIRED | ES_AWAYMODE_REQUIRED);
  if (previousState == 0) {
    OutputDebugStringW(L"Failed to prevent system sleep\n");
  } else {
    OutputDebugStringW(L"System sleep prevention enabled\n");
  }
}

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

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  // Check if running in service mode (headless)
  bool service_mode = IsServiceMode(command_line_arguments);

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  if (service_mode) {
    // Headless service mode: Run without creating a window
    // The Dart/Flutter app will handle the server startup and keep the process alive
    ::MSG msg;
    while (::GetMessage(&msg, nullptr, 0, 0)) {
      ::TranslateMessage(&msg);
      ::DispatchMessage(&msg);
    }
  } else {
    // Desktop mode: Create window as usual
    // Prevent system sleep during operation
    PreventSystemSleep();

    FlutterWindow window(project);
    Win32Window::Point origin(10, 10);
    Win32Window::Size size(1280, 720);
    if (!window.Create(L"verifikasi_server", origin, size)) {
      ::CoUninitialize();
      return EXIT_FAILURE;
    }
    window.SetQuitOnClose(true);

    ::MSG msg;
    while (::GetMessage(&msg, nullptr, 0, 0)) {
      ::TranslateMessage(&msg);
      ::DispatchMessage(&msg);
    }

    // Allow system sleep again when app closes
    SetThreadExecutionState(ES_CONTINUOUS);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
