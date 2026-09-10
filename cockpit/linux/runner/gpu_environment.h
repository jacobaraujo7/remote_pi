#ifndef COCKPIT_GPU_ENVIRONMENT_H_
#define COCKPIT_GPU_ENVIRONMENT_H_

#include <string>

// Applies Cockpit's process-local hybrid GPU policy before GTK/EGL starts.
// Returns a content-free description suitable for the startup log.
std::string configure_linux_gpu_environment();

#endif  // COCKPIT_GPU_ENVIRONMENT_H_
