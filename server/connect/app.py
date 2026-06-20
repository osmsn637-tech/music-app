"""
Live Connect — real-time cross-device playback handoff for the music app.

A tiny FastAPI WebSocket service. Devices in the same room share one
authoritative playback *session*; exactly one device is *active* (owns audio
output). Any device can remote-control the active one or transfer playback to
another device mid-song (Spotify-Connect style), carrying the exact position.

Wire protocol is frozen as `protocol: 1`. See README "Live Connect" + the
build spec. Single shared ROOM_CODE (env) gates the room — same
unauthenticated-LAN posture as the music/piper servers; put it behind TLS
(wss://) for any internet deployment.
"""

import asyncio
import contextlib
import json
import os
import time
import uuid
from contextlib import asynccontextmanager
from dataclasses import dataclass
from typing import Optional

from fastapi import FastAPI, WebSocket, WebSocketDisconnect

# ── Config (env-driven, like the rest of server/) ────────────────────────────
ROOM_CODE = os.environ.get("ROOM_CODE", "changeme")
STATE_PATH = os.environ.get("STATE_PATH", "/state/state.json")
PING_INTERVAL = float(os.environ.get("PING_INTERVAL", "15"))      # idle ping
EVICT_AFTER = float(os.environ.get("EVICT_AFTER", "45"))          # dead socket
RECONNECT_GRACE = float(os.environ.get("RECONNECT_GRACE", "20"))  # active resume
TRANSFER_TIMEOUT = float(os.environ.get("TRANSFER_READY_TIMEOUT", "5"))
HELLO_TIMEOUT = float(os.environ.get("HELLO_TIMEOUT", "10"))
SAVE_DEBOUNCE = 5.0
PROTOCOL = 1


def now_ms() -> int:
    return int(time.time() * 1000)


def new_session(room_id: str) -> dict:
    return {
        "roomId": room_id,
        "seq": 0,
        "activeDeviceId": None,
        "queueIds": [],
        "index": -1,
        "positionMs": 0,
        "positionAtEpochMs": now_ms(),
        "playing": False,
        "shuffle": False,
        "repeat": "off",
        "updatedBy": "",
        "updatedAt": now_ms(),
    }


@dataclass
class Device:
    device_id: str
    name: str
    platform: str
    can_play: bool
    ws: WebSocket
    last_seen: float
    online: bool = True


@dataclass
class Handoff:
    handoff_id: str
    src: str
    dst: str
    issuer: str
    cmd_id: Optional[str]
    position_ms: int
    play: bool
    started: float
    base_seq: int


@dataclass
class Room:
    code: str
    session: dict
    devices: dict           # device_id -> Device
    handoff: Optional[Handoff] = None
    demote_deadline: Optional[float] = None


rooms: dict[str, Room] = {}
_last_save = 0.0


def get_room(code: str) -> Room:
    r = rooms.get(code)
    if r is None:
        r = Room(code=code, session=new_session(code), devices={})
        rooms[code] = r
    return r


def peer_view(d: Device) -> dict:
    return {
        "deviceId": d.device_id,
        "deviceName": d.name,
        "platform": d.platform,
        "canPlay": d.can_play,
        "online": d.online,
    }


async def send(dev: Device, frame: dict) -> bool:
    try:
        await dev.ws.send_text(json.dumps(frame))
        return True
    except Exception:
        return False


async def broadcast(room: Room, frame: dict, exclude: Optional[str] = None) -> None:
    # Serialize once so every recipient of a single broadcast gets a
    # byte-identical snapshot even if another coroutine mutates room.session
    # between two awaits in this fan-out loop.
    payload = json.dumps(frame)
    for d in list(room.devices.values()):
        if exclude is not None and d.device_id == exclude:
            continue
        try:
            await d.ws.send_text(payload)
        except Exception:
            pass


async def cancel_handoff_if_party(room: Room, device_id: str) -> None:
    """Release an in-flight handoff when one of its participants leaves, so a
    dropped source/target doesn't wedge transfers until the timeout fires."""
    h = room.handoff
    if h is not None and device_id in (h.src, h.dst):
        room.handoff = None
        issuer = room.devices.get(h.issuer)
        if issuer is not None:
            await send(issuer, {"type": "commandAck", "cmdId": h.cmd_id,
                                "ok": False, "error": "target_offline"})


# ── Persistence (debounced JSON snapshot, like content/manifest.json) ─────────
def save_state() -> None:
    try:
        os.makedirs(os.path.dirname(STATE_PATH) or ".", exist_ok=True)
        data = {code: r.session for code, r in rooms.items()}
        tmp = STATE_PATH + ".tmp"
        with open(tmp, "w") as f:
            json.dump(data, f)
        os.replace(tmp, STATE_PATH)
    except Exception:
        pass


def maybe_save() -> None:
    global _last_save
    now = time.time()
    if now - _last_save >= SAVE_DEBOUNCE:
        _last_save = now
        save_state()


def load_state() -> None:
    try:
        with open(STATE_PATH) as f:
            data = json.load(f)
        for code, sess in data.items():
            # Roster is never persisted — it rebuilds from reconnect/hello.
            # The active device is gone on boot, so clear it; a still-alive
            # device just re-claims active on its next state push. Leaving a
            # stale activeDeviceId would lock out all new playback.
            sess["activeDeviceId"] = None
            sess["playing"] = False
            rooms[code] = Room(code=code, session=sess, devices={})
    except Exception:
        pass


# ── Frame handlers ───────────────────────────────────────────────────────────
async def handle_state(room: Room, dev: Device, msg: dict) -> None:
    s = room.session
    incoming = msg.get("session") or {}
    base = msg.get("baseSeq")
    active = s["activeDeviceId"]
    first_play = active is None and bool(incoming.get("playing"))

    if active == dev.device_id:
        if base is not None and base != s["seq"]:
            await send(dev, {"type": "nack", "of": "state",
                             "reason": "stale_seq", "session": s})
            return
    elif not first_play:
        await send(dev, {"type": "nack", "of": "state",
                         "reason": "not_active", "session": s})
        return

    repeat = incoming.get("repeat", "off")
    ns = {
        "roomId": s["roomId"],
        "seq": s["seq"] + 1,
        "activeDeviceId": dev.device_id,
        "queueIds": list(incoming.get("queueIds", [])),
        "index": int(incoming.get("index", -1)),
        "positionMs": int(incoming.get("positionMs", 0)),
        "positionAtEpochMs": now_ms(),
        "playing": bool(incoming.get("playing", False)),
        "shuffle": bool(incoming.get("shuffle", False)),
        "repeat": repeat if repeat in ("off", "all", "one") else "off",
        "updatedBy": dev.device_id,
        "updatedAt": now_ms(),
    }
    room.session = ns
    room.demote_deadline = None
    await broadcast(room, {"type": "state", "session": ns})
    maybe_save()


async def handle_progress(room: Room, dev: Device, msg: dict) -> None:
    s = room.session
    if s["activeDeviceId"] != dev.device_id:
        return
    if msg.get("seq") != s["seq"]:          # stale (pre-state-change) frame
        return
    s["positionMs"] = int(msg.get("positionMs", s["positionMs"]))
    s["positionAtEpochMs"] = now_ms()
    s["playing"] = bool(msg.get("playing", s["playing"]))
    await broadcast(room, {
        "type": "progress",
        "positionMs": s["positionMs"],
        "playing": s["playing"],
        "atEpochMs": s["positionAtEpochMs"],
        "activeDeviceId": s["activeDeviceId"],
        "seq": s["seq"],
    }, exclude=dev.device_id)


async def handle_command(room: Room, dev: Device, msg: dict) -> None:
    s = room.session
    cmd_id = msg.get("cmdId")
    active = s["activeDeviceId"]
    if active is None:
        await send(dev, {"type": "commandAck", "cmdId": cmd_id,
                         "ok": False, "error": "no_active_device"})
        return
    target = room.devices.get(active)
    if target is None:
        await send(dev, {"type": "commandAck", "cmdId": cmd_id,
                         "ok": False, "error": "target_offline"})
        return
    await send(target, {
        "type": "command",
        "action": msg.get("action"),
        "args": msg.get("args"),
        "cmdId": cmd_id,
        "fromDeviceId": dev.device_id,
        "targetSeq": msg.get("targetSeq"),
    })
    await send(dev, {"type": "commandAck", "cmdId": cmd_id, "ok": True})


async def handle_transfer(room: Room, dev: Device, msg: dict) -> None:
    s = room.session
    cmd_id = msg.get("cmdId")
    to = msg.get("to")
    target = room.devices.get(to)
    if target is None:
        await send(dev, {"type": "commandAck", "cmdId": cmd_id,
                         "ok": False, "error": "target_offline"})
        return
    if not target.can_play:
        await send(dev, {"type": "commandAck", "cmdId": cmd_id,
                         "ok": False, "error": "target_cannot_play"})
        return
    if to == s["activeDeviceId"]:           # already active — no-op success
        await send(dev, {"type": "commandAck", "cmdId": cmd_id, "ok": True})
        return
    if room.handoff is not None:
        await send(dev, {"type": "commandAck", "cmdId": cmd_id,
                         "ok": False, "error": "rejected_by_active"})
        return

    position = int(msg.get("positionMs", s["positionMs"]))
    play = bool(msg.get("play", True))
    hid = uuid.uuid4().hex
    src_id = s["activeDeviceId"] or dev.device_id
    room.handoff = Handoff(hid, src_id, to, dev.device_id, cmd_id,
                           position, play, time.time(), s["seq"])

    # dict(s): freeze the session snapshot so a concurrent progress frame
    # mutating room.session can't make the two transferBegin recipients
    # disagree under the same handoffId.
    begin = {"type": "transferBegin", "from": src_id, "to": to,
             "positionMs": position, "play": play, "session": dict(s),
             "handoffId": hid}
    if not await send(target, begin):       # target socket already dead
        room.handoff = None
        await send(dev, {"type": "commandAck", "cmdId": cmd_id,
                         "ok": False, "error": "target_offline"})
        return
    src = room.devices.get(src_id)
    if src is not None and src.device_id != to:
        await send(src, begin)
    asyncio.create_task(_transfer_timeout(room, hid))


async def _transfer_timeout(room: Room, hid: str) -> None:
    await asyncio.sleep(TRANSFER_TIMEOUT)
    h = room.handoff
    if h is not None and h.handoff_id == hid:
        room.handoff = None
        issuer = room.devices.get(h.issuer)
        if issuer is not None:
            await send(issuer, {"type": "commandAck", "cmdId": h.cmd_id,
                                "ok": False, "error": "target_offline"})


async def handle_transfer_ready(room: Room, dev: Device, msg: dict) -> None:
    h = room.handoff
    if h is None or msg.get("handoffId") != h.handoff_id or dev.device_id != h.dst:
        return
    s = room.session
    if s["seq"] != h.base_seq:               # session moved under the handoff
        room.handoff = None                  # (e.g. a new first-play) — abort
        issuer = room.devices.get(h.issuer)  # rather than clobber it
        if issuer is not None:
            await send(issuer, {"type": "commandAck", "cmdId": h.cmd_id,
                                "ok": False, "error": "rejected_by_active"})
        return
    ns = dict(s)
    ns["seq"] = s["seq"] + 1
    ns["activeDeviceId"] = h.dst
    ns["positionMs"] = h.position_ms
    ns["positionAtEpochMs"] = now_ms()
    ns["playing"] = h.play
    ns["updatedBy"] = h.dst
    ns["updatedAt"] = now_ms()
    room.session = ns
    room.handoff = None
    room.demote_deadline = None
    await broadcast(room, {"type": "transferCommit", "handoffId": h.handoff_id,
                           "activeDeviceId": h.dst, "session": ns})
    issuer = room.devices.get(h.issuer)
    if issuer is not None:
        await send(issuer, {"type": "commandAck", "cmdId": h.cmd_id, "ok": True})
    maybe_save()


async def dispatch(room: Room, dev: Device, msg: dict) -> None:
    t = msg.get("type")
    if t == "ping":
        await send(dev, {"type": "pong", "t": msg.get("t")})
    elif t == "pong":
        pass  # liveness already refreshed by the read loop
    elif t == "state":
        await handle_state(room, dev, msg)
    elif t == "progress":
        await handle_progress(room, dev, msg)
    elif t == "command":
        await handle_command(room, dev, msg)
    elif t == "transfer":
        await handle_transfer(room, dev, msg)
    elif t == "transferReady":
        await handle_transfer_ready(room, dev, msg)
    elif t == "bye":
        with contextlib.suppress(Exception):
            await dev.ws.close()


# ── Liveness sweeper: ping idle sockets, evict dead ones, demote lost active ──
async def sweeper() -> None:
    while True:
        await asyncio.sleep(5)
        now = time.time()
        for room in list(rooms.values()):
            for d in list(room.devices.values()):
                idle = now - d.last_seen
                if idle > EVICT_AFTER:
                    room.devices.pop(d.device_id, None)   # pop first so the
                    with contextlib.suppress(Exception):  # device's own finally
                        await d.ws.close(code=4000)        # short-circuits (no
                    await broadcast(room, {"type": "peer", "event": "leave",
                                           "device": peer_view(d)})  # dup leave)
                    await cancel_handoff_if_party(room, d.device_id)
                    if (room.session["activeDeviceId"] == d.device_id
                            and room.demote_deadline is None):
                        room.demote_deadline = now + RECONNECT_GRACE
                elif idle > PING_INTERVAL:
                    await send(d, {"type": "ping", "t": int(now * 1000)})

            dl = room.demote_deadline
            if dl is not None and now > dl:
                room.demote_deadline = None
                active = room.session["activeDeviceId"]
                if active not in room.devices:        # still gone -> demote
                    s = room.session
                    ns = dict(s)
                    ns["seq"] = s["seq"] + 1
                    ns["activeDeviceId"] = None
                    ns["playing"] = False
                    ns["positionAtEpochMs"] = now_ms()
                    ns["updatedBy"] = "server"
                    ns["updatedAt"] = now_ms()
                    room.session = ns
                    await broadcast(room, {"type": "state", "session": ns})
                    maybe_save()


@asynccontextmanager
async def lifespan(_: FastAPI):
    load_state()
    task = asyncio.create_task(sweeper())
    try:
        yield
    finally:
        task.cancel()
        with contextlib.suppress(Exception):
            await task
        save_state()


app = FastAPI(lifespan=lifespan)


@app.get("/health")
def health():
    room = rooms.get(ROOM_CODE)
    return {
        "ok": True,
        "room": bool(ROOM_CODE),
        "devices": len(room.devices) if room else 0,
        "active": room.session["activeDeviceId"] if room else None,
    }


@app.websocket("/ws")
async def ws_endpoint(ws: WebSocket):
    await ws.accept()
    device_id: Optional[str] = None
    room: Optional[Room] = None
    try:
        try:
            raw_first = await asyncio.wait_for(
                ws.receive_text(), timeout=HELLO_TIMEOUT)
            first = json.loads(raw_first)
        except Exception:
            # no hello (or malformed) within the window — don't pin the slot.
            with contextlib.suppress(Exception):
                await ws.close(code=4008)
            return
        if first.get("type") != "hello" or first.get("protocol") != PROTOCOL:
            await send_raw(ws, {"type": "error", "code": "bad_protocol",
                                "message": "expected hello protocol:1"})
            await ws.close(code=4003)
            return
        if first.get("room") != ROOM_CODE:
            await send_raw(ws, {"type": "error", "code": "unknown_room",
                                "message": "bad room code"})
            await ws.close(code=4003)
            return
        device_id = first.get("deviceId")
        if not device_id:
            await send_raw(ws, {"type": "error", "code": "malformed",
                                "message": "missing deviceId"})
            await ws.close(code=4003)
            return

        room = get_room(ROOM_CODE)
        prev = room.devices.get(device_id)
        if prev is not None:                       # supersede stale connection
            with contextlib.suppress(Exception):
                await prev.ws.close(code=4001)

        caps = first.get("caps") or {}
        dev = Device(
            device_id=device_id,
            name=first.get("deviceName", "Device"),
            platform=first.get("platform", "unknown"),
            can_play=bool(caps.get("canPlay", True)),
            ws=ws,
            last_seen=time.time(),
        )
        room.devices[device_id] = dev

        # Active device reconnecting within grace -> cancel pending demote.
        if room.session["activeDeviceId"] == device_id and first.get("resume"):
            room.demote_deadline = None

        await send(dev, {
            "type": "welcome",
            "session": room.session,
            "you": {"deviceId": device_id,
                    "isActive": room.session["activeDeviceId"] == device_id},
            "peers": [peer_view(d) for d in room.devices.values()
                      if d.device_id != device_id],
            "serverEpochMs": now_ms(),
            "protocol": PROTOCOL,
        })
        await broadcast(room, {"type": "peer", "event": "join",
                               "device": peer_view(dev)}, exclude=device_id)

        while True:
            raw = await ws.receive_text()
            dev.last_seen = time.time()
            try:
                msg = json.loads(raw)
            except Exception:
                continue
            try:
                await dispatch(room, dev, msg)
            except (TypeError, ValueError):
                continue          # malformed field — drop frame, keep socket

    except WebSocketDisconnect:
        pass
    except Exception:
        pass
    finally:
        if room is not None and device_id is not None:
            d = room.devices.get(device_id)
            if d is not None and d.ws is ws:        # don't evict a newer socket
                room.devices.pop(device_id, None)
                await broadcast(room, {"type": "peer", "event": "leave",
                                       "device": peer_view(d)})
                await cancel_handoff_if_party(room, device_id)
                if room.session["activeDeviceId"] == device_id:
                    room.demote_deadline = time.time() + RECONNECT_GRACE


async def send_raw(ws: WebSocket, frame: dict) -> None:
    with contextlib.suppress(Exception):
        await ws.send_text(json.dumps(frame))
