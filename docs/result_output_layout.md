# Result Output Layout

This simulator now writes one canonical, analysis-friendly run tree instead of mixing raw root files, duplicate mirrors, and timestamped folders.

## Canonical Run Tree

Each run folder is organized as:

```text
<runFolder>/
  meta/
  reports/
    csv/
    mat/
    image/
  logs/
  air_interface/
    csv/
    mat/
    image/
    logs/
    detailed/
      csv/
      mat/
      image/
      logs/
  control/
    csv/
    image/
  harq/
    csv/
  system/
    csv/
    mat/
    image/
    logs/
  mmtc/
    csv/
    mat/
    image/
    logs/
  interference/
    csv/
  beamforming/
    csv/
  numerology/
    csv/
  rf/
    csv/
  v2x/
    csv/
  ntn/
    csv/
  packet_flow/
    csv/
    mat/
    image/
    logs/
  calibration/
```

Top-level results roots remain bucketed by simulation scope:

```text
results/
  lls/
  sls/
  e2e/
```

Stable default run folders are created under those buckets, for example:

- `results/lls/session/current`
- `results/sls/session/current`
- `results/e2e/truth_validation/current`

System-level runs now also emit a derived, provenance-preserving output
catalog directly under the run root:

```text
<systemRun>/
  manifests/
  summaries/
  raw/
  tables/
  traces/
  maps/
  plots/
  comparisons/
  debug/
```

This catalog does not relabel or synthesize system results. It reorganizes
actual SLS outputs into a review-friendly package and adds direct-run
metadata such as resolved config, environment summary, runtime summary, and
catalog inventory.

## Main Export Writers

These are the main places where result artifacts are written:

- `sixgr_run_3gpp_full_campaign.m`
  Main campaign orchestration, reports, metadata, packet-flow exports, and auxiliary probe exports.
- `run_truth_validation_profile.m`
  Truth-validation profile wrapper and truth-validation sidecar report/manifest.
- `+sixgr/+truth/runWaveformLinkBundle.m`
  Waveform LLS bundle under `air_interface/`.
- `+sixgr/+truth/exportControlPlaneTraces.m`
  Control-plane traces under `control/csv/`.
- `+sixgr/+link/exportLinkKPIs.m`
  LLS KPI CSV/MAT/image exports.
- `+sixgr/+system/SystemLevelRunner.m`
  SLS/system CSV/MAT/image exports.
- `+sixgr/+report/verifyCampaignArtifacts.m`
  Artifact checklist and required-output reports under `reports/csv/`.
- `+sixgr/+truth/scanTruthArtifacts.m`
  Truth-artifact scan under `reports/csv/`.
- `sixgr_deep_validate_campaign.m`
  Deep-validation audit outputs.

## Naming Rules

- Metadata goes under `meta/`.
- Human-readable reports go under `reports/`.
- Air-interface/link outputs go under `air_interface/`.
- System-level outputs go under `system/`.
- End-to-end packet/stack outputs go under `packet_flow/`.
- Figures go into `image/` folders, not `fig/`.
- Logs go into `logs/`.
- Optional profiling sidecars go into `reports/profiling/` only when a caller explicitly creates them through supported waveform tooling.

## Optional Compatibility Trees

- `analysis_by_block/` is an optional derived analysis tree, not the canonical source of truth.
- Topical mirrors under `results/lls`, `results/sls`, and `results/e2e` are optional compatibility views for browsing across runs.
