#!/bin/bash
##############################################################################
# calypso.sh — Connexion d'un Calypso réel (Motorola C1xx) via USB
#
# Usage: bash calypso.sh [/dev/ttyUSB0]
##############################################################################

SERIAL="${1:-/dev/ttyUSB0}"
FIRMWARE="/root/compal_e88/layer1.compalram.bin"

[ ! -e "$SERIAL" ] && {
    echo "Erreur: $SERIAL introuvable"
    echo "Usage: $0 [/dev/ttyUSBx]"
    exit 1; }

[ ! -f "$FIRMWARE" ] && {
    echo "Erreur: firmware $FIRMWARE introuvable"
    exit 1; }

echo "Connexion au Calypso réel sur $SERIAL..."
echo "Firmware: $FIRMWARE"
echo ""
osmocon -p "$SERIAL" -m c123xor "$FIRMWARE"
