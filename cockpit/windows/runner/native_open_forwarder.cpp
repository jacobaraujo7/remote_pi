#include "native_open_forwarder.h"
#include <windows.h>
#include <shellapi.h>
#include <filesystem>
#include <vector>

std::wstring QuoteNativeOpenArgument(const std::wstring& argument) {
  std::wstring quoted = L"\"";
  size_t slashes = 0;
  for (wchar_t character : argument) {
    if (character == L'\\') {
      ++slashes;
      continue;
    }
    quoted.append(character == L'"' ? 2 * slashes + 1 : slashes, L'\\');
    slashes = 0;
    quoted += character;
  }
  quoted.append(2 * slashes, L'\\');
  quoted += L'"';
  return quoted;
}

bool TryForwardNativeOpen() {
  int count = 0;
  wchar_t** arguments = ::CommandLineToArgvW(::GetCommandLineW(), &count);
  if (!arguments) return false;
  if (count < 2 || std::wstring(arguments[1]) == L"multi_window") {
    ::LocalFree(arguments);
    return false;
  }
  std::wstring executable(32768, L'\0');
  const DWORD length = ::GetModuleFileNameW(nullptr, executable.data(),
                                           static_cast<DWORD>(executable.size()));
  if (length == 0 || length >= executable.size()) {
    ::LocalFree(arguments);
    return false;
  }
  executable.resize(length);
  const auto cli = std::filesystem::path(executable).parent_path() / L"cockpit-cli.exe";
  std::error_code error;
  if (!std::filesystem::is_regular_file(cli, error)) {
    ::LocalFree(arguments);
    return false;
  }
  std::wstring command = QuoteNativeOpenArgument(cli.wstring());
#ifdef _DEBUG
  command += L" --forward-native-open debug";
#else
  command += L" --forward-native-open release";
#endif
  for (int index = 1; index < count; ++index) {
    command += L" " + QuoteNativeOpenArgument(arguments[index]);
  }
  ::LocalFree(arguments);
  STARTUPINFOW startup{};
  startup.cb = sizeof(startup);
  startup.dwFlags = STARTF_USESHOWWINDOW;
  startup.wShowWindow = SW_HIDE;
  PROCESS_INFORMATION process{};
  if (!::CreateProcessW(cli.c_str(), command.data(), nullptr, nullptr, FALSE,
                        CREATE_NO_WINDOW, nullptr, nullptr, &startup, &process)) {
    return false;
  }
  // The CLI bounds connect/write/read time; it does not initialize any GUI.
  ::WaitForSingleObject(process.hProcess, INFINITE);
  DWORD exit_code = 1;
  const bool finished = ::GetExitCodeProcess(process.hProcess, &exit_code) != FALSE;
  ::CloseHandle(process.hThread);
  ::CloseHandle(process.hProcess);
  return finished && exit_code == 0;
}
