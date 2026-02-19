#!/bin/bash
# =============================================================
#  launch_calypso.sh — Calypso QEMU BTS
#
#  Ce script :
#    1. Extrait les segments ELF (sans le gap 128KB)
#    2. Lance QEMU avec le loader (gelé -s -S, GDB :1234)
#    3. Injecte le firmware via gpa2hva + /proc/PID/mem
#    4. Lance calypso_loader.py → /tmp/osmocom_loader
#    5. Attend — osmoload se lance MANUELLEMENT dans un autre terminal
#       (fenêtre tmux 2 = "osmoload" dans run.sh)
#
#  Usage :
#    bash launch_calypso.sh [firmware.elf]
#    default: /root/compal_e88/layer1.highram.elf
# =============================================================

QEMU=qemu-system-arm
LOADER=${LOADER:-/root/compal_e88/loader.highram.elf}
FIRMWARE=${1:-/root/compal_e88/loader.highram.elf}
LOADER_PY=$(dirname "$(realpath "$0")")/calypso_loader.py
MONSOCK=/tmp/qemu-calypso-mon.sock
LOGFILE=/tmp/qemu-calypso.log
EXCEPTIONS_BIN=/tmp/calypso_exceptions.bin
FIRMWARE_BIN=/tmp/calypso_upload.bin

ADDR_EXCEPTIONS=0x0080001c
ADDR_LAYER1=0x00820000

G='\033[1;32m'  Y='\033[1;33m'  R='\033[1;31m'
C='\033[1;36m'  N='\033[0m'

log()  { echo -e "${G}[$(date +%H:%M:%S)]${N} $*"; }
info() { echo -e "${C}  →${N} $*"; }
err()  { echo -e "${R}[ERROR]${N} $*" >&2; }

echo -e "${C}"
echo "╔══════════════════════════════════════════════════╗"
echo "║         Calypso QEMU — BTS                       ║"
printf "║  Firmware : %-36s║\n" "$(basename $FIRMWARE)"
printf "║  Loader   : %-36s║\n" "$(basename $LOADER)"
echo "╚══════════════════════════════════════════════════╝"
echo -e "${N}"

[ ! -f "$FIRMWARE" ]  && { err "Firmware not found: $FIRMWARE";           exit 1; }
[ ! -f "$LOADER_PY" ] && { err "calypso_loader.py not found: $LOADER_PY"; exit 1; }
FIRMWARE=$(realpath "$FIRMWARE")
LOADER=$(realpath "$LOADER")

# ─── Cleanup ─────────────────────────────────────────────
log "Cleaning up..."
rm -f "$MONSOCK" "$LOGFILE" "$EXCEPTIONS_BIN" "$FIRMWARE_BIN" \
      /tmp/osmocom_loader /tmp/osmocom_l2
killall -q qemu-system-arm osmocon 2>/dev/null || true
sleep 0.3

# ─── Extract ELF segments ────────────────────────────────
# Sépare .text.exceptions (0x8001c, 28 bytes) du code principal (0x820000)
# pour éviter le gap de 128KB de zéros → bad CRC
log "Extracting ELF segments..."
arm-none-eabi-objcopy -O binary \
    --only-section=.text.exceptions \
    "$FIRMWARE" "$EXCEPTIONS_BIN"
[ $? -ne 0 ] || [ ! -s "$EXCEPTIONS_BIN" ] && {
    err "objcopy .text.exceptions failed"; exit 1; }
info "exceptions : $(stat -c%s $EXCEPTIONS_BIN) bytes @ $ADDR_EXCEPTIONS"

arm-none-eabi-objcopy -O binary \
    --remove-section=.text.exceptions \
    "$FIRMWARE" "$FIRMWARE_BIN"
[ $? -ne 0 ] || [ ! -s "$FIRMWARE_BIN" ] && {
    err "objcopy main failed"; exit 1; }
info "firmware   : $(stat -c%s $FIRMWARE_BIN) bytes @ $ADDR_LAYER1"

# ─── Start QEMU (paused) ─────────────────────────────────
log "Starting QEMU with loader (paused, GDB :1234)..."
$QEMU -M calypso \
    -kernel "$LOADER" \
    -serial pty \
    -monitor unix:$MONSOCK,server,nowait \
    -s -S \
    >"$LOGFILE" 2>&1 &
QEMU_PID=$!

PTS=""
for i in $(seq 1 50); do
    [ -f "$LOGFILE" ] && PTS=$(grep -o '/dev/pts/[0-9]*' "$LOGFILE" | head -1)
    [ -n "$PTS" ] && break
    sleep 0.1
done
[ -z "$PTS" ] && { err "No QEMU pty"; cat "$LOGFILE"; kill $QEMU_PID; exit 1; }
info "QEMU pty : $PTS  (PID $QEMU_PID)"

sleep 0.3
kill -0 $QEMU_PID 2>/dev/null || { err "QEMU died"; cat "$LOGFILE"; exit 1; }

log "Waiting for monitor socket..."
for i in $(seq 1 40); do
    [ -S "$MONSOCK" ] && { info "Monitor ready"; break; }
    kill -0 $QEMU_PID 2>/dev/null || { err "QEMU died"; exit 1; }
    sleep 0.2
done
[ ! -S "$MONSOCK" ] && { err "Monitor socket missing"; kill $QEMU_PID; exit 1; }
sleep 0.3

# ─── gpa2hva ─────────────────────────────────────────────
log "Resolving GPA→HVA..."
get_hva() {
    ( echo "gpa2hva $1"; sleep 0.4 ) \
        | socat - UNIX-CONNECT:$MONSOCK 2>/dev/null \
        | grep -i "host virtual" \
        | grep -o '0x[0-9a-fA-F]*' | tail -1
}
HVA_EXC=$(get_hva $ADDR_EXCEPTIONS)
HVA_L1=$(get_hva $ADDR_LAYER1)
[ -z "$HVA_EXC" ] || [ -z "$HVA_L1" ] && {
    err "gpa2hva failed (exc=${HVA_EXC:-empty} l1=${HVA_L1:-empty})"
    kill $QEMU_PID; exit 1; }
info "$ADDR_EXCEPTIONS → $HVA_EXC"
info "$ADDR_LAYER1    → $HVA_L1"

# ─── /proc/PID/mem injection ─────────────────────────────
log "Injecting firmware into QEMU RAM..."
python3 - << PYEOF
import sys
pid  = $QEMU_PID
jobs = [($HVA_EXC, "$EXCEPTIONS_BIN"), ($HVA_L1, "$FIRMWARE_BIN")]
try:
    with open(f"/proc/{pid}/mem", "r+b", buffering=0) as mem:
        for hva, path in jobs:
            data = open(path, "rb").read()
            written = 0
            while written < len(data):
                page_left = 0x1000 - ((hva + written) & 0xFFF)
                chunk = min(page_left, len(data) - written)
                mem.seek(hva + written)
                mem.write(data[written:written + chunk])
                written += chunk
            print(f"  [MEM] wrote {len(data):6d} bytes @ HVA {hex(hva)}")
    print("  [MEM] injection complete")
except PermissionError:
    print("  [ERR] Permission denied — run with --privileged")
    print("        or: echo 0 > /proc/sys/kernel/yama/ptrace_scope")
    sys.exit(1)
except Exception as e:
    print(f"  [ERR] {e}"); sys.exit(1)
PYEOF
[ $? -ne 0 ] && { kill $QEMU_PID; exit 1; }

# ─── Verify ──────────────────────────────────────────────
L1_W=$(( echo "x /1 $ADDR_LAYER1"; sleep 0.3 ) \
    | socat - UNIX-CONNECT:$MONSOCK 2>/dev/null \
    | grep -o '0x[0-9a-fA-F]*' | tail -1)
info "layer1[0] = $L1_W  (expect 0xe3a00000)"

# ─── calypso_loader.py ───────────────────────────────────
log "Starting calypso_loader.py..."
python3 "$LOADER_PY" $QEMU_PID $MONSOCK 1234 /tmp/osmocom_loader &
LOADER_PID=$!
for i in $(seq 1 30); do
    [ -S /tmp/osmocom_loader ] && { info "Loader socket ready"; break; }
    kill -0 $LOADER_PID 2>/dev/null || { err "loader daemon died"; exit 1; }
    sleep 0.2
done
[ ! -S /tmp/osmocom_loader ] && {
    err "/tmp/osmocom_loader never appeared"
    kill $QEMU_PID $LOADER_PID; exit 1; }

trap "
    echo ''
    log 'Shutting down...'
    kill $QEMU_PID $LOADER_PID 2>/dev/null
    rm -f $MONSOCK $EXCEPTIONS_BIN /tmp/osmocom_loader
    exit 0
" INT TERM

# ─── Affiche les commandes osmoload ──────────────────────
echo ""
echo -e "${Y}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
echo -e "${C}  QEMU prêt — fenêtre tmux 2 (osmoload) :${N}"
echo -e "${Y}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
echo ""
echo -e "  ${G}PTY      :${N} $PTS"
echo -e "  ${G}GDB      :${N} :1234"
echo -e "  ${G}Firmware :${N} $FIRMWARE_BIN"
echo ""
echo -e "  ${C}osmoload -m c123xor -l /tmp/osmocom_loader memload $ADDR_LAYER1 $FIRMWARE_BIN${N}"
echo -e "  ${C}osmoload -m c123xor -l /tmp/osmocom_loader jump $ADDR_LAYER1${N}"
echo -e "  ${C}osmocon -p $PTS -m c123xor${N}"
echo ""
echo -e "${R}  Ctrl+C to stop${N}"
echo -e "${Y}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
echo ""

wait $QEMU_PID 2>/dev/null
kill $LOADER_PID 2>/dev/null
rm -f "$MONSOCK" "$EXCEPTIONS_BIN" /tmp/osmocom_loader
