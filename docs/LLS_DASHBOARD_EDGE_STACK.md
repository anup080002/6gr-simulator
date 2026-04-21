# LLS Dashboard Edge Stack

This repo now supports a faster browser-serving path without rewriting the dashboard away from Python.

## Recommended topology

- Python dashboard stays responsible for:
  - login/session handling
  - `/api/*` orchestration
  - live MySQL reads
  - browser page generation
- A reverse proxy sits in front and caches only immutable artifact/image downloads:
  - `/artifact/<id>/raw`
- Recommended backend mode:
  - `waitress`
- Recommended edge:
  - `nginx` with `proxy_cache`

## Why this is faster

- artifact/image payloads are immutable by `artifact_id`, so proxy caching is safe
- the dashboard keeps doing live orchestration, but repeated image fetches stop hitting Python/MySQL
- gzip stays at the edge for HTML/JSON/SVG
- `waitress` handles concurrent browser/API traffic better than the basic `ThreadingHTTPServer`

## Launch options

Direct dashboard:

```powershell
apps\start_lls_web_dashboard.ps1 -Server waitress -Threads 32
```

Edge stack with nginx cache in front:

```powershell
apps\start_lls_dashboard_edge_stack.ps1 -Server waitress -Threads 32 -FrontendPort 62906 -BackendPort 62907
```

If `nginx.exe` is not found, the edge launcher falls back to the direct dashboard launcher.

## Files

- `apps/start_lls_web_dashboard.ps1`
- `apps/start_lls_dashboard_edge_stack.ps1`
- `apps/deploy/nginx/lls_dashboard_proxy_cache.conf.template`

## Notes

- live JSON endpoints are intentionally not proxy-cached
- `/artifact/*` is the main cache target because those files are immutable and large
- analytics and result image cards now open in a new browser tab so SVG-native zoom/pan and browser image tooling can be used directly
