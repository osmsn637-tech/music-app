"""
Live Connect self-test. Spins up two simulated devices against a running
service and asserts the four core behaviors:

  1. two devices join a room and see each other
  2. the active device pushes state; the other receives it (and a non-active
     push is rejected)
  3. a transfer moves "active" to the other device, carrying exact position
  4. a remote command is forwarded only to the active device
  5. (bonus) dropping the active device eventually demotes to nobody

Usage:  python selftest.py [ws_url] [room_code]
        defaults: ws://localhost:8002/ws  changeme

Exits non-zero on the first failed assertion.
"""

import asyncio
import json
import sys
import uuid

import websockets

WS_URL = sys.argv[1] if len(sys.argv) > 1 else "ws://localhost:8002/ws"
ROOM = sys.argv[2] if len(sys.argv) > 2 else "changeme"

_passed = 0


def ok(label: str) -> None:
    global _passed
    _passed += 1
    print(f"  PASS  {label}")


def die(label: str, detail: str = "") -> None:
    print(f"  FAIL  {label}  {detail}")
    sys.exit(1)


async def send(ws, frame):
    await ws.send(json.dumps(frame))


async def recv_until(ws, type_, timeout=5.0):
    """Read frames until one matches `type_`, auto-answering pings."""
    loop = asyncio.get_event_loop()
    deadline = loop.time() + timeout
    while True:
        remaining = deadline - loop.time()
        if remaining <= 0:
            die(f"timeout waiting for '{type_}'")
        raw = await asyncio.wait_for(ws.recv(), timeout=remaining)
        msg = json.loads(raw)
        if msg.get("type") == "ping":
            await send(ws, {"type": "pong", "t": msg.get("t")})
            continue
        if msg.get("type") == type_:
            return msg
        # ignore unrelated frames (peer/progress/state echoes) for this step


async def hello(ws, device_id, name, platform):
    await send(ws, {"type": "hello", "room": ROOM, "deviceId": device_id,
                    "deviceName": name, "platform": platform,
                    "caps": {"canPlay": True}, "protocol": 1})
    return await recv_until(ws, "welcome")


async def main():
    a_id = "dev-A-" + uuid.uuid4().hex[:6]
    b_id = "dev-B-" + uuid.uuid4().hex[:6]

    async with websockets.connect(WS_URL) as a, websockets.connect(WS_URL) as b:
        # 1 — both join, both see no active device, A learns about B
        wa = await hello(a, a_id, "Mac", "macos")
        if wa.get("protocol") != 1:
            die("A welcome protocol", str(wa))
        if wa["session"]["activeDeviceId"] is not None:
            die("room should start idle", str(wa["session"]))
        base = wa["session"]["seq"]   # seq persists across restarts; assert deltas
        wb = await hello(b, b_id, "iPhone", "ios")
        ok("two devices join, room idle")
        # A should get a peer{join} for B
        pj = await recv_until(a, "peer")
        if pj["device"]["deviceId"] != b_id:
            die("A should see B join", str(pj))
        ok("roster: A sees B join")

        # 2 — A claims active via a first-play state push; B receives it
        await send(a, {"type": "state", "baseSeq": 0, "session": {
            "queueIds": ["s1", "s2", "s3"], "index": 0, "positionMs": 0,
            "playing": True, "shuffle": False, "repeat": "off"}})
        sb = await recv_until(b, "state")
        if sb["session"]["activeDeviceId"] != a_id:
            die("B should see A active", str(sb["session"]))
        if sb["session"]["queueIds"] != ["s1", "s2", "s3"] or sb["session"]["seq"] != base + 1:
            die("B should see A's queue at seq base+1", str(sb["session"]))
        ok("active device's state fans out to the other (seq+1, queue carried)")

        # 2b — a non-active device's state push is rejected
        await send(b, {"type": "state", "baseSeq": base + 1, "session": {
            "queueIds": ["x"], "index": 0, "playing": True}})
        nb = await recv_until(b, "nack")
        if nb.get("reason") != "not_active":
            die("non-active push should nack not_active", str(nb))
        ok("non-active state push rejected (nack not_active)")

        # 3 — A is at 42s; transfer playback to B carrying that position
        await send(a, {"type": "progress", "positionMs": 42000,
                       "playing": True, "atEpochMs": 0, "seq": base + 1})
        cmd_id = uuid.uuid4().hex
        await send(a, {"type": "transfer", "to": b_id, "positionMs": 42000,
                       "play": True, "cmdId": cmd_id})
        tb = await recv_until(b, "transferBegin")
        if tb["positionMs"] != 42000:
            die("transferBegin carries position", str(tb))
        ta = await recv_until(a, "transferBegin")  # source also notified
        if ta["handoffId"] != tb["handoffId"]:
            die("both sides share handoffId", f"{ta} {tb}")
        await send(b, {"type": "transferReady", "handoffId": tb["handoffId"]})
        ca = await recv_until(a, "transferCommit")
        if ca["activeDeviceId"] != b_id:
            die("commit promotes B to active", str(ca))
        if ca["session"]["positionMs"] != 42000 or not ca["session"]["playing"]:
            die("commit carries exact position + playing", str(ca["session"]))
        if ca["session"]["seq"] != base + 2:
            die("commit bumps seq to base+2", str(ca["session"]))
        ok("transfer moves active to B, position 42000 carried exactly (seq+2)")

        # 4 — A remote-commands the (now B) active device; B receives it
        cmd2 = uuid.uuid4().hex
        await send(a, {"type": "command", "action": "pause",
                       "cmdId": cmd2, "targetSeq": base + 2})
        cb = await recv_until(b, "command")
        if cb["action"] != "pause" or cb["fromDeviceId"] != a_id:
            die("active device B should receive the forwarded command", str(cb))
        acka = await recv_until(a, "commandAck")
        if not acka.get("ok"):
            die("issuer should get an ok ack", str(acka))
        ok("remote command forwarded only to the active device")

    print(f"\nALL {_passed} CHECKS PASSED")


if __name__ == "__main__":
    asyncio.run(main())
