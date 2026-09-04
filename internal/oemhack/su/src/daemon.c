#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/wait.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <signal.h>

#define SOCK_PATH "/dev/cytasu.sock"
#define MAX_CMD 8192

static void handle(int fd) {
  char cmd[MAX_CMD];
  int n = 0;
  while (n < MAX_CMD - 1) {
    int r = read(fd, cmd + n, 1);
    if (r <= 0) return;
    if (cmd[n] == '\0') break;
    n++;
  }
  cmd[n] = '\0';
  if (n == 0) return;

  int pfd[2];
  if (pipe(pfd) < 0) return;
  pid_t pid = fork();
  if (pid < 0) return;
  if (pid == 0) {
    dup2(pfd[1], 1);
    dup2(pfd[1], 2);
    close(pfd[0]); close(pfd[1]); close(fd);
    execl("/system/bin/sh", "sh", "-c", cmd, (char *)NULL);
    _exit(127);
  }
  close(pfd[1]);
  char buf[1024];
  int r;
  while ((r = read(pfd[0], buf, sizeof buf)) > 0) {
    int off = 0;
    while (off < r) {
      int w = write(fd, buf + off, r - off);
      if (w <= 0) break;
      off += w;
    }
  }
  close(pfd[0]);
  int st; waitpid(pid, &st, 0);
  /* trailing status byte after NUL marker would be nicer; client uses exit of connection */
}

int main(void) {
  signal(SIGCHLD, SIG_IGN);
  unlink(SOCK_PATH);
  int s = socket(AF_UNIX, SOCK_STREAM, 0);
  if (s < 0) return 1;
  struct sockaddr_un addr;
  memset(&addr, 0, sizeof addr);
  addr.sun_family = AF_UNIX;
  strncpy(addr.sun_path, SOCK_PATH, sizeof(addr.sun_path) - 1);
  if (bind(s, (struct sockaddr *)&addr, sizeof addr) < 0) return 2;
  chmod(SOCK_PATH, 0666);
  if (listen(s, 8) < 0) return 3;
  for (;;) {
    int c = accept(s, NULL, NULL);
    if (c < 0) continue;
    pid_t pid = fork();
    if (pid == 0) {
      close(s);
      handle(c);
      close(c);
      _exit(0);
    }
    close(c);
  }
}
