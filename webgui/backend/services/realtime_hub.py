from __future__ import annotations

import asyncio
from collections import defaultdict, deque
from datetime import datetime, timezone
from typing import Any

from fastapi import WebSocket

_connections: dict[str, set[WebSocket]] = defaultdict(set)
_history: dict[str, deque[dict[str, Any]]] = defaultdict(lambda: deque(maxlen=250))
_lock = asyncio.Lock()


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


async def connect(run_id: str, websocket: WebSocket) -> None:
    await websocket.accept()
    async with _lock:
        _connections[run_id].add(websocket)
        history = list(_history[run_id])
    for message in history:
        await websocket.send_json(message)


async def disconnect(run_id: str, websocket: WebSocket) -> None:
    async with _lock:
        _connections[run_id].discard(websocket)


async def publish(run_id: str, message: dict[str, Any]) -> None:
    payload = dict(message)
    payload.setdefault("run_id", run_id)
    payload.setdefault("timestamp", utc_now())
    async with _lock:
        _history[run_id].append(payload)
        sockets = list(_connections[run_id])
    stale: list[WebSocket] = []
    for socket in sockets:
        try:
            await socket.send_json(payload)
        except Exception:
            stale.append(socket)
    if stale:
        async with _lock:
            for socket in stale:
                _connections[run_id].discard(socket)

