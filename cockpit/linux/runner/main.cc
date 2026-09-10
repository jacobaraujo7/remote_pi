#include "my_application.h"
#include "gpu_environment.h"

int main(int argc, char** argv) {
  const std::string gpu_policy = configure_linux_gpu_environment();
  g_message("Cockpit Linux startup: gpu_policy=%s gdk_backend=%s session=%s",
            gpu_policy.c_str(),
            g_getenv("GDK_BACKEND") != nullptr ? g_getenv("GDK_BACKEND")
                                                : "auto",
            g_getenv("XDG_SESSION_TYPE") != nullptr
                ? g_getenv("XDG_SESSION_TYPE")
                : "unknown");
  g_autoptr(MyApplication) app = my_application_new();
  return g_application_run(G_APPLICATION(app), argc, argv);
}
