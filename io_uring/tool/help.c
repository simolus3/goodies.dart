#include <stdint.h>
#include <stdio.h>
#include <sys/socket.h>
#include <stddef.h>
#include <netinet/in.h>
#include <string.h>
#include <errno.h>

int main() {
    uint8_t data[16];
    memset(&data, 0, 16);
    data[0] = 0x2;
    data[1] = 0x0;
    data[2] = 0x40;
    data[3] = 0x1f;

    struct sockaddr_in* addr = &data[0];
    printf("type: %d (%d), port: %d", addr->sin_family, SOCK_STREAM, addr->sin_port);

    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd == -1) {
        printf("could not create socket");
    }

    if (connect(fd, &data[0], 16) < 0) {
      printf("could not connect: ");
      printf(strerror(errno));
    } else {
        printf("connected!");
    }
}