# Trust Boundary Audit

Date: 2026-04-24
Repo: `sixgr_foundation_v2`

## Purpose

This note documents the current repository trust-boundary problem: active source and tests are mixed with runtime-generated artifacts, temporary scratch files, dashboard state, and audit outputs. The goal of Phase 0 is to make the tree safer to patch without silently deleting user-owned work or breaking test fixtures that are intentionally checked in.

## Inventory Commands

The current snapshot was built from:

```powershell
git status --short
git diff --cached --name-status
git diff --name-status
Get-Content .gitignore
Get-ChildItem -Force -Directory
Get-ChildItem -Recurse -Directory -Filter __pycache__
Get-ChildItem -Force tmp_web_runs,logs,reports,results
```

Snapshot counts from `git status --porcelain=v1`:

- Staged: `0`
- Unstaged tracked changes: `63`
- Deleted tracked files: `5`
- Untracked files: `83`

## Classification

### Active source code

These are legitimate edit targets and must not be treated as disposable runtime output:

- `+sixgr/`
- `apps/*.py`
- `simulator/configs/defaults/`
- `simulator/configs/schema/`
- canonical scenario YAML under `simulator/configs/scenarios/`
- `scripts/`

### Active tests

- `tests/*.m`
- `tests/*.py`

### Documentation and checked-in audit evidence

These are not runtime scratch files even when they are CSV:

- `docs/`
- checked-in report contract CSV under `reports/`

Important: several tests and scripts read specific checked-in `reports/*.csv` files directly. They are currently part of the repository contract surface and must not be blanket-ignored or silently deleted.

### Generated runtime artifacts

These are recurring runtime outputs and should not be patched as if they were source:

- `tmp_web_runs/`
- `logs/`
- `results/`
- Python bytecode caches under `apps/__pycache__/`, `scripts/__pycache__/`, `tests/__pycache__/`
- web-generated scenario YAML named `simulator/configs/scenarios/__web_runtime_*.yaml`

Examples seen in this snapshot:

- `tmp_web_runs/codex_ul_noisevar_web_10slot_20260424.log`
- `tmp_web_runs/*.pid.json`
- `tmp_web_runs/*.offset.json`
- `logs/lls_web_dashboard_62906.stdout.log`
- `simulator/configs/scenarios/__web_runtime_codex_ul_noisevar_web_10slot_20260424.yaml`

### Temporary scratch and document-extraction folders

These appear to be local working material rather than repo source:

- `.codex*/`
- `codex_tmp/`
- `codex_empty/`
- `tmp/`
- `tmp_dashboard/`
- `tmp_flexran_pdf_pages/`
- `tmp_intel_doc_extracts/`
- `tmp_issue6_runsingle_probe/`
- `tmp_rehydrate/`
- `tmp_repro/`
- `tmp_tbs_pdf_pages/`
- `Crashpad/`
- `MathWorks/`

### Ambiguous user-owned work

The following paths are modified or newly created and may contain active user work. They were not deleted, reverted, or restaged in Phase 0:

- source changes under `+sixgr/`
- scenario/config changes under `simulator/configs/`
- dashboard/materializer changes under `apps/`
- test changes under `tests/`
- newly added helper/test files such as:
  - `+sixgr/+phy/+ul/resolveULNoiseVariance.m`
  - `+sixgr/+util/normalizeReportedCQI.m`
  - `+sixgr/+util/resolveDataNREPerPRB.m`
  - `+sixgr/+util/resolveTDDSlotPartition.m`
  - `tests/testULNoiseVarianceValidation.m`

### Deleted tracked files

The tracked deleted files are old web-runtime scenario YAMLs:

- `simulator/configs/scenarios/__web_runtime_webgui_rel20_4ghz_100mhz_200ue_1frame_20260421_073928.yaml`
- `simulator/configs/scenarios/__web_runtime_webgui_rel20_4ghz_100mhz_200ue_1frame_20260421_113050.yaml`
- `simulator/configs/scenarios/__web_runtime_webgui_rel20_4ghz_100mhz_200ue_1frame_20260421_113321.yaml`
- `simulator/configs/scenarios/__web_runtime_webgui_rel20_4ghz_100mhz_50ue_14slot_20260422_060209.yaml`
- `simulator/configs/scenarios/__web_runtime_webgui_rel20_4ghz_100mhz_50ue_14slot_r4_20260422_100500.yaml`

These were not resurrected in Phase 0.

## Ignore Policy Added

Phase 0 updated `.gitignore` to quarantine recurring runtime debris:

- Python caches: `__pycache__/`, `*.pyc`, `*.pyo`
- Codex/local scratch: `.codex*/`, `codex_tmp/`, `codex_empty/`
- MATLAB scratch: `*.asv`, `*.autosave`, `*.mlx.autosave`, `slprj/`
- runtime temp/log roots: `logs/`, `tmp/`, `tmp*/`, `Crashpad/`, `MathWorks/`
- dashboard/web runtime outputs: `tmp_web_runs/`, `tmp_dashboard/`
- generated runtime scenario YAML: `simulator/configs/scenarios/__web_runtime_*.yaml`

## Hybrid Boundary Cases

The following paths are intentionally *not* blanket-ignored in this phase:

- `reports/*.csv`
  - reason: current tests and helper scripts read these checked-in CSVs as canonical contract inputs
- `simulator/configs/scenarios/*.yaml`
  - reason: canonical scenario definitions live beside generated `__web_runtime_*` YAML, so the ignore rule targets only the generated prefix

## Source-Input Dependency Check

A search of the codebase shows:

- `tmp_web_runs/` is a recognized runtime output/state location for dashboard launch and monitoring scripts
- `__web_runtime_*.yaml` files are generated and cleaned by the dashboard code
- `reports/*.csv` includes checked-in contract fixtures consumed by tests

Conclusion:

- `tmp_web_runs/`, dashboard logs, results trees, and `__web_runtime_*.yaml` are runtime artifacts, not authoritative source inputs
- `reports/*.csv` is currently a mixed domain and must remain reviewable until the contract-fixture surface is separated from runtime-generated report exports

## Non-Destructive Phase 0 Outcome

Phase 0 did the following:

- tightened ignore rules for recurring runtime debris
- documented mixed-boundary paths
- preserved ambiguous user-owned files
- preserved current tracked deletions

Phase 0 explicitly did not:

- delete tracked generated files from Git history
- revert user edits
- move checked-in contract CSV out of `reports/`

## Recommended Follow-Up

To finish trust-boundary hardening cleanly in a later change:

1. move checked-in report-contract fixtures out of `reports/` into a dedicated test-fixture directory
2. deindex tracked runtime logs, dashboard state files, and old `__web_runtime_*` YAML once the owner confirms they are disposable
3. add a small script that inventories source vs runtime artifacts before large patch series
