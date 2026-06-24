from __future__ import annotations

import asyncio
from pathlib import Path

from config import settings
from services.csv_store import read_last_n_rows, repo_relative
from services.realtime_hub import publish

try:
    from watchdog.events import FileSystemEventHandler
    from watchdog.observers import Observer
except Exception:  # pragma: no cover - optional at import time
    FileSystemEventHandler = object  # type: ignore
    Observer = None  # type: ignore

_aliases: dict[str, str] = {}


def register_run_watcher(run_tag: str, run_id: str | None = None) -> None:
    _aliases[str(run_tag)] = str(run_id or run_tag)


def _run_id_from_csv_path(path: Path) -> str | None:
    parts = list(path.parts)
    if "lls" in parts:
        idx = parts.index("lls")
        if len(parts) > idx + 2:
            run_tag = parts[idx + 2]
            return _aliases.get(run_tag, run_tag)
    for alias, run_id in _aliases.items():
        if alias in parts:
            return run_id
    return None


if Observer is not None:
    class ResultsHandler(FileSystemEventHandler):  # type: ignore[misc]
        def __init__(self, loop: asyncio.AbstractEventLoop):
            self.loop = loop

        def on_modified(self, event) -> None:  # noqa: ANN001
            if getattr(event, "is_directory", False):
                return
            path = Path(str(getattr(event, "src_path", "")))
            if path.suffix.lower() != ".csv":
                return
            asyncio.run_coroutine_threadsafe(self._handle_csv_change(path), self.loop)

        async def _handle_csv_change(self, csv_path: Path) -> None:
            run_id = _run_id_from_csv_path(csv_path)
            if not run_id:
                return
            try:
                rows = read_last_n_rows(csv_path, 5)
            except Exception:
                return
            await publish(
                run_id,
                {
                    "type": "csv_update",
                    "file": csv_path.name,
                    "artifact": repo_relative(csv_path),
                    "rows": rows,
                },
            )


async def start_file_watcher() -> None:
    if Observer is None:
        return
    results_dir = settings.results_root_path
    results_dir.mkdir(parents=True, exist_ok=True)
    loop = asyncio.get_running_loop()
    observer = Observer()
    observer.schedule(ResultsHandler(loop), str(results_dir), recursive=True)
    observer.start()
    try:
        while True:
            await asyncio.sleep(1)
    finally:
        observer.stop()
        observer.join(timeout=5)

