#!/bin/bash
##############################################################################
# start.sh — Lance Wireshark (GSMTAP) puis le conteneur OpenBSC
# Usage: sudo bash start.sh
##############################################################################
set -e

G='\033[0;32m'  Y='\033[1;33m'  N='\033[0m'
log()  { echo -e "${G}[START]${N} $1"; }
warn() { echo -e "${Y}[WARN]${N} $1"; }

command -v docker &>/dev/null || {
    echo "Docker non installé: curl -fsSL https://get.docker.com | sh"
    exit 1; }

# ── Wireshark GSMTAP ─────────────────────────────────────
log "Lancement Wireshark (GSMTAP udp:4729 sur lo)..."
killall -q wireshark 2>/dev/null || true
sleep 0.3
wireshark -i lo -k -f "udp port 4729" -Y gsmtap >/dev/null 2>&1 &
WIRESHARK_PID=$!
log "Wireshark PID: $WIRESHARK_PID"
sleep 2

# ── Conteneur ────────────────────────────────────────────
log "Démarrage du conteneur openbsc-nitb..."
docker rm -f openbsc-nitb 2>/dev/null || true

docker run -ti --rm \
    --name openbsc-nitb \
    --privileged \
    --cap-add=NET_ADMIN \
    --cap-add=SYS_RAWIO \
    --cap-add=SYS_PTRACE \
    --network=host \
    -v "$(pwd)/configs:/etc/osmocom:rw" \
    -v /dev/net/tun:/dev/net/tun \
    -v /dev/pts:/dev/pts \
    openbsc-nitb:latest

# ── Cleanup ──────────────────────────────────────────────
log "Conteneur arrêté — fermeture Wireshark..."
kill "$WIRESHARK_PID" 2>/dev/null || true
log "Terminé."
