# Canonical 6GR WebGUI information architecture

## Global shell

- Same-origin login-protected application served by the canonical FastAPI process.
- Fixed global run selector with search, recent, pinned, ownership/share indicator, status, profile and scenario.
- Mode selector: LLS, SLS, E2E/Protocol Study. Changing mode changes visible configuration sections but never mutates hidden YAML.
- Global badges: run status, config revision/hash, profile, source commit, MATLAB/Toolbox version, artifact completeness and validation state.

## Primary navigation

1. **Overview** — stage waterfall, KPI cards, critical validation gates, hero plots and recent events.
2. **Configure** — structured parameter catalog, architecture block diagram, OSM geometry, Advanced raw YAML, source/effective/resolved/diff.
3. **Runs** — owned/shared/all-by-role tables, queue, start/stop/share/delete, resource/quota use.
4. **Live** — progress, stage timing, logs, measured KPIs, queue/resource state and stop action by permission.
5. **Results** — domain and DUT gallery generated from the artifact registry.
6. **Validation** — point status, confidence intervals, independent comparisons, provenance, artifact/schema audits and gate waterfall.
7. **Compare Runs** — compatible-key selection, overlays, deltas and confidence-aware comparisons.
8. **Artifact Explorer** — every CSV/PNG/JSON/YAML/MAT/MD/log with filters, preview, hash, lineage and download.
9. **Architecture & Parameters** — interactive L1/L2/L3 block diagram and searchable schema catalog.
10. **Operations** — worker/queue/DB/disk/quota health, audit, retention and administration under RBAC.

## Results page behavior

- Left filter rail: domain, DUT, direction, UE/cell, base/impact, evidence validity, file type and search.
- Hero grid: 2–4 highest-priority plots from `dashboard_dut_visualization_catalog.csv`.
- All artifacts: cards generated from `dashboard_artifact_registry.csv`; never hard-coded in React.
- Each card shows source CSV, SHA-256, generation time, provenance, validity, schema state and an explicit unavailable reason.
- Plotly interactive reconstruction is allowed only from validated source CSV and a registered recipe. Otherwise display the validated PNG. Missing data never yields a synthetic line/zero-filled plot.

## Attached visual references

The files under `visual_references/` are style/archetype inputs only. They must never appear in a run artifact manifest, never be copied to a run directory and never satisfy a result/validation requirement.
