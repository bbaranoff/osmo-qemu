##############################################################################
# Dockerfile - OpenBSC (osmo-nitb) + pile EGPRS
# Base: Ubuntu 18.04 (Bionic)
# Multi-stage : build puis runtime
#
# Versions choisies cohérentes (ère mi-2019, compatibles entre elles) :
#   libosmocore  1.1.0   →  base de tout
#   libosmo-abis 0.7.0   →  requiert libosmocore >= 1.0.0
#   libosmo-netif 0.6.0  →  requiert libosmocore >= 1.0.0
#   libosmo-sccp 1.1.0   →  requiert libosmocore >= 1.0.0
#   libsmpp34    1.14.0
#   openbsc      master  →  legacy, dernière version disponible
#   osmo-bts     1.0.0
#   osmo-trx     1.0.0
#   osmo-pcu     0.8.0
#   osmo-ggsn    1.5.0
#   osmo-sgsn    1.6.0
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

# Dépendances de compilation
RUN apt-get update && apt-get install -y \
    build-essential gcc-9 g++-9 make automake autoconf libtool pkg-config \
    git libpcsclite-dev libtalloc-dev libsctp-dev libgnutls28-dev \
    libmnl-dev libdbi-dev libdbd-sqlite3 libsqlite3-dev sqlite3 \
    libc-ares-dev libfftw3-dev libusb-1.0-0-dev \
    libreadline-dev libncurses5-dev python3 python3-setuptools libortp-dev python3 python-is-python3 \
    && rm -rf /var/lib/apt/lists/*

RUN update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-9 90 \
  --slave /usr/bin/g++ g++ /usr/bin/g++-9

RUN update-alternatives --set gcc /usr/bin/gcc-9

WORKDIR /src

# ── libosmocore 1.1.0 ───────────────────────────────────────────────────
RUN git clone https://gitea.osmocom.org/osmocom/libosmocore && \
    cd libosmocore && git checkout 1.1.0 && \
    autoreconf -fi && \
    ./configure --prefix=${PREFIX} --disable-doxygen && \
    make -j$(nproc) && make install && ldconfig

# ── libosmo-abis 0.7.0 (requiert libosmocore >= 1.0.0) ─────────────────
RUN git clone https://gitea.osmocom.org/osmocom/libosmo-abis && \
    cd libosmo-abis && git checkout 0.7.0 && \
    autoreconf -fi && \
    ./configure --prefix=${PREFIX} && \
    make -j$(nproc) && make install && ldconfig

RUN git clone https://gitea.osmocom.org/sdr/libosmo-dsp && \
    cd libosmo-dsp && git checkout 0.4.0 && \
    autoreconf -fi && \
    ./configure --prefix=${PREFIX} && \
    make -j$(nproc) && make install && ldconfig

# ── libosmo-netif 0.6.0 (requiert libosmocore >= 1.0.0) ────────────────
RUN git clone https://gitea.osmocom.org/osmocom/libosmo-netif && \
    cd libosmo-netif && git checkout 0.6.0 && \
    autoreconf -fi && \
    ./configure --prefix=${PREFIX} && \
    make -j$(nproc) && make install && ldconfig

# ── libosmo-sccp 1.1.0 ─────────────────────────────────────────────────
RUN git clone https://gitea.osmocom.org/osmocom/libosmo-sccp && \
    cd libosmo-sccp && git checkout 1.1.0 && \
    autoreconf -fi && \
    ./configure --prefix=${PREFIX} && \
    make -j$(nproc) && make install && ldconfig

# ── libsmpp34 1.14.0 ───────────────────────────────────────────────────
RUN git clone https://gitea.osmocom.org/cellular-infrastructure/libsmpp34 && \
    cd libsmpp34 && git checkout 1.14.0 && \
    autoreconf -fi && \
    ./configure --prefix=${PREFIX} && \
    make -j$(nproc) && make install && ldconfig

# ── OpenBSC (osmo-nitb) ── LE CŒUR ─────────────────────────────────────
# Legacy : on utilise master (dernier état du repo archivé)
RUN git clone https://gitea.osmocom.org/cellular-infrastructure/openbsc && \
    cd openbsc/openbsc && autoreconf -fi && \
    ./configure --prefix=${PREFIX} --enable-nat --enable-smpp && \
    make -j$(nproc) && make install && ldconfig

# ── osmo-bts 1.0.0 (virtual + trx) ─────────────────────────────────────
RUN git clone https://gitea.osmocom.org/cellular-infrastructure/osmo-bts && \
    cd osmo-bts && git checkout 0.8.1 && \
    autoreconf -fi && \
    ./configure --prefix=${PREFIX} --enable-trx \
        --with-openbsc=/src/openbsc/openbsc/include && \
    make -j$(nproc) && make install && ldconfig

# ── osmo-trx 1.0.0 (fake_trx pour simulation) ──────────────────────────
RUN git clone https://gitea.osmocom.org/cellular-infrastructure/osmo-trx && \
    cd osmo-trx && git checkout 1.0.0 && \
    autoreconf -fi && \
    ./configure --prefix=${PREFIX} \
        --without-uhd --without-lms --without-usrp1 && \
    make -j$(nproc) && make install && ldconfig


# ── OsmocomBB (mobile virtuel + trxcon) ─────────────────────────────────
RUN git clone https://github.com/bbaranoff/osmocom-bb && \
    cd osmocom-bb/src && \
    make HOST_layer23_CONFARGS=--enable-transceiver nofirmware



##############################
# STAGE 2 : RUNTIME
##############################
FROM builder as openbsc_egprs

LABEL maintainer="openbsc-egprs"
LABEL description="OpenBSC (osmo-nitb) + EGPRS stack on Ubuntu 18.04"

ENV DEBIAN_FRONTEND=noninteractive
ENV LD_LIBRARY_PATH=/usr/local/lib
ENV PATH=/usr/local/bin:${PATH}

# Dépendances runtime uniquement
RUN apt-get update && apt-get install -y --no-install-recommends \
    libtalloc2 libsctp1 libgnutls30 libmnl0 \
    libdbi1 libdbd-sqlite3 libsqlite3-0 sqlite3 \
    libc-ares2 libfftw3-single3 libusb-1.0-0 \
    libreadline-dev libncurses5 libpcsclite1 \
    telnet tmux iproute2 iptables dnsmasq \
    python3 \
    && rm -rf /var/lib/apt/lists/*

# Copier les binaires et bibliothèques compilés
COPY --from=builder /usr/local/bin/ /usr/local/bin/
COPY --from=builder /usr/local/lib/ /usr/local/lib/
COPY --from=builder /usr/local/share/ /usr/local/share/
RUN ldconfig

# Créer les répertoires
RUN mkdir -p /etc/osmocom /var/lib/osmocom /data

# Copier les configs et scripts
COPY configs/ /etc/osmocom/
COPY scripts/entrypoint.sh /entrypoint.sh
COPY scripts/launch_calypso.sh /root
RUN chmod +x /root/launch_calypso.sh
RUN chmod +x /entrypoint.sh

# Créer la base HLR vide
RUN touch /data/hlr.sqlite3
RUN apt-get update && apt-get install -y \
    git \
    build-essential \
    pkg-config \
    meson \
    ninja-build \
    python3 \
    python3-pip \
    python3-venv \
    libglib2.0-dev \
    libpixman-1-dev \
    libfdt-dev \
    zlib1g-dev \
    libslirp-dev \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# ---- deps python (tu les veux explicitement) ----
RUN pip3 install --no-cache-dir ninja tomli

WORKDIR /src

# ---- clone ton fork ----
RUN git clone https://github.com/bbaranoff/qemu.git

# ---- configure QEMU ----
RUN pip install tomli
RUN cd qemu && mkdir build && cd build && ../configure --target-list=arm-softmmu

# ---- build ----
RUN cd qemu/build && ninja && ninja install

RUN git clone https://github.com/bbaranoff/firmware-osmobbtrx/ /root/firmware/
RUN cp -r /root/firmware/board/compal_e88 /root/compal_e88
RUN cp /src/osmocom-bb/src/host/osmocon/osmocon /usr/local/bin
RUN cp /src/osmocom-bb/src/host/osmocon/osmoload /usr/local/bin
RUN cp /src/osmocom-bb/src/host/layer23/src/transceiver/transceiver /usr/local/bin
# shell par défaut
RUN apt update && apt install nano socat telnet -y
CMD ["/bin/bash"]

# Ports VTY
EXPOSE 4240 4241 4242 4245 4247 4260

# Ports réseau internes (Abis, GPRS, etc.)
EXPOSE 3002/tcp 3003/tcp 4729/udp 23000/udp

VOLUME ["/data", "/etc/osmocom"]
COPY scripts/run.sh /root
RUN chmod +x /root/run.sh

ENTRYPOINT ["/entrypoint.sh"]
CMD ["/bin/bash"]
