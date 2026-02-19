#!/bin/bash
##############################################################################
# entrypoint.sh — Démarre la pile OpenBSC/EGPRS dans le conteneur
##############################################################################
set -e

G='\033[0;32m'  Y='\033[1;33m'  N='\033[0m'
log()  { echo -e "${G}[ENTRYPOINT]${N} $1"; }
warn() { echo -e "${Y}[WARN]${N} $1"; }

##############################################################################
# 1. Interface TUN pour GGSN (GPRS)
##############################################################################
log "Configuration réseau GPRS (TUN/NAT)..."
mkdir -p /dev/net
[ ! -c /dev/net/tun ] && mknod /dev/net/tun c 10 200 || true

ip tuntap add dev apn0 mode tun   2>/dev/null || true
ip addr add 192.168.100.1/24 dev apn0 2>/dev/null || true
ip link set apn0 up               2>/dev/null || true
echo 1 > /proc/sys/net/ipv4/ip_forward 2>/dev/null || true

##############################################################################
# 2. ptrace scope — nécessaire pour /proc/PID/mem (calypso_loader)
##############################################################################
if [ -f /proc/sys/kernel/yama/ptrace_scope ]; then
    echo 0 > /proc/sys/kernel/yama/ptrace_scope 2>/dev/null || \
        warn "Could not set ptrace_scope=0 (run with --privileged)"
fi

##############################################################################
# 3. Lance la pile GSM via run.sh (tmux)
##############################################################################
log "Lancement de la pile GSM..."
exec bash /root/run.sh
