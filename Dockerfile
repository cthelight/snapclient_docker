#================================================================ Simple builder container to contain (and not ship) the mess of the build. ================================================================
# Alpine + musl toolchain: snapclient is linked fully static so the final image can be "FROM scratch".
# clang/libc++ is used because Alpine ships libc++-static but no libstdc++-static.
FROM alpine:3.21 AS builder

RUN apk add --no-cache \
    autoconf automake libtool gettext bash build-base \
    clang19 libc++ libc++-dev libc++-static \
    cmake meson ninja git pkgconf file curl \
    expat-dev expat-static soxr-dev soxr-static \
    openssl-dev openssl-libs-static \
    zlib-static \
    boost1.84-dev

# libogg + libvorbis (no release tags on github; official xiph tarballs)
RUN mkdir /src && cd /src \
    && curl -sSL -o ogg.tar.gz https://downloads.xiph.org/releases/ogg/libogg-1.3.5.tar.gz \
    && tar xzf ogg.tar.gz
WORKDIR /src/libogg-1.3.5
RUN ./configure --prefix=/usr --enable-static --disable-shared && make -j$(nproc) && make install

RUN cd /src \
    && curl -sSL -o vorbis.tar.gz https://downloads.xiph.org/releases/vorbis/libvorbis-1.3.7.tar.gz \
    && tar xzf vorbis.tar.gz
WORKDIR /src/libvorbis-1.3.7
RUN ./configure --prefix=/usr --enable-static --disable-shared && make -j$(nproc) && make install

RUN git clone --depth 1 --branch 1.4.3 https://github.com/xiph/flac /src/flac
WORKDIR /src/flac
RUN ./autogen.sh && ./configure --prefix=/usr --enable-static --disable-shared && make -j$(nproc) && make install

RUN git clone --depth 1 --branch v1.5.2 https://github.com/xiph/opus /src/opus
WORKDIR /src/opus
RUN ./autogen.sh && ./configure --prefix=/usr --enable-static --disable-shared && make -j$(nproc) && make install

RUN git clone --depth 1 --branch v1.2.16 https://github.com/alsa-project/alsa-lib /src/alsa-lib
WORKDIR /src/alsa-lib
RUN autoreconf -fi && ./configure --prefix=/usr --enable-static --disable-shared && make -j$(nproc) && make install

# dbus from source: Alpine's libdbus-1.a is LTO objects (unusable by ld without a plugin),
# and dbus >= 1.15 has no autotools build. CMake hardcodes SHARED for the client lib,
# so use Meson with default_library=static.
RUN curl -sSL -o /src/dbus.tar.gz https://gitlab.freedesktop.org/dbus/dbus/-/archive/dbus-1.16.2/dbus-1.16.2.tar.gz \
    && tar xzf /src/dbus.tar.gz -C /src \
    && mv /src/dbus-dbus-1.16.2-* /src/dbus-1.16.2 \
    && cd /src/dbus-1.16.2 \
    && meson setup build -Dprefix=/usr -Ddefault_library=static \
        -Dmessage_bus=false -Dtools=false -Dmodular_tests=disabled -Dxml_docs=disabled \
    && ninja -C build \
    && ninja -C build install \
    && rm -rf /src/dbus-1.16.2 /src/dbus.tar.gz

# avahi from the official release tarball (avahi's git autogen.sh does not work on Alpine).
# The generated avahi-client.pc is wrong for static linking (missing -ldbus-1/-lexpat and
# wrong library order), so patch it after install.
RUN curl -sSL -o /src/avahi-0.8.tar.gz https://avahi.org/download/avahi-0.8.tar.gz \
    && tar xzf /src/avahi-0.8.tar.gz -C /src \
    && cd /src/avahi-0.8 && ./configure --prefix=/usr --enable-static --disable-shared \
        --disable-glib --disable-gobject --disable-gtk --disable-gtk3 \
        --disable-libevent --disable-qt4 --disable-qt5 --disable-libdaemon --disable-gdbm \
        --disable-mono --disable-python --disable-pygobject --disable-autoipd \
        --disable-nls --disable-manpages --with-distro=none \
    && make -j$(nproc) && make install \
    && sed -i 's|^Libs:.*|Libs: -L/usr/lib -Wl,--start-group -lavahi-client -lavahi-common -ldbus-1 -lexpat -Wl,--end-group|' /usr/lib/pkgconfig/avahi-client.pc

# Check out the release to build
RUN git clone --depth 1 --branch v0.35.0 https://github.com/snapcast/snapcast /src/snapcast
WORKDIR /src/snapcast
# -static + libc++ for the musl static link; -lgomp because Alpine's static libsoxr
# (a snapclient dependency) is built with OpenMP.
RUN cmake -B build \
    -DBUILD_SERVER=OFF -DBUILD_STATIC_LIBS=ON \
    -DOPENSSL_USE_STATIC_LIBS=ON -DOPENSSL_ROOT_DIR=/usr \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++ \
    -DCMAKE_C_FLAGS="-static -ffunction-sections -fdata-sections" \
    -DCMAKE_CXX_FLAGS="-static -stdlib=libc++ -ffunction-sections -fdata-sections" \
    -DCMAKE_EXE_LINKER_FLAGS="-static -s -Wl,--gc-sections" \
    -DCMAKE_CXX_STANDARD_LIBRARIES="-Wl,--start-group -lc -lc++ -lc++abi -lm -lgomp -Wl,--end-group"
RUN cmake --build build -j$(nproc)
RUN file bin/snapclient && ./bin/snapclient -v

# Static entrypoint (replaces start.sh; the image needs no shell)
COPY ./entrypoint.c /src/entrypoint.c
RUN gcc -O2 -Wall -Wextra -static -s -o /entrypoint /src/entrypoint.c

# Static healthcheck: TCP-connect probe against SNAPSERVER:SNAPSERVER_PORT
# (the image has no shell or network tools to run a HEALTHCHECK with)
COPY ./healthcheck.c /src/healthcheck.c
RUN gcc -O2 -Wall -Wextra -static -s -o /healthcheck /src/healthcheck.c

#================================================================
# Actual container that will be distributed.
# Three statically linked binaries and nothing else.
#================================================================
FROM scratch
COPY --from=builder /src/snapcast/bin/snapclient /usr/local/bin/snapclient
COPY --from=builder /entrypoint /usr/bin/entrypoint
COPY --from=builder /healthcheck /usr/bin/healthcheck
# ALSA global config (alsa.conf + pcm/cards definitions); without it ALSA
# cannot resolve the "default" device on real hardware
COPY --from=builder /usr/share/alsa /usr/share/alsa

# ENV variables used to configure snapclient instance
ENV PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
ENV SND_DEVICE="default"
ENV SNAPSERVER="NOT YET SET"
ENV SNAPSERVER_PORT="1704"
ENV CLIENT_HOST_ID="NOT YET SET"
ENV LIST_DEVICES_AND_EXIT="false"

# Healthy = snapserver reachable (snapclient itself exposes no external state)
HEALTHCHECK --interval=30s --timeout=10s --start-period=15s --retries=3 \
    CMD ["/usr/bin/healthcheck"]

# Start snapclient
CMD ["/usr/bin/entrypoint"]
