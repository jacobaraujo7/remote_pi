#include "gpu_environment.h"

#include <cassert>
#include <cstdlib>
#include <string>

int main() {
  setenv("__GLX_VENDOR_LIBRARY_NAME", "nvidia", 1);
  setenv("__NV_PRIME_RENDER_OFFLOAD", "1", 1);
  setenv("LIBVA_DRIVER_NAME", "nvidia", 1);
  unsetenv("COCKPIT_USE_NVIDIA");
  assert(configure_linux_gpu_environment() == "integrated-default");
  assert(std::getenv("__GLX_VENDOR_LIBRARY_NAME") == nullptr);
  assert(std::getenv("__NV_PRIME_RENDER_OFFLOAD") == nullptr);
  assert(std::getenv("LIBVA_DRIVER_NAME") == nullptr);
  assert(std::string(std::getenv("DRI_PRIME")) == "0");

  setenv("COCKPIT_USE_NVIDIA", "1", 1);
  unsetenv("__GLX_VENDOR_LIBRARY_NAME");
  unsetenv("__NV_PRIME_RENDER_OFFLOAD");
  assert(configure_linux_gpu_environment() == "nvidia-opt-in");
  assert(std::string(std::getenv("__GLX_VENDOR_LIBRARY_NAME")) == "nvidia");
  assert(std::string(std::getenv("__NV_PRIME_RENDER_OFFLOAD")) == "1");
  return 0;
}
