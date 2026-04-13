# Result Integrity Checks

## Primary tables

- Link KPI tables and raw trials
- `E2E.SummaryTable`
- `E2E.CheckTable`
- `E2E.PacketIntegrityTable`
- `E2E.FlowSummaryTable`
- `E2E.BearerSummaryTable`
- Grant and HARQ traces
- Manifest metadata and structured organizer outputs

## Hotspots

- `sixgr_run_3gpp_full_campaign.m`: do not promote rows with notes like `fallback_*` or `synthetic_from_fast_kernel*` into primary result tables.
- `+sixgr/+system/SystemLevelRunner.m`: grant and HARQ tables must use real grant fields and real `TBSBits`.
- `+sixgr/+report/OrganizeRunResults.m`: preserve E2E artifacts and manifest entries.
- `+sixgr/+link/exportLinkKPIs.m`: keep CSV, MAT, and FIG export contracts stable.
- `+sixgr/+core/SimResults.m`: preserve `strictMode`, `approximationsUsed`, `calibrationSource`, `configHash`, `codeVersion`, and `missingArtifacts`.

## Required tests

- `matlab -batch "setup6GRSimToolkit('Verbose',false); testLinkExportPipeline; testArtifactIntegrity; testOrganizeRunResults_E2EArtifactPreservation; testSchedulerGrantConsistency"`
- `matlab -batch "setup6GRSimToolkit('Verbose',false); testE2E_FastVsTruth; testE2E_TruthPacketSemanticCampaign"`
- `matlab -batch "setup6GRSimToolkit('Verbose',false); testAll"`

## Red flags

- Placeholder rows added only to keep table height stable
- `GrantReason=fast_proxy*` or `Note=synthetic_from_fast_kernel*` appearing in primary grant exports
- Proxy or fallback sources relabeled as `truth` or left unlabeled in summary rows
