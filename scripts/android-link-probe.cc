#include <cerrno>
#include <string>
#include <system_error>

extern "C" int syncfs(int fd);

extern "C" int android_link_probe(int fd) {
    const std::string message =
        std::error_code(errno, std::system_category()).message();
    return static_cast<int>(message.size()) + syncfs(fd);
}
