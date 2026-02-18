#!/bin/bash
##############################################################################
# start.sh - Démarrage du conteneur OpenBSC (osmo-nitb) + EGPRS
#
# Usage: sudo ./start.sh
##############################################################################
set -e
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'
log()  { echo -e "${GREEN}[START]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

# Vérifier que Docker est installé
if ! command -v docker &>/dev/null; then
    echo "Docker n'est pas installé. Installez-le d'abord :"
    echo "  curl -fsSL https://get.docker.com | sh"
    exit 1
fi

##############################################################################
# 1. Wireshark — GSMTAP sur loopback (port UDP 4729)
##############################################################################
log "Lancement de Wireshark (GSMTAP sur lo)..."

# Tuer une ancienne instance si besoin
killall -q wireshark 2>/dev/null || true
sleep 0.3

wireshark -i lo -k -f "udp port 4729" -Y gsmtap >/dev/null 2>&1 &
WIRESHARK_PID=$!
log "Wireshark PID: $WIRESHARK_PID"

# Attendre un peu que Wireshark ouvre sa fenêtre
sleep 2

##############################################################################
# 2. Conteneur OpenBSC
##############################################################################
log "Démarrage du conteneur openbsc-nitb..."

# Arrêter le conteneur existant
docker rm -f openbsc-nitb 2>/dev/null || true

docker run -ti --rm \
    --name openbsc-nitb \
    --privileged \
    --cap-add=NET_ADMIN \
    --cap-add=SYS_RAWIO \
    --network=host \
    -v "$(pwd)/configs:/etc/osmocom:rw" \
    -v /dev/net/tun:/dev/net/tun \
    -v /dev/pts:/dev/pts \
    openbsc-nitb:latest

##############################################################################
# 3. Cleanup à la sortie
##############################################################################
log "Conteneur arrêté, fermeture de Wireshark..."
kill "$WIRESHARK_PID" 2>/dev/null || true
log "Terminé."
