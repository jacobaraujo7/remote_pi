#include "cockpit_pty.h"

#include "include/dart_api_dl.c"

#if _WIN32
#include "cockpit_pty_win.c"
#else
#include "forkpty.c"
#include "cockpit_pty_unix.c"
#endif