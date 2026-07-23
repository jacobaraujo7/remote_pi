#ifndef FORKPTY_H_
#define FORKPTY_H_

#include <termios.h>
#include <unistd.h>

pid_t pty_forkpty(int *master, int *slave, const struct termios *termp,
                  const struct winsize *winp);

#endif