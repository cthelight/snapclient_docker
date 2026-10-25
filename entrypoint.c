/* Static entrypoint for the snapclient container.
 *
 * Replaces the former start.sh shell script so the image needs no shell
 * (or any dynamic interpreter) at all. Behavior is identical:
 *
 *   LIST_DEVICES_AND_EXIT=true          -> run "snapclient -l" and exit with its code
 *   SNAPSERVER unset / "NOT YET SET"    -> abort with an error (exit 1)
 *   CLIENT_HOST_ID set (other than "NOT YET SET") -> pass --hostID <id>
 *   otherwise                           -> exec snapclient with the usual flags
 */

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>

static const char *env_or_empty(const char *name)
{
    const char *value = getenv(name);
    return value != NULL ? value : "";
}

static int run_snapclient(char *const argv[])
{
    execvp("snapclient", argv);
    perror("snapclient");
    return 127;
}

int main(void)
{
    if (strcmp(env_or_empty("LIST_DEVICES_AND_EXIT"), "true") == 0) {
        printf("Listing all available sound devices..\n");
        fflush(stdout);
        char *argv[] = { "snapclient", "-l", NULL };
        return run_snapclient(argv);
    }

    const char *server = env_or_empty("SNAPSERVER");
    if (strcmp(server, "NOT YET SET") == 0) {
        fprintf(stderr, "Must specify the snapserver to connect to. Aborting...\n");
        return 1;
    }

    const char *host_id = env_or_empty("CLIENT_HOST_ID");
    const int pass_host_id = strcmp(host_id, "NOT YET SET") != 0;

    const char *snd_device = env_or_empty("SND_DEVICE");
    const char *port = env_or_empty("SNAPSERVER_PORT");

    /* Server is passed as a URI (the -h/-p options were deprecated in snapclient 0.35.0).
     * tcp:// is the scheme the old -h/-p combination used; omit the port when unset so
     * snapclient applies its tcp default (1704). */
    char uri[2048];
    if (port[0] != '\0')
        snprintf(uri, sizeof(uri), "tcp://%s:%s", server, port);
    else
        snprintf(uri, sizeof(uri), "tcp://%s", server);

    char *argv[8];
    int n = 0;
    argv[n++] = "snapclient";
    argv[n++] = "-s";
    argv[n++] = (char *)snd_device;
    if (pass_host_id) {
        argv[n++] = "--hostID";
        if (host_id[0] != '\0')
            argv[n++] = (char *)host_id;
    }
    argv[n++] = uri;
    argv[n] = NULL;
    return run_snapclient(argv);
}
