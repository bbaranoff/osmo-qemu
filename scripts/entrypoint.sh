#!/bin/bash
##############################################################################
# entrypoint.sh - Démarre toute la pile OpenBSC/EGPRS dans le conteneur
##############################################################################

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()  { echo -e "${GREEN}[ENTRYPOINT]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

CONF="/etc/osmocom"
DATA="/data"

##############################################################################
# 1. Configuration réseau GPRS (TUN + NAT)
##############################################################################
log "Configuration réseau GPRS..."

# Créer l'interface TUN pour le GGSN
mkdir -p /dev/net
if [ ! -c /dev/net/tun ]; then
    mknod /dev/net/tun c 10 200
fi

ip tuntap add dev apn0 mode tun 2>/dev/null || true
ip addr add 192.168.100.1/24 dev apn0 2>/dev/null || true
ip link set apn0 up 2>/dev/null || true

# IP forwarding
echo 1 > /proc/sys/net/ipv4/ip_forward 2>/dev/null || true

##############################################################################
# 2. Lancement de la pile GSM
##############################################################################
log "Lancement de la pile GSM dans tmux..."
exec bash /root/run.sh
