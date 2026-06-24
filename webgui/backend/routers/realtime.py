from __future__ import annotations

from fastapi import APIRouter, WebSocket, WebSocketDisconnect

from services.matlab_runner import stop_run
from services.realtime_hub import connect, disconnect

router = APIRouter(tags=["realtime"])


@router.websocket("/ws/{run_id}")
async def websocket_endpoint(websocket: WebSocket, run_id: str):
    await connect(run_id, websocket)
    try:
        while True:
            data = await websocket.receive_json()
            action = data.get("action")
            if action == "stop":
                stopped = stop_run(run_id)
                await websocket.send_json({"type": "stop_ack", "run_id": run_id, "stopped": stopped})
            elif action == "ping":
                await websocket.send_json({"type": "pong", "run_id": run_id})
    except WebSocketDisconnect:
        pass
    finally:
        await disconnect(run_id, websocket)

