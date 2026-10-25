/* Static healthcheck for the snapclient container.
 *
 * The image ships no shell or network tools, so this small binary performs
 * the Docker HEALTHCHECK probe: it exits 0 when the snapserver
 * (SNAPSERVER:SNAPSERVER_PORT) accepts a TCP connection, 1 otherwise.
 * Note this verifies server reachability, not that audio is actually
 * streaming (snapclient exposes no external state).
 */

#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <netdb.h>
#include <poll.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

#define CONNECT_TIMEOUT_MS 3000

static int try_connect(const struct sockaddr *sa, socklen_t len)
{
    int fd = socket(sa->sa_family, SOCK_STREAM, 0);
    if (fd < 0)
        return -1;

    if (fcntl(fd, F_SETFL, O_NONBLOCK) < 0) {
        close(fd);
        return -1;
    }

    if (connect(fd, sa, len) == 0) {
        close(fd);
        return 0;
    }
    if (errno != EINPROGRESS) {
        close(fd);
        return -1;
    }

    struct pollfd pfd;
    pfd.fd = fd;
    pfd.events = POLLOUT;
    if (poll(&pfd, 1, CONNECT_TIMEOUT_MS) == 1 && (pfd.revents & POLLOUT) != 0) {
        int so_error = 0;
        socklen_t so_len = sizeof(so_error);
        if (getsockopt(fd, SOL_SOCKET, SO_ERROR, &so_error, &so_len) == 0 && so_error == 0) {
            close(fd);
            return 0;
        }
    }
    close(fd);
    return -1;
}

int main(void)
{
    const char *server = getenv("SNAPSERVER");
    if (server == NULL || server[0] == '\0' || strcmp(server, "NOT YET SET") == 0)
        return 1;

    const char *port_env = getenv("SNAPSERVER_PORT");
    const char *port = (port_env != NULL && port_env[0] != '\0') ? port_env : "1704";

    struct addrinfo hints;
    memset(&hints, 0, sizeof(hints));
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = SOCK_STREAM;

    struct addrinfo *res = NULL;
    if (getaddrinfo(server, port, &hints, &res) != 0)
        return 1;

    int ok = 0;
    for (struct addrinfo *ai = res; ai != NULL && !ok; ai = ai->ai_next)
        ok = (try_connect(ai->ai_addr, ai->ai_addrlen) == 0);

    freeaddrinfo(res);
    return ok ? 0 : 1;
}
