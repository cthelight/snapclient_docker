#================================================================
# Simple builder container to contain (and not ship) the mess of the build.
#================================================================
FROM debian:bookworm-slim as builder
RUN apt-get update

# Install build deps for snapclient
RUN apt-get install pkg-config libasound2-dev curl build-essential libpulse-dev libvorbisidec-dev libvorbis-dev libopus-dev libflac-dev libsoxr-dev alsa-utils libavahi-client-dev avahi-daemon libexpat1-dev libboost-dev git -y
# Check out latest release (0.27.0)
RUN git clone https://github.com/badaix/snapcast.git
WORKDIR /snapcast
RUN git checkout v0.27.0

# Build just the client
RUN make -j $(nproc --all) client

# Move the resulting binary somewhere with a shorter path to reference later
RUN cp client/snapclient /snapclient

#================================================================
# Actual container that will be distributed.
# Copies relevant built artifacts from the builder container
#================================================================
FROM debian:bookworm-slim

# ENV variables used to configure snapclient instance
ENV SND_DEVICE="default"
ENV SNAPSERVER="NOT YET SET"
ENV SNAPSERVER_PORT="1704"
ENV CLIENT_HOST_ID="NOT YET SET"
ENV LIST_DEVICES_AND_EXIT="false"

# Apt dependencies for snapclient use, pulled from deps of prebuilt "with pulse" snapclient build
# Minor change for bookeworm is flac12 not flac8 being required
RUN apt-get update && apt-get install alsa-utils libasound2 libatomic1 libavahi-client3 libavahi-common3 libc6 libflac12 libgcc-s1 libogg0 libopus0 libsoxr0 libstdc++6 libvorbisidec1 adduser libpulse0 -y

# Steal the built snapclient from our builder container
COPY --from=builder /snapclient /usr/bin/snapclient

# Inject the startup script somewhere on PATH
COPY ./start.sh /usr/bin/start.sh

# Start snapclient
CMD start.sh
