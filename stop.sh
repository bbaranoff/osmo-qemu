#!/bin/bash
##############################################################################
# stop.sh - Arrêt du conteneur OpenBSC
##############################################################################

echo "Arrêt du conteneur openbsc-nitb..."

if command -v docker-compose &>/dev/null; then
    docker-compose down
elif docker compose version &>/dev/null 2>&1; then
    docker compose down
else
    docker rm -f openbsc-nitb 2>/dev/null || true
fi

echo "Conteneur arrêté."
echo ""
echo "Pour supprimer les données persistantes (HLR, etc.) :"
echo "  docker volume rm openbsc-data"
