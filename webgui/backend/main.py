from __future__ import annotations

import asyncio
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from config import settings
from models.database import create_tables, test_db_connection
from routers import analytics, complexity, config as cfg_router, functions, profile, realtime, results, runs
from services.file_watcher import start_file_watcher


@asynccontextmanager
async def lifespan(app: FastAPI):
    db_ok = test_db_connection()
    app.state.db_available = db_ok
    if db_ok:
        create_tables()
        print("MySQL connected and WebGUI tables are ready")
    else:
        print("MySQL unavailable - WebGUI running in CSV-only mode")

    watcher_task = asyncio.create_task(start_file_watcher())
    yield
    watcher_task.cancel()
    try:
        await watcher_task
    except asyncio.CancelledError:
        pass


app = FastAPI(
    title="6GR Simulator v2 WebGUI API",
    version="2.0.0",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.frontend_origins,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/api/v1/health")
async def health() -> dict:
    return {
        "ok": True,
        "db_available": bool(getattr(app.state, "db_available", False)),
        "mode": "mysql+csv" if getattr(app.state, "db_available", False) else "csv",
        "results_root": str(settings.results_root_path),
    }


app.include_router(runs.router, prefix="/api/v1")
app.include_router(cfg_router.router, prefix="/api/v1")
app.include_router(results.router, prefix="/api/v1")
app.include_router(analytics.router, prefix="/api/v1")
app.include_router(profile.router, prefix="/api/v1")
app.include_router(complexity.router, prefix="/api/v1")
app.include_router(functions.router, prefix="/api/v1")
app.include_router(realtime.router)

