##############################################################################
# Dockerfile — OpenBSC (osmo-nitb) + EGPRS + QEMU Calypso
# Base: Ubuntu 22.04
#
# Versions cohérentes (ère mi-2019) :
#   libosmocore  1.10.0
#   libosmo-abis 0.8.0
#   libosmo-netif 0.7.0
#   libosmo-sccp 1.2.0
#   libosmo-dsp  0.5.0
#   libsmpp34    1.14.0
#   openbsc      master  (legacy archivé)
#   osmo-bts     0.8.1   (--with-openbsc)
#   osmo-trx     1.0.0
#   osmocom-bb   bbaranoff fork (layer23 + trxcon + osmocon + osmoload)
#   QEMU         bbaranoff fork (calypso machine)
##############################################################################

##############################
# STAGE 1 : BUILD
##############################
FROM ubuntu:22.04 AS builder

ENV DEBIAN_FRONTEND=noninteractive
ENV PREFIX=/usr/local
ENV LD_LIBRARY_PATH=${PREFIX}/lib
ENV PKG_CONFIG_PATH=${PREFIX}/lib/pkgconfig
ENV PATH=${PREFIX}/bin:${PATH}

# Toutes les dépendances de compilation en un seul layer
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential gcc-9 g++-9 make automake autoconf libtool pkg-config \
    git libpcsclite-dev libtalloc-dev libsctp-dev libgnutls28-dev \
    libmnl-dev libdbi-dev libdbd-sqlite3 libsqlite3-dev sqlite3 \
    libc-ares-dev libfftw3-dev libusb-1.0-0-dev liburing-dev \
    libreadline-dev libncurses5-dev python3 python3-setuptools \
    python-is-python3 python3-pip libortp-dev \
    gcc-arm-none-eabi \
    meson ninja-build libglib2.0-dev libpixman-1-dev libfdt-dev \
    zlib1g-dev libslirp-dev ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-9 90 \
    --slave /usr/bin/g++ g++ /usr/bin/g++-9 && \
    update-alternatives --set gcc /usr/bin/gcc-9

RUN pip3 install --no-cache-dir ninja tomli

WORKDIR /src

# ── libosmocore ──────────────────────────────────────────────────────────────
RUN git clone --depth=1 -b 1.10.0 \
    https://gitea.osmocom.org/osmocom/libosmocore && \
    cd libosmocore && autoreconf -fi && \
    ./configure --prefix=${PREFIX} --disable-doxygen && \
    make -j$(nproc) && make install && ldconfig

# ── libosmo-abis ─────────────────────────────────────────────────────────────
RUN git clone --depth=1 -b 0.8.0 \
    https://gitea.osmocom.org/osmocom/libosmo-abis && \
    cd libosmo-abis && autoreconf -fi && \
    ./configure --prefix=${PREFIX} --disable-dahdi && \
    make -j$(nproc) && make install && ldconfig

# ── libosmo-dsp ──────────────────────────────────────────────────────────────
RUN git clone --depth=1 -b 0.5.0 \
    https://gitea.osmocom.org/sdr/libosmo-dsp && \
    cd libosmo-dsp && autoreconf -fi && \
    ./configure --prefix=${PREFIX} && \
    make -j$(nproc) && make install && ldconfig

# ── libosmo-netif ────────────────────────────────────────────────────────────
RUN git clone --depth=1 -b 0.7.0 \
    https://gitea.osmocom.org/osmocom/libosmo-netif && \
    cd libosmo-netif && autoreconf -fi && \
    ./configure --prefix=${PREFIX} && \
    make -j$(nproc) && make install && ldconfig

# ── libosmo-sccp ─────────────────────────────────────────────────────────────
RUN git clone --depth=1 -b 1.2.0 \
    https://gitea.osmocom.org/osmocom/libosmo-sccp && \
    cd libosmo-sccp && autoreconf -fi && \
    ./configure --prefix=${PREFIX} && \
    make -j$(nproc) && make install && ldconfig

# ── libsmpp34 ────────────────────────────────────────────────────────────────
RUN git clone --depth=1 -b 1.14.0 \
    https://gitea.osmocom.org/cellular-infrastructure/libsmpp34 && \
    cd libsmpp34 && autoreconf -fi && \
    ./configure --prefix=${PREFIX} && \
    make -j$(nproc) && make install && ldconfig

# ── openbsc (osmo-nitb) ──────────────────────────────────────────────────────
RUN git clone https://gitea.osmocom.org/cellular-infrastructure/openbsc && \
    cd openbsc/openbsc && autoreconf -fi && \
    ./configure --prefix=${PREFIX} --enable-nat --enable-smpp && \
    make -j$(nproc) && make install && ldconfig

# ── osmo-bts ─────────────────────────────────────────────────────────────────
RUN git clone --depth=1 -b 0.8.1 \
    https://gitea.osmocom.org/cellular-infrastructure/osmo-bts && \
    cd osmo-bts && autoreconf -fi && \
    ./configure --prefix=${PREFIX} --enable-trx \
        --with-openbsc=/src/openbsc/openbsc/include && \
    make -j$(nproc) && make install && ldconfig

# ── osmo-trx ─────────────────────────────────────────────────────────────────
RUN git clone --depth=1 -b 1.0.0 \
    https://gitea.osmocom.org/cellular-infrastructure/osmo-trx && \
    cd osmo-trx && autoreconf -fi && \
    ./configure --prefix=${PREFIX} \
        --without-uhd --without-lms --without-usrp1 && \
    make -j$(nproc) && make install && ldconfig

# ── osmocom-bb (bbaranoff fork) ──────────────────────────────────────────────
# Fournit : osmocon, osmoload, transceiver, cell_log, mobile
RUN git clone https://github.com/bbaranoff/osmocom-bb /src/osmocom-bb && \
    cd /src/osmocom-bb/src && \
    make HOST_layer23_CONFARGS=--enable-transceiver nofirmware && \
    cp host/layer23/src/transceiver/transceiver ${PREFIX}/bin/ || true

# ── QEMU (bbaranoff fork — machine calypso) ──────────────────────────────────
RUN git clone https://github.com/bbaranoff/qemu.git /src/qemu && \
    mkdir /src/qemu/build && \
    cd /src/qemu/build && \
    ../configure --target-list=arm-softmmu && \
    ninja -j$(nproc) && ninja install

# ── firmware compal_e88 ──────────────────────────────────────────────────────
RUN git clone https://github.com/bbaranoff/firmware-osmobbtrx/ /tmp/firmware && \
    cp -r /tmp/firmware/board/compal_e88 /root/compal_e88 && \
    rm -rf /tmp/firmware

RUN git clone https://github.com/osmocom/libosmo-gprs /root/libosmo-gprs && \
    cd /root/libosmo-gprs/ && \
    autoreconf -fi && ./configure && make && make install && ldconfig

RUN git clone https://github.com/osmocom/osmocom-bb /root/osmocom-bb && \
    cd /src/osmocom-bb/src && \
    make nofirmware && \
    cp host/osmocon/osmocon   ${PREFIX}/bin/ && \
    cp host/osmocon/osmoload  ${PREFIX}/bin/ && \
    cp host/layer23/src/misc/cell_log           ${PREFIX}/bin/ || true && \
    cp host/layer23/src/mobile/mobile           ${PREFIX}/bin/ || true

##############################
# STAGE 2 : RUNTIME
##############################
FROM builder AS openbsc_egprs

LABEL maintainer="openbsc-egprs"
LABEL description="OpenBSC (osmo-nitb) + EGPRS + QEMU Calypso"

ENV DEBIAN_FRONTEND=noninteractive
ENV LD_LIBRARY_PATH=/usr/local/lib
ENV PATH=/usr/local/bin:${PATH}

RUN apt-get update && apt-get install -y --no-install-recommends \
    # runtime libs
    libtalloc2 libsctp1 libgnutls30 libmnl0 \
    libdbi1 libdbd-sqlite3 libsqlite3-0 sqlite3 psmisc \
    libc-ares2 libfftw3-single3 libusb-1.0-0 \
    libreadline8 libncurses6 libpcsclite1 gdb-multiarch\
    libortp15 libglib2.0-0 libpixman-1-0 libfdt1 libslirp0 liburing-dev gcc-arm-none-eabi \
    # outils
    python3 python3-pip \
    tmux socat telnet nano iproute2 iptables dnsmasq \
    gcc-arm-none-eabi \
    && rm -rf /var/lib/apt/lists/*

RUN ln -s /usr/bin/gdb-multiarch /usr/bin/arm-none-eabi-gdb
# Binaires et libs compilés
COPY --from=builder /usr/local/bin/  /usr/local/bin/
COPY --from=builder /usr/local/lib/  /usr/local/lib/
COPY --from=builder /usr/local/share/ /usr/local/share/
COPY --from=builder /root/compal_e88 /root/compal_e88
RUN ldconfig

# Structure des répertoires
RUN mkdir -p /etc/osmocom /var/lib/osmocom /data

# Scripts et configs
COPY scripts/entrypoint.sh     /entrypoint.sh
COPY scripts/run.sh            /root/run.sh
COPY scripts/set_ip.sh         /root/set_ip.sh
COPY scripts/launch_calypso.sh /root/launch_calypso.sh
COPY scripts/calypso_loader.py /root/calypso_loader.py
COPY scripts/calypso.sh        /root/calypso.sh
COPY configs/                  /etc/osmocom/
RUN chmod +x /entrypoint.sh /root/run.sh /root/launch_calypso.sh /root/calypso.sh

# HLR vide
RUN touch /data/hlr.sqlite3

# Ports VTY (telnet)
EXPOSE 4240 4241 4242 4245 4247 4260
# Abis / GPRS / GSMTAP
EXPOSE 3002/tcp 3003/tcp 4729/udp 23000/udp

VOLUME ["/data", "/etc/osmocom"]

ENTRYPOINT ["/entrypoint.sh"]
CMD ["/bin/bash"]
