Snapclient in a docker container

This repo contains the info required to create the snapclient docker container, which is used as a snapcast endpoint, for music streaming (see https://github.com/badaix/snapcast for info on snapcast).

As you likely want audio to be able to be played through a real audio device, you generally will need to map `/dev/snd` into the container as a device (unless, of course, you know what you are doing).

The following environment variables can be used when running this container:
 - `SNAPSERVER` **REQUIRED**
    - The hostname or IP of the server you would like the snapclient to connect to
 - `SNAPSERVER_PORT` (=1704) **OPTIONAL**
    - The port on which your snapserver is listening for connections on (default for snapcast is 1704)
 - `SND_DEVICE` (=default) **OPTIONAL**
    - The name/index of the audio device you would like snapclient to play audio to
 - `CLIENT_HOST_ID` (=MAC in container) **OPTIONAL**
    - The unique identifier snapserver can use to refer to this endpoint.
    - Defaults to the MAC address, however, those are not guaranteed to be static in docker, so it is recommended to chose your own.
 - `LIST_DEVICES_AND_EXIT` (=false) **OPTIONAL**
    - If this is set to true, the container will simply dump the list of snapcast-available audio devices and exit (equivalent to `snapclient -l`)
    - Snapclient will not be started in this mode

Note: I am not the author of snapclient. This repo simply wraps snapclient in a simple docker container to allow it to be run more easily on assorted HW.
