#include "maidpty.h"

#include "include/dart_api_dl.c"

#if _WIN32
#include "maidpty_win.c"
#else
#include "forkpty.c"
#include "maidpty_unix.c"
#endif