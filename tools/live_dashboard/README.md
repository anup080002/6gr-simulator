# Reliable live dashboard refresh

Start the existing dashboard with the additive display repair:

```powershell
python tools/live_dashboard/serve.py --host 127.0.0.1 --port 62906 --server auto --threads 32 --no-browser
```

Use the installed WebGUI Python environment if `python` does not contain its
dependencies. This launcher imports `apps/lls_web_dashboard.py` directly. It
keeps the existing routes, authentication, source readers and exports. It does
not start a simulation. Stop only the old dashboard listener before replacing
it; do not stop MATLAB. Open <http://127.0.0.1:62906/realtime> and reload any
browser tab that was already open to receive the updated JavaScript.

The separate launcher is intentional: the running n40 gate freezes every
`apps/**/*.py` file, as well as simulator and configuration sources. Editing
those files during execution would invalidate checkpoint continuation. The
repair lives under `tools/live_dashboard`, outside that frozen input set;
neither source-hash checks nor simulator acceptance criteria are changed.

## Corrected behavior

- The automatic Live selection prefers the active waveform child over its
  own sweep parent. Explicit run IDs still select exactly that run, including
  historical failures. Sweep progress links open each child's own evidence.
- Only one lightweight request and one detailed request per selected run may
  be in flight. A valid detailed response is displayed even when publication
  advances during the request. Its actual source version and timestamp remain
  visible, and a subsequent poll retrieves newer evidence.
- Lightweight updates retain the same run's detailed tables, configured UE
  count and plots. A full response can still legitimately replace them with
  empty results. Missing measurements remain missing; zeros are not invented.
- Refresh failures preserve the last received display and show the error.
  Responses from an old run selection cannot overwrite the current run.
- Redraws deferred while editing resume after the interaction ends. A focused
  button no longer freezes the page indefinitely. **Refresh now** requests an
  explicit refresh. The status panel distinguishes loading from missing data.
- Windows process inventories are shared for at most three seconds instead
  of launching one PowerShell process per historical run. This caches only
  the actual OS observation, never measurement values or acceptance results.

## Focused verification

```powershell
python -m pytest tools/live_dashboard -q
```

The tests execute the exact frontend JavaScript with controlled HTTP responses
and UI timing, plus injection and concurrent process-inventory checks. They
cover changing artifact versions, late responses, retry, empty/full data,
clock ordering, editing, parent/child ownership and historical selection.
Browser checks must additionally confirm loaded live tables, the selector,
visible refresh status, and absence of JavaScript errors. These tests concern
the dashboard only; they do not establish any PHY or gate acceptance result.
