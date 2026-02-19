#!/bin/bash
# =============================================================
#  launch.sh — Calypso QEMU full boot pipeline
#
#  Pipeline:
#    1. Extract ELF segments (strip 128KB gap)
#    2. Start QEMU with loader (paused -s -S)
#    3. Resolve GPA→HVA via QEMU monitor (gpa2hva)
#    4. Inject firmware via /proc/PID/mem
#    5. Start calypso_loader.py (fake compal loader daemon)
#       → crée /tmp/osmocom_loader pour osmoload
#    6. Wait for osmoload commands in CLI
#    7. After jump: start osmocon → /tmp/osmocom_l2
#
#  Usage:
#    bash launch.sh                              # layer1 (default)
#    bash launch.sh ~/compal_e88/trx.highram.elf # transceiver
#
#  Then in another terminal:
#    osmoload -m c123xor -l /tmp/osmocom_loader ping
#    osmoload -m c123xor -l /tmp/osmocom_loader memload 0x820000 /tmp/calypso_upload.bin
#    osmoload -m c123xor -l /tmp/osmocom_loader jump 0x820000
# =============================================================

QEMU=qemu-system-arm
LOADER=${LOADER:-~/compal_e88/loader.highram.elf}
FIRMWARE=${1:-~/compal_e88/layer1.highram.elf}
MONSOCK=/tmp/qemu-calypso-mon.sock
LOGFILE=/tmp/qemu-calypso.log
EXCEPTIONS_BIN=/tmp/calypso_exceptions.bin
FIRMWARE_BIN=/tmp/calypso_upload.bin
LOADER_PY=$(dirname "$(realpath "$0")")/calypso_loader.py

ADDR_EXCEPTIONS=0x0080001c
ADDR_LAYER1=0x00820000

G='\033[1;32m'  Y='\033[1;33m'  R='\033[1;31m'
C='\033[1;36m'  N='\033[0m'

log()  { echo -e "${G}[$(date +%H:%M:%S)]${N} $*"; }
info() { echo -e "${C}  →${N} $*"; }
err()  { echo -e "${R}[ERROR]${N} $*" >&2; }

echo -e "${C}"
echo "╔══════════════════════════════════════════════════╗"
echo "║         Calypso QEMU — Full Boot Pipeline        ║"
printf "║  Firmware : %-36s║\n" "$(basename $FIRMWARE)"
printf "║  Loader   : %-36s║\n" "$(basename $LOADER)"
echo "╚══════════════════════════════════════════════════╝"
echo -e "${N}"

# ─── Validate inputs ─────────────────────────────────────
[ ! -f "$FIRMWARE" ]  && { err "Firmware not found: $FIRMWARE";           exit 1; }
[ ! -f "$LOADER_PY" ] && { err "calypso_loader.py not found: $LOADER_PY"; exit 1; }
FIRMWARE=$(realpath "$FIRMWARE")
LOADER=$(realpath "$LOADER")

# ─── Step 1: Cleanup ─────────────────────────────────────
log "Cleaning up..."
rm -f "$MONSOCK" "$LOGFILE" "$EXCEPTIONS_BIN" "$FIRMWARE_BIN" /tmp/osmocom_loader /tmp/osmocom_l2
killall -q qemu-system-arm osmocon 2>/dev/null
sleep 0.3

# ─── Step 2: Extract ELF segments ────────────────────────
# .text.exceptions @ 0x0080001c (28 bytes) — exception vectors
# main code        @ 0x00820000 — _start, main, ...
# We strip .text.exceptions to avoid the 128KB zero gap that
# causes bad CRC when osmoload sends the flat binary.
log "Extracting ELF segments..."

arm-none-eabi-objcopy -O binary \
    --only-section=.text.exceptions \
    "$FIRMWARE" "$EXCEPTIONS_BIN"
[ $? -ne 0 ] || [ ! -s "$EXCEPTIONS_BIN" ] && {
    err "Failed to extract .text.exceptions from $FIRMWARE"; exit 1; }
info "exceptions : $(stat -c%s $EXCEPTIONS_BIN) bytes @ $ADDR_EXCEPTIONS"

arm-none-eabi-objcopy -O binary \
    --remove-section=.text.exceptions \
    "$FIRMWARE" "$FIRMWARE_BIN"
[ $? -ne 0 ] || [ ! -s "$FIRMWARE_BIN" ] && {
    err "Failed to extract main segment from $FIRMWARE"; exit 1; }
info "firmware   : $(stat -c%s $FIRMWARE_BIN) bytes @ $ADDR_LAYER1"

# ─── Step 3: Start QEMU (paused) ─────────────────────────
log "Starting QEMU with loader (paused, GDB :1234)..."
$QEMU -M calypso \
    -kernel "$LOADER" \
    -serial pty \
    -monitor unix:$MONSOCK,server,nowait \
    -s -S \
    >"$LOGFILE" 2>&1 &
QEMU_PID=$!

# Wait for pty
PTS=""
for i in $(seq 1 50); do
    [ -f "$LOGFILE" ] && PTS=$(grep -o '/dev/pts/[0-9]*' "$LOGFILE" | head -1)
    [ -n "$PTS" ] && break
    sleep 0.1
done
[ -z "$PTS" ] && { err "No QEMU pty found"; cat "$LOGFILE"; kill $QEMU_PID; exit 1; }
info "QEMU pty : $PTS  (PID $QEMU_PID)"

sleep 0.3
kill -0 $QEMU_PID 2>/dev/null || { err "QEMU died after pty"; cat "$LOGFILE"; exit 1; }

# Wait for monitor socket
log "Waiting for monitor socket..."
for i in $(seq 1 40); do
    [ -S "$MONSOCK" ] && { info "Monitor ready (${i} iterations)"; break; }
    kill -0 $QEMU_PID 2>/dev/null || { err "QEMU died waiting for monitor"; exit 1; }
    sleep 0.2
done
[ ! -S "$MONSOCK" ] && { err "Monitor socket never appeared"; kill $QEMU_PID; exit 1; }
sleep 0.3

# ─── Step 4: Resolve GPA → HVA ───────────────────────────
log "Resolving guest→host addresses (gpa2hva)..."
get_hva() {
    local GPA=$1
    ( echo "gpa2hva $GPA"; sleep 0.4 ) \
        | socat - UNIX-CONNECT:$MONSOCK 2>/dev/null \
        | grep -i "host virtual" \
        | grep -o '0x[0-9a-fA-F]*' \
        | tail -1
}

HVA_EXCEPTIONS=$(get_hva $ADDR_EXCEPTIONS)
HVA_LAYER1=$(get_hva $ADDR_LAYER1)

[ -z "$HVA_EXCEPTIONS" ] || [ -z "$HVA_LAYER1" ] && {
    err "gpa2hva failed"
    info "exceptions HVA : ${HVA_EXCEPTIONS:-<empty>}"
    info "layer1 HVA     : ${HVA_LAYER1:-<empty>}"
    kill $QEMU_PID; exit 1; }

info "$ADDR_EXCEPTIONS → HVA $HVA_EXCEPTIONS"
info "$ADDR_LAYER1    → HVA $HVA_LAYER1"

# ─── Step 5: Inject firmware via /proc/PID/mem ───────────
log "Injecting firmware into QEMU RAM..."
python3 - << PYEOF
import sys

pid  = $QEMU_PID
jobs = [
    ($HVA_EXCEPTIONS, "$EXCEPTIONS_BIN"),
    ($HVA_LAYER1,     "$FIRMWARE_BIN"),
]

try:
    with open(f"/proc/{pid}/mem", "r+b", buffering=0) as mem:
        for hva, path in jobs:
            data = open(path, "rb").read()
            # write page by page to handle boundaries
            written = 0
            while written < len(data):
                page_left = 0x1000 - ((hva + written) & 0xFFF)
                chunk     = min(page_left, len(data) - written)
                mem.seek(hva + written)
                mem.write(data[written:written + chunk])
                written += chunk
            print(f"  [MEM] wrote {len(data):6d} bytes @ HVA {hex(hva)}")
    print("  [MEM] injection complete")
except PermissionError:
    print("  [ERR] Permission denied — try: sudo bash launch.sh")
    print("        or: echo 0 > /proc/sys/kernel/yama/ptrace_scope")
    sys.exit(1)
except Exception as e:
    print(f"  [ERR] {e}")
    sys.exit(1)
PYEOF
[ $? -ne 0 ] && { kill $QEMU_PID; exit 1; }

# ─── Step 6: Verify via QEMU monitor ─────────────────────
log "Verifying injected memory..."
EXC_WORD=$(( echo "x /1 $ADDR_EXCEPTIONS"; sleep 0.3 ) \
    | socat - UNIX-CONNECT:$MONSOCK 2>/dev/null \
    | grep -o '0x[0-9a-fA-F]*' | tail -1)
L1_WORD=$(( echo "x /1 $ADDR_LAYER1"; sleep 0.3 ) \
    | socat - UNIX-CONNECT:$MONSOCK 2>/dev/null \
    | grep -o '0x[0-9a-fA-F]*' | tail -1)
info "exceptions[0] = $EXC_WORD  (expect 0xea...)"
info "layer1[0]     = $L1_WORD  (expect 0xe3a00000)"

# ─── Step 7: Start calypso_loader.py daemon ──────────────
log "Starting calypso_loader.py..."
python3 "$LOADER_PY" $QEMU_PID $MONSOCK &
LOADER_PID=$!

for i in $(seq 1 30); do
    [ -S /tmp/osmocom_loader ] && { info "Loader socket ready"; break; }
    kill -0 $LOADER_PID 2>/dev/null || { err "calypso_loader.py died"; exit 1; }
    sleep 0.2
done
[ ! -S /tmp/osmocom_loader ] && {
    err "/tmp/osmocom_loader never appeared"; kill $QEMU_PID $LOADER_PID; exit 1; }

trap "
    echo ''
    log 'Shutting down...'
    kill $QEMU_PID $LOADER_PID 2>/dev/null
    pkill -f 'osmocon.*$PTS' 2>/dev/null
    rm -f $MONSOCK $EXCEPTIONS_BIN $FIRMWARE_BIN /tmp/osmocom_loader /tmp/osmocom_l2.2
    exit 0
" INT TERM

# ─── Step 8: CLI — wait for osmoload ─────────────────────
echo ""
echo -e "${Y}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
echo -e "${C}  QEMU ready — firmware injected — loader listening${N}"
echo -e "${Y}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
echo ""
echo -e "  ${G}QEMU PID      :${N} $QEMU_PID"
echo -e "  ${G}GDB port      :${N} :1234"
echo -e "  ${G}PTY           :${N} $PTS"
echo -e "  ${G}Loader socket :${N} /tmp/osmocom_loader"
echo -e "  ${G}Firmware bin  :${N} $FIRMWARE_BIN ($(stat -c%s $FIRMWARE_BIN) bytes)"
echo ""
echo -e "${Y}  ── osmoload commands ─────────────────────────────${N}"
echo -e "  ${C}osmoload -m c123xor -l /tmp/osmocom_loader ping${N}"
echo -e "  ${C}osmoload -m c123xor -l /tmp/osmocom_loader \\${N}"
echo -e "  ${C}    memload $ADDR_LAYER1 $FIRMWARE_BIN${N}"
echo -e "  ${C}osmoload -m c123xor -l /tmp/osmocom_loader \\${N}"
echo -e "  ${C}    jump $ADDR_LAYER1${N}"
echo ""
echo -e "${Y}  ── after jump ────────────────────────────────────${N}"
echo -e "  ${C}osmocon -p $PTS -m c123xor${N}"
echo -e "  ${C}cell_log -O /tmp/osmocom_l2${N}"
echo ""
echo -e "${Y}  ── wireshark ──────────────────────────────────────${N}"
echo -e "  ${C}wireshark -k -i lo -f 'udp port 4729'${N}"
echo ""
echo -e "${R}  Ctrl+C to stop everything${N}"
echo -e "${Y}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
echo ""

wait $QEMU_PID 2>/dev/null
kill $LOADER_PID 2>/dev/null
rm -f "$MONSOCK" "$EXCEPTIONS_BIN" "$FIRMWARE_BIN" /tmp/osmocom_loader
