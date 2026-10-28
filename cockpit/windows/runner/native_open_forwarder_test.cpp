#include "native_open_forwarder.h"
#include <windows.h>
#include <shellapi.h>
#include <iostream>
#include <vector>

int main() {
  const std::vector<std::wstring> cases = {
    L"", L"plain.orc", L"folder with spaces\\team.orc", L"trailing\\",
    L"quote\"inside", L"slash\\\"quote", L"C:\\projetos\\equipe 日本.orc"
  };
  for (const auto& value : cases) {
    const std::wstring command = L"test.exe " + QuoteNativeOpenArgument(value);
    int count = 0;
    wchar_t** parsed = ::CommandLineToArgvW(command.c_str(), &count);
    const bool matches = parsed && count == 2 && value == parsed[1];
    if (parsed) ::LocalFree(parsed);
    if (!matches) {
      std::cerr << "Native file argument round-trip failed" << std::endl;
      return 1;
    }
  }
  std::cout << "Native file argument round-trips passed" << std::endl;
  return 0;
}
