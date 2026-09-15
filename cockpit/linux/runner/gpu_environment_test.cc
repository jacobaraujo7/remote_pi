#include "gpu_environment.h"

#include <cassert>
#include <cstdlib>
#include <string>

int main() {
  setenv("__GLX_VENDOR_LIBRARY_NAME", "nvidia", 1);
  setenv("__NV_PRIME_RENDER_OFFLOAD", "1", 1);
  setenv("LIBVA_DRIVER_NAME", "nvidia", 1);
  unsetenv("COCKPIT_USE_NVIDIA");
  unsetenv("GDK_BACKEND");
  assert(configure_linux_gpu_environment() == "integrated-x11-default");
  assert(std::getenv("__GLX_VENDOR_LIBRARY_NAME") == nullptr);
  assert(std::getenv("__NV_PRIME_RENDER_OFFLOAD") == nullptr);
  assert(std::getenv("LIBVA_DRIVER_NAME") == nullptr);
  assert(std::string(std::getenv("DRI_PRIME")) == "0");
  assert(std::string(std::getenv("GDK_BACKEND")) == "x11");

  setenv("GDK_BACKEND", "wayland", 1);
  assert(configure_linux_gpu_environment() == "integrated-x11-default");
  assert(std::string(std::getenv("GDK_BACKEND")) == "wayland");

  setenv("COCKPIT_USE_NVIDIA", "1", 1);
  unsetenv("GDK_BACKEND");
  unsetenv("__GLX_VENDOR_LIBRARY_NAME");
  unsetenv("__NV_PRIME_RENDER_OFFLOAD");
  assert(configure_linux_gpu_environment() == "nvidia-opt-in");
  assert(std::string(std::getenv("__GLX_VENDOR_LIBRARY_NAME")) == "nvidia");
  assert(std::string(std::getenv("__NV_PRIME_RENDER_OFFLOAD")) == "1");
  assert(std::getenv("GDK_BACKEND") == nullptr);
  return 0;
}
