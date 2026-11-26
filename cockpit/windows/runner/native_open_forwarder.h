#ifndef RUNNER_NATIVE_OPEN_FORWARDER_H_
#define RUNNER_NATIVE_OPEN_FORWARDER_H_
#include <string>

std::wstring QuoteNativeOpenArgument(const std::wstring& argument);
// Uses the bundled, authenticated CLI; never initializes Flutter or plugins.
bool TryForwardNativeOpen();
#endif
