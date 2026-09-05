#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <sys/un.h>

#define SOCK_PATH "/dev/q22esu.sock"
#define MAX_CMD 12288

static int talk(const char *cmd) {
  int s = socket(AF_UNIX, SOCK_STREAM, 0);
  if (s < 0) { perror("socket"); return 126; }
  struct sockaddr_un addr;
  memset(&addr, 0, sizeof addr);
  addr.sun_family = AF_UNIX;
  strncpy(addr.sun_path, SOCK_PATH, sizeof(addr.sun_path) - 1);
  if (connect(s, (struct sockaddr *)&addr, sizeof addr) < 0) {
    fprintf(stderr, "Access denied\n");
    close(s);
    return 1;
  }
  if (write(s, cmd, strlen(cmd) + 1) < 0) { close(s); return 1; }
  char buf[1024];
  int r;
  while ((r = read(s, buf, sizeof buf)) > 0)
    fwrite(buf, 1, r, stdout);
  close(s);
  return 0;
}

/* Escape for embedding in single-quoted sh string: ' -> '\'' */
static void escape_sq(const char *in, char *out, size_t outsz) {
  size_t j = 0;
  for (size_t i = 0; in[i] && j + 5 < outsz; i++) {
    if (in[i] == '\'') {
      memcpy(out + j, "'\\''", 4);
      j += 4;
    } else {
      out[j++] = in[i];
    }
  }
  out[j] = '\0';
}

int main(int argc, char **argv) {
  int i = 1;
  int uid = 0;
  if (i < argc && argv[i][0] >= '0' && argv[i][0] <= '9') {
    uid = atoi(argv[i]);
    i++;
  }
  char cmdbuf[MAX_CMD];
  const char *cmd;
  if (i < argc && strcmp(argv[i], "-c") == 0) {
    if (i + 1 >= argc) { fprintf(stderr, "su: -c needs arg\n"); return 1; }
    cmd = argv[i + 1];
  } else {
    cmd = "exec /system/bin/sh";
  }

  if (uid == 0) {
    return talk(cmd);
  }

  char esc[MAX_CMD];
  escape_sq(cmd, esc, sizeof esc);
  snprintf(cmdbuf, sizeof cmdbuf,
           "/system/xbin/busybox setuidgid %d /system/bin/sh -c '%s'",
           uid, esc);
  return talk(cmdbuf);
}
