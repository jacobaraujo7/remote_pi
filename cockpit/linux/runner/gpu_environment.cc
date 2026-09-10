#include "gpu_environment.h"

#include <cstdlib>

namespace {

bool is_enabled(const char* value) {
  return value != nullptr && std::string(value) == "1";
}

void set_default(const char* name, const char* value) {
  if (std::getenv(name) == nullptr) setenv(name, value, 0);
}

}  // namespace

std::string configure_linux_gpu_environment() {
  if (is_enabled(std::getenv("COCKPIT_USE_NVIDIA"))) {
    set_default("__NV_PRIME_RENDER_OFFLOAD", "1");
    set_default("__GLX_VENDOR_LIBRARY_NAME", "nvidia");
    set_default("__VK_LAYER_NV_optimus", "NVIDIA_only");
    return "nvidia-opt-in";
  }

  // Omarchy/Hyprland sessions can export these globally for the compositor.
  // Letting them leak into Flutter silently selected NVIDIA EGL despite the
  // Cockpit launcher claiming to prefer Intel, and recent cores ended inside
  // libnvidia-eglcore. This changes only Cockpit and its descendants.
  unsetenv("__NV_PRIME_RENDER_OFFLOAD");
  unsetenv("__GLX_VENDOR_LIBRARY_NAME");
  unsetenv("__VK_LAYER_NV_optimus");
  unsetenv("__EGL_VENDOR_LIBRARY_FILENAMES");
  unsetenv("VK_ICD_FILENAMES");
  unsetenv("GBM_BACKEND");
  unsetenv("LIBVA_DRIVER_NAME");
  setenv("DRI_PRIME", "0", 1);
  return "integrated-default";
}
