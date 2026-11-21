#!/usr/bin/env python3
"""Drives a running Touch Jockey over its WebSocket, the way a phone does, and prints what it sees.

Usage: scripts/drive.py [host] — runs a scripted handoff: start A, cue B on the next bar,
sweep highs and mids, flick the bass, then push everything over and wait for the swap.
Standard library only (a tiny WebSocket client).
"""
import base64, json, os, socket, struct, sys, time

HOST = sys.argv[1] if len(sys.argv) > 1 else "127.0.0.1"
PORT = 8081

def connect():
    s = socket.create_connection((HOST, PORT))
    key = base64.b64encode(os.urandom(16)).decode()
    s.sendall((f"GET / HTTP/1.1\r\nHost: {HOST}:{PORT}\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
               f"Sec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n\r\n").encode())
    resp = b""
    while b"\r\n\r\n" not in resp:
        resp += s.recv(1024)
    assert b" 101 " in resp.split(b"\r\n")[0], resp
    s.setblocking(False)
    return s, resp.split(b"\r\n\r\n", 1)[1]

def send(s, obj):
    data = json.dumps(obj).encode()
    mask = os.urandom(4)
    head = bytes([0x81])
    head += bytes([0x80 | len(data)]) if len(data) < 126 else bytes([0x80 | 126]) + struct.pack(">H", len(data))
    s.sendall(head + mask + bytes(b ^ mask[i % 4] for i, b in enumerate(data)))

buf = b""
def latest_state(s, wait=0.15):
    """Drains incoming frames for `wait` seconds and returns the newest state message."""
    global buf
    end, last = time.time() + wait, None
    while time.time() < end:
        try:
            chunk = s.recv(65536)
            if chunk: buf += chunk
        except BlockingIOError:
            time.sleep(0.01)
        while len(buf) >= 2:
            n = buf[1] & 0x7F; off = 2
            if n == 126: n = struct.unpack(">H", buf[2:4])[0]; off = 4
            elif n == 127: n = struct.unpack(">Q", buf[2:10])[0]; off = 10
            if len(buf) < off + n: break
            payload, buf = buf[off:off + n], buf[off + n:]
            try:
                m = json.loads(payload)
                if m.get("t") == "state": last = m
            except ValueError:
                pass
    return last

def show(label, m):
    lanes = " ".join(f"{k}={v:.2f}" for k, v in sorted(m["lanes"].items()))
    decks = " | ".join(f"{d['name']}:{'▶' if d['playing'] else '■'} {d['bpm']:.2f}" for d in m["decks"])
    beat = m.get("beat")
    print(f"{label:28} out={m['out']} beat={beat if beat is None else round(beat, 2)} startsIn={m.get('startsIn') and round(m['startsIn'], 2)}  {lanes}  [{decks}]")

s, buf = connect()
m = latest_state(s, 0.5); show("connected", m)
send(s, {"t": "play"}); time.sleep(1.0); m = latest_state(s); show("after play A", m)
send(s, {"t": "cue", "every": 4}); m = latest_state(s, 0.3); show("cued B next bar", m)
time.sleep(2.2); m = latest_state(s); show("B should be playing", m)
for band in ("high", "mid"):
    send(s, {"t": "grab", "band": band})
    for i in range(1, 21):
        send(s, {"t": "lane", "band": band, "v": i / 20}); time.sleep(0.02)
    send(s, {"t": "release", "band": band})
m = latest_state(s); show("highs+mids over", m)
send(s, {"t": "flick", "band": "low", "to": 1}); m = latest_state(s, 0.1); show("flick sent (not landed yet)", m)
time.sleep(2.2); m = latest_state(s); show("flick landed?", m)
time.sleep(2.5); m = latest_state(s); show("handoff finished?", m)
send(s, {"t": "stable"}); m = latest_state(s); show("stable", m)
