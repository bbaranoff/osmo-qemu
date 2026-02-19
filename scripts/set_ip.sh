#!/bin/bash
##############################################################################
# set_ip.sh — Met à jour l'IP dans tous les fichiers de config
# Usage: ./set_ip.sh <nouvelle_ip>
##############################################################################
[ -z "$1" ] && {
    echo "Usage: $0 <ip>"
    echo "Exemple: $0 192.168.1.100"
    exit 1; }

NEW_IP="$1"
CONF_DIR="/etc/osmocom"

[ ! -d "$CONF_DIR" ] && { echo "Dossier configs/ introuvable"; exit 1; }

echo "Remplacement de l'IP → ${NEW_IP} dans ${CONF_DIR}..."
grep -rl '192\.168\.' "$CONF_DIR" | while read f; do
    sed -i "s/192\\.168\\.[0-9]*\\.[0-9]*/${NEW_IP}/g" "$f"
    echo "  updated: $f"
done
