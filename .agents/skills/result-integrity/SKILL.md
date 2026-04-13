---
name: result-integrity
description: Protect exported tables, manifests, and campaign artifacts from synthetic or mislabeled data. Use when editing sixgr_run_3gpp_full_campaign.m, +sixgr/+system/SystemLevelRunner.m, +sixgr/+report, +sixgr/+link/exportLinkKPIs.m, manifest generation, or any code that writes SummaryTable, CheckTable, PacketIntegrityTable, grant traces, or fallback and proxy labels.
---

# Result Integrity

Use this skill to review or patch exported results without corrupting provenance.

## Workflow

1. Decide which tables are primary user-facing outputs and which artifacts are debug, proxy, or audit-only.
2. Enforce these invariants:
- Never mix truth rows with proxy or fallback rows in a primary table.
- Never add placeholder rows just to keep table height or schema stable.
- Keep `Source`, `ExecutionBackend`, `ApproximationMode`, `Notes`, and manifest metadata honest.
- Export grant-level TBS only from actual grants, transport blocks, or direct PHY allocation math.
3. Check the hotspots and red flags in `references/checks.md`.
4. Run the listed tests. When in doubt, run all of them plus `testAll`.

## Quick decisions

- Missing data: emit an empty table, skip the artifact, or throw. Do not fabricate a replacement row.
- Proxy rescue data: keep it in explicitly proxy-labeled artifacts only.
- Existing notes like `fallback_*` and `synthetic_from_fast_kernel*` are quarantine markers, not production summary rows.

Read `references/checks.md` for file-level guidance and commands.
