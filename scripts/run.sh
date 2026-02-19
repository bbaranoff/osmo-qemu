#!/bin/bash

SESSION="gsm"
NITB_CONF="/etc/osmocom"
OSMOCON_MODE="c123xor"
ADDR_LAYER1="0x00820000"
FIRMWARE_BIN="/tmp/calypso_upload.bin"

tmux has-session -t "$SESSION" 2>/dev/null && tmux kill-session -t "$SESSION"
killall -q osmo-nitb osmo-bts-trx qemu-system-arm osmocon transceiver socat || true
rm -f /tmp/osmocom_l2 /tmp/osmocom_l2.2 /tmp/osmocom_loader

tmux new-session -d -s "$SESSION" -n nitb -x 220 -y 50

# ───── NITB ─────────────────────────────
tmux send-keys -t "$SESSION:nitb" \
"cd $NITB_CONF && osmo-nitb --yes-i-really-want-to-run-prehistoric-software --debug=DRLL:DCC:DMM:DRR:DRSL:DNM | tee /tmp/nitb.log" Enter

sleep 3

# ───── CALYPSO ──────────────────────────
tmux new-window -t "$SESSION" -n calypso
tmux send-keys -t "$SESSION:calypso" \
"bash /root/launch_calypso.sh | tee /tmp/calypso.log" Enter

# ───── LOADER ───────────────────────────
tmux new-window -t "$SESSION" -n loader
tmux send-keys -t "$SESSION:loader" \
bash -c "
echo -n 'Wait PTY...' >&2
for i in {1..60}; do
  PTY=\$(grep -o '/dev/pts/[0-9]*' /tmp/calypso.log | tail -1)
  [ -n \"\$PTY\" ] && break
  sleep 1
done
[ -z \"\$PTY\" ] && exit 1
echo ' ok' >&2

echo -n 'Wait loader...' >&2
for i in {1..60}; do
  [ -S /tmp/osmocom_loader ] && break
  sleep 1
done
[ ! -S /tmp/osmocom_loader ] && exit 1
echo ' ok' >&2

osmoload -l /tmp/osmocom_loader memload 0x00820000 /tmp/calypso_upload.bin
osmoload -l /tmp/osmocom_loader jump 0x00820000

exec osmocon -p \"\$PTY\" -m c123xor
" >/dev/null 2>&1

# ───── TRX ──────────────────────────────
tmux new-window -t "$SESSION" -n trx
tmux send-keys -t "$SESSION:trx" \
bash -c "
echo -n 'Wait /tmp/osmocom_l2...' >&2
for i in {1..120}; do
  [ -S /tmp/osmocom_l2 ] && break
  sleep 1
done
[ ! -S /tmp/osmocom_l2 ] && exit 1
echo ' ok' >&2

exec transceiver -a 1 -r 99
" >/dev/null 2>&1 | tee /tmp/trx.log

# ───── BTS ──────────────────────────────
tmux new-window -t "$SESSION" -n bts
tmux send-keys -t "$SESSION:bts" \
"cd $NITB_CONF && osmo-bts-trx -i 127.0.0.1 | tee /tmp/bts.log" Enter

