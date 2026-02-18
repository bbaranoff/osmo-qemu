#!/bin/bash
##############################################################################
# calypso.sh - Connexion d'un téléphone Calypso (Motorola C1xx) réel
#
# Prérequis : un téléphone Calypso flashé avec OsmocomBB connecté via USB
# Usage: sudo ./calypso.sh [/dev/ttyUSB0]
##############################################################################

SERIAL="${1:-/dev/ttyUSB0}"

if [ ! -e "${SERIAL}" ]; then
    echo "Erreur: ${SERIAL} introuvable."
    echo "Branchez votre Calypso et vérifiez le port série."
    echo "Usage: $0 [/dev/ttyUSBx]"
    exit 1
fi

echo "Connexion au Calypso sur ${SERIAL}..."
echo "Le téléphone doit être flashé avec le firmware OsmocomBB."
echo ""

# Lancer osmocon pour charger le firmware
docker exec -it openbsc-nitb bash -c \
    "osmocon -p ${SERIAL} -m c123xor /usr/local/share/osmocom-bb/firmware/board/compal_e88/layer1.compalram.bin"
