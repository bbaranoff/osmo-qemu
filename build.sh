#!/bin/bash
##############################################################################
# build.sh - Compile l'image Docker OpenBSC (osmo-nitb) + EGPRS
#
# Usage: sudo ./build.sh
##############################################################################

set -e

IMAGE_NAME="openbsc-nitb"
GREEN='\033[0;32m'
NC='\033[0m'

echo -e "${GREEN}[BUILD]${NC} Construction de l'image Docker ${IMAGE_NAME}..."
echo -e "${GREEN}[BUILD]${NC} (Cela peut prendre 20-40 minutes la première fois)"
echo ""

docker build -t "${IMAGE_NAME}:latest" .

echo ""
echo -e "${GREEN}[BUILD]${NC} =========================================="
echo -e "${GREEN}[BUILD]${NC}   IMAGE CONSTRUITE AVEC SUCCÈS !"
echo -e "${GREEN}[BUILD]${NC} =========================================="
echo -e "${GREEN}[BUILD]${NC} Image : ${IMAGE_NAME}:latest"
echo -e "${GREEN}[BUILD]${NC}"
echo -e "${GREEN}[BUILD]${NC} Lancer avec :"
echo -e "${GREEN}[BUILD]${NC}   sudo ./start.sh"
echo -e "${GREEN}[BUILD]${NC}   ou : docker-compose up -d"
