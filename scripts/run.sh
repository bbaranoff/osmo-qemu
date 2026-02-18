#!/bin/bash
# ============================================================
#  run.sh — Full Osmocom GSM stack in tmux
#
#  Window layout:
#    0: osmo-nitb    (MSC/HLR/BSC combo)
#    1: calypso      (QEMU + osmocon)
#    2: transceiver  (L1→TRX bridge)
#    3: osmo-bts-trx (BTS)
#    4: cell_log     (GSMTAP sniffer via socat proxy)
#
#  Usage: bash run.sh
#  Stop:  tmux kill-session -t gsm
# ============================================================

SESSION="gsm"
DELAY=3  # seconds between component starts

# Colors for logging
R='\033[1;31m'  G='\033[1;32m'  B='\033[1;34m'
Y='\033[1;33m'  C='\033[1;36m'  N='\033[0m'

banner() {
    echo -e "${C}"
    echo "╔══════════════════════════════════════════════╗"
    echo "║         🗼  Osmocom GSM Stack  🗼            ║"
    echo "║                                              ║"
    echo "║  [0] osmo-nitb      MSC/HLR/BSC              ║"
    echo "║  [1] calypso        QEMU + osmocon           ║"
    echo "║  [2] transceiver    L1 → TRX bridge          ║"
    echo "║  [3] osmo-bts-trx   BTS                      ║"
    echo "║  [4] cell_log       GSMTAP sniffer           ║"
    echo "╚══════════════════════════════════════════════╝"
    echo -e "${N}"
}

log() {
    echo -e "${G}[$(date +%H:%M:%S)]${N} ${B}[$1]${N} $2"
}

# Kill old session if exists
tmux has-session -t "$SESSION" 2>/dev/null && {
    log "CLEANUP" "Killing old '$SESSION' session..."
    tmux kill-session -t "$SESSION"
    sleep 1
}

# Kill leftover processes
for proc in osmo-nitb osmo-bts-trx qemu-system-arm osmocon transceiver cell_log socat; do
    killall -q "$proc" 2>/dev/null
done
rm -f /tmp/osmocom_l2.2
sleep 0.5

banner

# ── Window 0: osmo-nitb ──────────────────────────────────
log "NITB" "Starting osmo-nitb (MSC/HLR/BSC)..."
tmux new-session -d -s "$SESSION" -n "nitb" -x 200 -y 50
tmux send-keys -t "$SESSION:nitb" "
    clear
    echo -e '${Y}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}'
    echo -e '${Y}  📡  osmo-nitb — Core Network${N}'
    echo -e '${Y}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}'
    cd /etc/osmocom
    echo '[*] Launching osmo-nitb...'
    osmo-nitb --yes-i-really-want-to-run-prehistoric-software --debug=DRLL:DCC:DMM:DRR:DRSL:DNM 
" Enter

sleep "$DELAY"

# ── Window 1: QEMU Calypso ───────────────────────────────
log "CALYPSO" "Starting QEMU Calypso + osmocon..."
tmux new-window -t "$SESSION" -n "calypso"
tmux send-keys -t "$SESSION:calypso" "
    clear
    echo -e '${Y}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}'
    echo -e '${Y}  📱  QEMU Calypso — Phone Emulator${N}'
    echo -e '${Y}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}'
    cd /src/qemu
    echo '[*] Launching QEMU + osmocon...'
    bash launch_calypso.sh
" Enter

sleep "$DELAY"

# ── Window 2: Transceiver ────────────────────────────────
log "TRX" "Starting transceiver (L1→TRX bridge)..."
tmux new-window -t "$SESSION" -n "trx"
tmux send-keys -t "$SESSION:trx" "
    clear
    echo -e '${Y}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}'
    echo -e '${Y}  🔗  Transceiver — L1/TRX Bridge${N}'
    echo -e '${Y}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}'
    cd /src/osmocom-bb/src/host/layer23/src/transceiver
    echo '[*] Waiting for L1CTL socket...'
    for i in \$(seq 1 30); do
        [ -S /tmp/osmocom_l2 ] && break
        sleep 1
    done
    if [ -S /tmp/osmocom_l2 ]; then
        echo '[+] L1CTL socket ready, launching transceiver...'
        ./transceiver -a 1 -r 99
    else
        echo '[-] ERROR: /tmp/osmocom_l2 not found after 30s'
    fi
" Enter

sleep "$DELAY"

# ── Window 3: osmo-bts-trx ───────────────────────────────
log "BTS" "Starting osmo-bts-trx..."
tmux new-window -t "$SESSION" -n "bts"
tmux send-keys -t "$SESSION:bts" "
    clear
    echo -e '${Y}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}'
    echo -e '${Y}  🗼  osmo-bts-trx — Base Station${N}'
    echo -e '${Y}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}'
    cd /etc/osmocom
    echo '[*] Launching osmo-bts-trx...'
    osmo-bts-trx -i 0.0.0.0
" Enter

sleep "$DELAY"

# ── Window 4: cell_log (socat proxy + GSMTAP sniffer) ────
log "CELLLOG" "Starting socat proxy + cell_log..."
tmux new-window -t "$SESSION" -n "celllog"
tmux send-keys -t "$SESSION:celllog" "
    clear
    echo -e '${Y}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}'
    echo -e '${Y}  🔍  cell_log — GSMTAP Sniffer${N}'
    echo -e '${Y}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}'

    echo '[*] Waiting for /tmp/osmocom_l2 (transceiver must be up)...'
    for i in \$(seq 1 60); do
        [ -S /tmp/osmocom_l2 ] && break
        sleep 1
    done
    if [ ! -S /tmp/osmocom_l2 ]; then
        echo '[-] ERROR: /tmp/osmocom_l2 not found after 60s'
        exit 1
    fi

    echo '[+] L1CTL socket found.'
    echo '[*] Starting socat proxy: /tmp/osmocom_l2 → /tmp/osmocom_l2.2'
    rm -f /tmp/osmocom_l2.2
    socat UNIX-LISTEN:/tmp/osmocom_l2.2,fork,reuseaddr \
          UNIX-CONNECT:/tmp/osmocom_l2 &
    SOCAT_PID=\$!

    echo '[*] Waiting for proxy socket /tmp/osmocom_l2.2...'
    for i in \$(seq 1 20); do
        [ -S /tmp/osmocom_l2.2 ] && break
        sleep 0.2
    done
    if [ ! -S /tmp/osmocom_l2.2 ]; then
        echo '[-] ERROR: socat proxy socket not ready'
        kill \$SOCAT_PID 2>/dev/null
        exit 1
    fi

    echo '[+] Proxy ready. Launching cell_log on /tmp/osmocom_l2.2'
    echo '[+] GSMTAP frames → udp://127.0.0.1:4729'
    echo -e '${Y}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}'
    /root/osmocom-bb/src/host/layer23/src/misc/cell_log -O /tmp/osmocom_l2.2
    kill \$SOCAT_PID 2>/dev/null
    rm -f /tmp/osmocom_l2.2
" Enter

# ── Done ──────────────────────────────────────────────────
echo ""
log "DONE" "All components launched!"
echo ""
echo -e "  ${G}tmux attach -t $SESSION${N}        → attach to session"
echo -e "  ${G}Ctrl+B then 0-4${N}               → switch windows"
echo -e "  ${G}tmux kill-session -t $SESSION${N}  → stop everything"
echo -e "  ${G}Wireshark: udp port 4729${N}       → GSMTAP frames"
echo ""

# Auto-attach
tmux select-window -t "$SESSION:nitb"
exec tmux attach -t "$SESSION"
