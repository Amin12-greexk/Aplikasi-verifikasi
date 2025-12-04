#include <windows.h>
#include <winsvc.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <tlhelp32.h>
#include <tchar.h>

#pragma comment(lib, "advapi32.lib")
#pragma comment(lib, "winsvc.lib")

// Service name and display name
#define SERVICE_NAME TEXT("VerifikasiServer")
#define SERVICE_DISPLAY_NAME TEXT("Verifikasi Server")

// Global variables
SERVICE_STATUS g_ServiceStatus = {0};
SERVICE_STATUS_HANDLE g_StatusHandle = NULL;
HANDLE g_ServiceStopEvent = INVALID_HANDLE_VALUE;
HANDLE g_ServerProcess = NULL;

// Function declarations
void WINAPI ServiceMain(DWORD dwArgc, LPTSTR *lpszArgv);
void WINAPI ServiceControlHandler(DWORD dwControl);
DWORD WINAPI ServiceWorkerThread(LPVOID lpParam);
BOOL InstallService(const wchar_t* serviceName, const wchar_t* appPath);
BOOL RemoveService(const wchar_t* serviceName);
BOOL StartServiceByName(const wchar_t* serviceName);
BOOL StopServiceByName(const wchar_t* serviceName);

// Report status to SCM
void ReportServiceStatus(DWORD dwCurrentState, DWORD dwWin32ExitCode, DWORD dwWaitHint) {
  static DWORD dwCheckPoint = 1;

  // Fill in the SERVICE_STATUS structure.
  g_ServiceStatus.dwCurrentState = dwCurrentState;
  g_ServiceStatus.dwWin32ExitCode = dwWin32ExitCode;
  g_ServiceStatus.dwWaitHint = dwWaitHint;

  if (dwCurrentState == SERVICE_START_PENDING)
    g_ServiceStatus.dwCheckPoint = dwCheckPoint++;
  else
    g_ServiceStatus.dwCheckPoint = 0;

  // Report the status of the service to the SCM.
  SetServiceStatus(g_StatusHandle, &g_ServiceStatus);
}

// Service main function
void WINAPI ServiceMain(DWORD dwArgc, LPTSTR *lpszArgv) {
  // Register the handler function for the service
  g_StatusHandle = RegisterServiceCtrlHandler(SERVICE_NAME, ServiceControlHandler);

  if (!g_StatusHandle) {
    _wprintf(L"RegisterServiceCtrlHandler failed w/err 0x%08lx\n", GetLastError());
    return;
  }

  // Tell the service controller we are starting
  ZeroMemory(&g_ServiceStatus, sizeof(g_ServiceStatus));
  g_ServiceStatus.dwServiceType = SERVICE_WIN32_OWN_PROCESS;
  g_ServiceStatus.dwControlsAccepted = SERVICE_ACCEPT_STOP | SERVICE_ACCEPT_SHUTDOWN;
  g_ServiceStatus.dwCurrentState = SERVICE_START_PENDING;

  ReportServiceStatus(SERVICE_START_PENDING, NO_ERROR, 3000);

  // Create a stop event to wait on later.
  g_ServiceStopEvent = CreateEventEx(NULL, NULL, CREATE_EVENT_MANUAL_RESET, EVENT_ALL_ACCESS);

  if (!g_ServiceStopEvent) {
    ReportServiceStatus(SERVICE_STOPPED, GetLastError(), 0);
    return;
  }

  // Start the actual work performed by the service
  HANDLE hThread = CreateThread(NULL, 0, ServiceWorkerThread, NULL, 0, NULL);
  if (!hThread) {
    ReportServiceStatus(SERVICE_STOPPED, GetLastError(), 0);
    return;
  }

  ReportServiceStatus(SERVICE_RUNNING, NO_ERROR, 0);

  // Wait until our worker thread exits signaling that the service should stop
  WaitForSingleObject(hThread, INFINITE);

  CloseHandle(hThread);
  CloseHandle(g_ServiceStopEvent);
  ReportServiceStatus(SERVICE_STOPPED, NO_ERROR, 0);
}

// Service control handler
void WINAPI ServiceControlHandler(DWORD dwControl) {
  switch (dwControl) {
    case SERVICE_CONTROL_STOP:
      ReportServiceStatus(SERVICE_STOP_PENDING, NO_ERROR, 0);
      // Signal the worker thread to stop
      SetEvent(g_ServiceStopEvent);
      return;

    case SERVICE_CONTROL_SHUTDOWN:
      // Perform system shutdown operations
      if (g_ServerProcess && g_ServerProcess != INVALID_HANDLE_VALUE) {
        TerminateProcess(g_ServerProcess, 0);
      }
      ReportServiceStatus(SERVICE_STOPPED, NO_ERROR, 0);
      return;

    case SERVICE_CONTROL_INTERROGATE:
      // Report current status
      break;

    default:
      break;
  }

  ReportServiceStatus(g_ServiceStatus.dwCurrentState, NO_ERROR, 0);
}

// Service worker thread
DWORD WINAPI ServiceWorkerThread(LPVOID lpParam) {
  wchar_t appPath[MAX_PATH];
  wchar_t cmdLine[MAX_PATH * 2];
  STARTUPINFOW si = {0};
  PROCESS_INFORMATION pi = {0};

  // Get the path to the application
  if (!GetModuleFileNameW(NULL, appPath, MAX_PATH)) {
    _wprintf(L"GetModuleFileName failed w/err 0x%08lx\n", GetLastError());
    SetEvent(g_ServiceStopEvent);
    return 1;
  }

  // Replace service wrapper exe with server exe in path
  wchar_t *lastBackslash = wcsrchr(appPath, L'\\');
  if (lastBackslash) {
    wcscpy_s(lastBackslash + 1, MAX_PATH - (lastBackslash - appPath + 1), L"verifikasi_server.exe");
  }

  // Build command line with --service-mode flag
  swprintf_s(cmdLine, MAX_PATH * 2, L"\"%s\" --service-mode", appPath);

  // Prepare startup info
  si.cb = sizeof(si);
  si.dwFlags = STARTF_USESHOWWINDOW;
  si.wShowWindow = SW_HIDE;

  _wprintf(L"Starting server: %s\n", cmdLine);

  // Loop to restart server if it crashes
  while (WaitForSingleObject(g_ServiceStopEvent, 0) == WAIT_TIMEOUT) {
    if (!CreateProcessW(
        NULL,           // No module name (use command line)
        cmdLine,        // Command line
        NULL,           // Process handle not inheritable
        NULL,           // Thread handle not inheritable
        FALSE,          // Set handle inheritance to FALSE
        0,              // No creation flags
        NULL,           // Use parent's environment block
        NULL,           // Use parent's starting directory
        &si,            // Pointer to STARTUPINFO structure
        &pi             // Pointer to PROCESS_INFORMATION structure
        )) {
      _wprintf(L"CreateProcess failed w/err 0x%08lx\n", GetLastError());
      Sleep(5000);  // Wait 5 seconds before retrying
      continue;
    }

    g_ServerProcess = pi.hProcess;
    _wprintf(L"Server process started (PID: %lu)\n", pi.dwProcessId);

    // Close the thread handle as we don't need it
    CloseHandle(pi.hThread);

    // Wait for the server process to exit or for the stop event
    HANDLE handles[2] = {g_ServerProcess, g_ServiceStopEvent};
    DWORD result = WaitForMultipleObjects(2, handles, FALSE, INFINITE);

    if (result == WAIT_OBJECT_0) {
      // Server process exited, restart it unless we're stopping the service
      DWORD exitCode;
      GetExitCodeProcess(g_ServerProcess, &exitCode);
      _wprintf(L"Server process exited with code %lu, restarting...\n", exitCode);
      CloseHandle(g_ServerProcess);
      g_ServerProcess = NULL;

      if (WaitForSingleObject(g_ServiceStopEvent, 3000) != WAIT_TIMEOUT) {
        // Stop event was set, exit the loop
        break;
      }
    } else if (result == WAIT_OBJECT_0 + 1) {
      // Stop event was signaled, terminate the server process
      _wprintf(L"Service stop requested, terminating server...\n");
      if (g_ServerProcess && g_ServerProcess != INVALID_HANDLE_VALUE) {
        TerminateProcess(g_ServerProcess, 0);
        WaitForSingleObject(g_ServerProcess, INFINITE);
        CloseHandle(g_ServerProcess);
        g_ServerProcess = NULL;
      }
      break;
    }
  }

  SetEvent(g_ServiceStopEvent);
  return 0;
}

// Install service
BOOL InstallService(const wchar_t* serviceName, const wchar_t* appPath) {
  SC_HANDLE schSCManager;
  SC_HANDLE schService;
  wchar_t szPath[MAX_PATH * 2];

  // Get a handle to the SCM database
  schSCManager = OpenSCManagerW(
      NULL,                    // Local computer
      NULL,                    // Services database
      SC_MANAGER_ALL_ACCESS);  // Full access rights

  if (NULL == schSCManager) {
    _wprintf(L"OpenSCManager failed w/err 0x%08lx\n", GetLastError());
    return FALSE;
  }

  // Build the path with the service wrapper exe
  if (!GetModuleFileNameW(NULL, szPath, MAX_PATH)) {
    _wprintf(L"GetModuleFileName failed w/err 0x%08lx\n", GetLastError());
    CloseServiceHandle(schSCManager);
    return FALSE;
  }

  // Create the service
  schService = CreateServiceW(
      schSCManager,                      // SCM database
      serviceName,                       // Name of service
      SERVICE_DISPLAY_NAME,              // Display name
      SERVICE_ALL_ACCESS,                // Desired access
      SERVICE_WIN32_OWN_PROCESS,         // Service type
      SERVICE_AUTO_START,                // Start type (auto start)
      SERVICE_ERROR_NORMAL,              // Error control type
      szPath,                            // Path to service executable
      NULL,                              // No load ordering group
      NULL,                              // No tag identifier
      NULL,                              // No dependencies
      NULL,                              // LocalSystem account
      NULL);                             // No password

  if (schService == NULL) {
    _wprintf(L"CreateService failed w/err 0x%08lx\n", GetLastError());
    CloseServiceHandle(schSCManager);
    return FALSE;
  }

  _wprintf(L"Service installed successfully\n");

  // Cleanup
  CloseServiceHandle(schService);
  CloseServiceHandle(schSCManager);
  return TRUE;
}

// Remove service
BOOL RemoveService(const wchar_t* serviceName) {
  SC_HANDLE schSCManager;
  SC_HANDLE schService;
  SERVICE_STATUS ssStatus;

  // Get a handle to the SCM database
  schSCManager = OpenSCManagerW(
      NULL,                    // Local computer
      NULL,                    // Services database
      SC_MANAGER_ALL_ACCESS);  // Full access rights

  if (NULL == schSCManager) {
    _wprintf(L"OpenSCManager failed w/err 0x%08lx\n", GetLastError());
    return FALSE;
  }

  // Get a handle to the service
  schService = OpenServiceW(
      schSCManager,       // SCM database
      serviceName,        // Name of service
      DELETE);            // Need delete access

  if (schService == NULL) {
    _wprintf(L"OpenService failed w/err 0x%08lx\n", GetLastError());
    CloseServiceHandle(schSCManager);
    return FALSE;
  }

  // Delete the service
  if (!DeleteService(schService)) {
    _wprintf(L"DeleteService failed w/err 0x%08lx\n", GetLastError());
    CloseServiceHandle(schService);
    CloseServiceHandle(schSCManager);
    return FALSE;
  }

  _wprintf(L"Service removed successfully\n");

  CloseServiceHandle(schService);
  CloseServiceHandle(schSCManager);
  return TRUE;
}

// Start service
BOOL StartServiceByName(const wchar_t* serviceName) {
  SC_HANDLE schSCManager;
  SC_HANDLE schService;

  schSCManager = OpenSCManagerW(NULL, NULL, SC_MANAGER_ALL_ACCESS);

  if (NULL == schSCManager) {
    _wprintf(L"OpenSCManager failed w/err 0x%08lx\n", GetLastError());
    return FALSE;
  }

  schService = OpenServiceW(schSCManager, serviceName, SERVICE_START);

  if (schService == NULL) {
    _wprintf(L"OpenService failed w/err 0x%08lx\n", GetLastError());
    CloseServiceHandle(schSCManager);
    return FALSE;
  }

  if (!StartServiceW(schService, 0, NULL)) {
    _wprintf(L"StartService failed w/err 0x%08lx\n", GetLastError());
    CloseServiceHandle(schService);
    CloseServiceHandle(schSCManager);
    return FALSE;
  }

  _wprintf(L"Service started successfully\n");

  CloseServiceHandle(schService);
  CloseServiceHandle(schSCManager);
  return TRUE;
}

// Stop service
BOOL StopServiceByName(const wchar_t* serviceName) {
  SC_HANDLE schSCManager;
  SC_HANDLE schService;
  SERVICE_STATUS ssStatus;

  schSCManager = OpenSCManagerW(NULL, NULL, SC_MANAGER_ALL_ACCESS);

  if (NULL == schSCManager) {
    _wprintf(L"OpenSCManager failed w/err 0x%08lx\n", GetLastError());
    return FALSE;
  }

  schService = OpenServiceW(schSCManager, serviceName, SERVICE_STOP | SERVICE_QUERY_STATUS);

  if (schService == NULL) {
    _wprintf(L"OpenService failed w/err 0x%08lx\n", GetLastError());
    CloseServiceHandle(schSCManager);
    return FALSE;
  }

  if (!ControlService(schService, SERVICE_CONTROL_STOP, &ssStatus)) {
    _wprintf(L"ControlService failed w/err 0x%08lx\n", GetLastError());
    CloseServiceHandle(schService);
    CloseServiceHandle(schSCManager);
    return FALSE;
  }

  _wprintf(L"Service stopped successfully\n");

  CloseServiceHandle(schService);
  CloseServiceHandle(schSCManager);
  return TRUE;
}

// Main entry point
int wmain(int argc, wchar_t *argv[]) {
  _wprintf(L"Verifikasi Server - Windows Service Manager\n");
  _wprintf(L"========================================\n\n");

  if (argc < 2) {
    _wprintf(L"Usage:\n");
    _wprintf(L"  %s install <path_to_app>\n", argv[0]);
    _wprintf(L"  %s remove\n", argv[0]);
    _wprintf(L"  %s start\n", argv[0]);
    _wprintf(L"  %s stop\n", argv[0]);
    return 1;
  }

  wchar_t *command = argv[1];

  if (wcscmp(command, L"install") == 0) {
    if (argc < 3) {
      _wprintf(L"Error: install requires application path\n");
      return 1;
    }
    return InstallService(SERVICE_NAME, argv[2]) ? 0 : 1;
  } else if (wcscmp(command, L"remove") == 0) {
    return RemoveService(SERVICE_NAME) ? 0 : 1;
  } else if (wcscmp(command, L"start") == 0) {
    return StartServiceByName(SERVICE_NAME) ? 0 : 1;
  } else if (wcscmp(command, L"stop") == 0) {
    return StopServiceByName(SERVICE_NAME) ? 0 : 1;
  } else if (wcscmp(command, L"run") == 0) {
    // Run as service (called by Windows SCM)
    SERVICE_TABLE_ENTRY DispatchTable[] = {{SERVICE_NAME, ServiceMain}, {NULL, NULL}};

    if (!StartServiceCtrlDispatcher(DispatchTable)) {
      _wprintf(L"StartServiceCtrlDispatcher failed w/err 0x%08lx\n", GetLastError());
      return 1;
    }
    return 0;
  } else {
    _wprintf(L"Unknown command: %s\n", command);
    return 1;
  }
}
