# 6GR LLS WebGUI

This WebGUI provides a FastAPI backend and React/Vite frontend for launching
config-driven `run_true_lls` jobs, streaming MATLAB stdout/WebSocket updates,
and inspecting measurement-backed CSV artifacts.

## Run Locally

From `webgui/` on Windows:

```bat
start_all.bat
```

Or run the services separately:

```bat
start_backend.bat
start_frontend.bat
```

Backend: <http://localhost:8000/api/v1/health>

Frontend: <http://localhost:5173>

## Integrity Notes

- MySQL is optional. If the database is unavailable, the backend stays in
  CSV-only mode and reads artifacts from `results/`.
- Missing CSV artifacts are returned as empty/unavailable responses. The API
  does not synthesize placeholder rows.
- The oracle guard flags `UsedOracleFields`, configured-SNR noise sources,
  perfect/oracle channel-estimation labels, and fallback/synthetic provenance
  tokens in measurement-facing CSVs.
- The frontend renders unavailable states when evidence is missing.

## Main API Surfaces

- `POST /api/v1/runs`
- `GET /api/v1/runs`
- `GET /api/v1/results/{run_id}`
- `GET /api/v1/analytics/real-time/{run_id}`
- `GET /api/v1/profile/{run_id}`
- `GET /api/v1/complexity/{run_id}`
- `GET /api/v1/functions/{run_id}/missed`
- `WS /ws/{run_id}`

