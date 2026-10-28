#define _GNU_SOURCE
#include <sys/syscall.h>
#include <unistd.h>

#if defined(__ANDROID_API__) && __ANDROID_API__ < 28
int syncfs(int fd) {
    return syscall(SYS_syncfs, fd);
}
#endif
