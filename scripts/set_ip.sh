#!/bin/bash
##############################################################################
# set_ip.sh - Met à jour l'adresse IP dans tous les fichiers de config
# Usage: ./set_ip.sh <votre_ip>
##############################################################################

if [ -z "$1" ]; then
    echo "Usage: $0 <votre_ip>"
    echo "Exemple: $0 192.168.1.100"
    exit 1
fi

NEW_IP="$1"
CONF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/configs"

echo "Remplacement de l'IP par ${NEW_IP} dans ${CONF_DIR}..."
sed -i -e "s/192\.168\.1\.69/${NEW_IP}/g" "${CONF_DIR}"/*.cfg

echo "Terminé. Redémarrez le conteneur :"
echo "  sudo ./stop.sh && sudo ./start.sh"
