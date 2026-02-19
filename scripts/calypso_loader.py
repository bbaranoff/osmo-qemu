#!/usr/bin/env python3
"""
calypso_loader.py — Compal loader daemon for QEMU Calypso

Protocole osmoload confirmé sur le wire:
  - msgb framing  : 2-byte BE length prefix + payload
  - cmd 0x08      : memload — [cmd][blen][crc16 BE][addr BE 4][data]
  - cmd 0x04/0x06 : jump   — [cmd][addr BE 4]
  - cmd 0x00      : ping   → pong 0x01
  - cmd 0x02      : memget
  - CRC16-IBM     : poly=0x8005 reflected, init=0x0000 (confirmé brute-force)
  - Mémoire       : /proc/PID/mem via gpa2hva QEMU monitor
  - Jump          : arm-none-eabi-gdb set $pc + continue

Usage:
    python3 calypso_loader.py <QEMU_PID> <MONSOCK> [GDB_PORT] [LOADER_SOCK]

Defaults:
    GDB_PORT    = 1234
    LOADER_SOCK = /tmp/osmocom_loader
"""

import sys, os, socket, struct, threading, time, subprocess

if len(sys.argv) < 3:
    print(f"Usage: {sys.argv[0]} <QEMU_PID> <MONSOCK> [GDB_PORT] [LOADER_SOCK]")
    sys.exit(1)

QEMU_PID    = int(sys.argv[1])
MONSOCK     = sys.argv[2]
GDB_PORT    = int(sys.argv[3]) if len(sys.argv) > 3 else 1234
LOADER_SOCK = sys.argv[4]      if len(sys.argv) > 4 else "/tmp/osmocom_loader"

# ── CRC16-IBM : poly=0x8005 reflected, init=0x0000 ───────
def crc16(data: bytes) -> int:
    crc = 0x0000
    for b in data:
        crc ^= b
        for _ in range(8):
            crc = ((crc >> 1) ^ 0xA001) if crc & 1 else (crc >> 1)
    return crc

# ── QEMU memory access ────────────────────────────────────
class QEMUMem:
    def __init__(self, pid: int, monsock: str):
        self.pid     = pid
        self.monsock = monsock
        self._hva    = {}   # gpa_page → hva_page

    def _gpa2hva(self, gpa: int) -> int:
        page = gpa & ~0xFFF
        if page not in self._hva:
            s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            s.connect(self.monsock)
            s.recv(4096)   # banner
            s.send(f"gpa2hva {hex(page)}\n".encode())
            time.sleep(0.3)
            resp = s.recv(4096).decode(errors="replace")
            s.close()
            for line in resp.splitlines():
                if "host virtual address" in line.lower() and " is " in line.lower():
                    self._hva[page] = int(line.split(" is ")[-1].strip(), 16)
                    break
            else:
                raise RuntimeError(f"gpa2hva failed for {hex(gpa)}")
        return self._hva[page] + (gpa & 0xFFF)

    def write(self, gpa: int, data: bytes):
        written = 0
        with open(f"/proc/{self.pid}/mem", "r+b", buffering=0) as mem:
            while written < len(data):
                hva       = self._gpa2hva(gpa + written)
                page_left = 0x1000 - ((gpa + written) & 0xFFF)
                chunk     = min(page_left, len(data) - written)
                mem.seek(hva)
                mem.write(data[written:written + chunk])
                written  += chunk
        print(f"  [MEM] wrote {len(data):6d} bytes @ gpa={hex(gpa)}")

    def read(self, gpa: int, length: int) -> bytes:
        hva = self._gpa2hva(gpa)
        with open(f"/proc/{self.pid}/mem", "rb", buffering=0) as mem:
            mem.seek(hva)
            return mem.read(length)

# ── GDB jump ─────────────────────────────────────────────
def gdb_jump(addr: int):
    print(f"  [GDB] jump to {hex(addr)} via :{GDB_PORT}")
    subprocess.Popen([
        "arm-none-eabi-gdb", "-batch",
        "-ex", f"target remote :{GDB_PORT}",
        "-ex", f"set $pc = {hex(addr)}",
        "-ex", "continue",
    ], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    print(f"  [GDB] Confirmed jump to {hex(addr)}.")

# ── msgb framing ─────────────────────────────────────────
def recv_exact(sock: socket.socket, n: int) -> bytes:
    buf = b""
    while len(buf) < n:
        chunk = sock.recv(n - len(buf))
        if not chunk:
            raise ConnectionError("peer disconnected")
        buf += chunk
    return buf

def recv_msg(sock: socket.socket) -> bytes:
    length = struct.unpack(">H", recv_exact(sock, 2))[0]
    if length == 0 or length > 65535:
        raise ValueError(f"bad msgb length: {length}")
    return recv_exact(sock, length)

def send_msg(sock: socket.socket, payload: bytes):
    sock.sendall(struct.pack(">H", len(payload)) + payload)

# ── Client handler ────────────────────────────────────────
def handle_client(conn: socket.socket, qmem: QEMUMem):
    print("  [LOADER] client connected")
    try:
        while True:
            payload = recv_msg(conn)
            cmd     = payload[0]

            # ── PING ──────────────────────────────────────
            if cmd == 0x01:
                print("  [LOADER] PING → PONG")
                send_msg(conn, bytes([0x01, 0x00]))

            # ── MEMLOAD ───────────────────────────────────
            elif cmd == 0x08:
                if len(payload) < 8:
                    print(f"  [LOADER] memload too short ({len(payload)})")
                    continue
                block_len = payload[1]
                rx_crc    = struct.unpack_from(">H", payload, 2)[0]
                addr      = struct.unpack_from(">I", payload, 4)[0]
                data      = payload[8:8 + block_len]
                calc_crc  = crc16(data)

                print(f"  [LOADER] memload addr={hex(addr)} len={block_len} "
                      f"crc={hex(rx_crc)}", end="")

                if calc_crc != rx_crc:
                    print(f" MISMATCH calc={hex(calc_crc)} → NACK")
                    send_msg(conn, bytes([0x08, block_len])
                             + struct.pack(">HI", 0x0000, addr))
                    continue

                qmem.write(addr, data)
                send_msg(conn, bytes([0x08, block_len])
                         + struct.pack(">HI", calc_crc, addr))
                print(" → ACK")

            # ── JUMP ──────────────────────────────────────
            elif cmd == 0x04:
                addr = struct.unpack_from(">I", payload, 1)[0] \
                       if len(payload) >= 5 else 0x820000
                print(f"  [LOADER] JUMP → {hex(addr)}")
                send_msg(conn, bytes([cmd]) + struct.pack(">I", addr))
                gdb_jump(addr)
                break

            # ── MEMGET ────────────────────────────────────
            elif cmd == 0x02:
                addr   = struct.unpack_from(">I", payload, 1)[0]
                length = struct.unpack_from(">H", payload, 5)[0] \
                         if len(payload) >= 7 else 4
                data   = qmem.read(addr, length)
                send_msg(conn, bytes([0x02])
                         + struct.pack(">IH", addr, length) + data)
                print(f"  [LOADER] MEMGET {hex(addr)} len={length}")

            else:
                print(f"  [LOADER] unknown cmd=0x{cmd:02x} "
                      f"payload={payload.hex()}")

    except (ConnectionError, ValueError) as e:
        print(f"  [LOADER] {e}")
    except Exception as e:
        import traceback; traceback.print_exc()
    finally:
        conn.close()
        print("  [LOADER] client disconnected")

# ── Main ─────────────────────────────────────────────────
def main():
    qmem = QEMUMem(QEMU_PID, MONSOCK)

    # sanity check
    try:
        test = qmem.read(0x820000, 4)
        print(f"[LOADER] Memory OK  : {test.hex()} @ 0x820000")
    except Exception as e:
        print(f"[LOADER] Memory FAIL: {e}")
        sys.exit(1)

    if os.path.exists(LOADER_SOCK):
        os.unlink(LOADER_SOCK)

    srv = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    srv.bind(LOADER_SOCK)
    srv.listen(5)

    print(f"[LOADER] Listening on {LOADER_SOCK}")
    print(f"[LOADER] GDB port   : {GDB_PORT}")
    print()

    try:
        while True:
            conn, _ = srv.accept()
            threading.Thread(
                target=handle_client,
                args=(conn, qmem),
                daemon=True
            ).start()
    except KeyboardInterrupt:
        print("\n[LOADER] exit")
    finally:
        srv.close()
        if os.path.exists(LOADER_SOCK):
            os.unlink(LOADER_SOCK)

if __name__ == "__main__":
    main()
