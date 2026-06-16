# LLS KPI Goodput And Throughput Accounting

This document describes simulator KPI accounting derived from NR PHY/MAC
evidence. It is not a normative 6G KPI standard.

## Contract

LLS KPI summary values are reconstructed from raw source rows. Direction is a
required source column; UL values use only `Direction=UL` rows and DL values use
only `Direction=DL` rows. Missing, empty, proxy-only, skipped-only, wrong-
direction, duration-less, or schema-invalid source rows fail strict KPI
reconstruction instead of falling back to aggregate or previous summary values.

## Core Formulas

`PHY_ScheduledThroughput_Mbps` is
`sum(ScheduledBits or TBSize_bits/TBS)/AggregationDurationSec/1e6`.

`TB_Delivery_Goodput_Mbps` is
`sum(unique delivered TB GoodputBits where CRC passes)/AggregationDurationSec/1e6`.
Failed CRC transport blocks contribute scheduled load but zero delivered goodput.

`BER` is weighted as `sum(BitErrors)/sum(BitsCompared)`, never as an
unweighted mean of per-row BER values.

`BLER` is currently attempt-level failed TB attempts divided by total TB
attempts. Final-delivery HARQ BLER remains a separate MAC/HARQ procedure
closure item.

`Goodput_UL_max_Mbps` and `Goodput_DL_max_Mbps` are legacy compatibility aliases.
They are generated from the canonical formula registry and raw direction rows,
not from shared aggregate link variables.

## HARQ Accounting

Scheduled retransmission bits count toward scheduled PHY load. Delivered
goodput counts a `TransportBlockId` only once. If a delivered TB appears again,
the duplicate attempt is recorded in `kpi_harq_delivery_trace_*.csv` and does
not inflate delivered goodput.

If `TransportBlockId` is missing, the accounting engine derives a stable key
from UE/HARQ/NDI/frame/slot/RV fields. That supports KPI reconstruction but does
not claim full MAC/HARQ timing conformance.

## Artifacts

The KPI exporter writes:

- `air_interface/csv/lls_kpi_summary.csv`
- `reports/csv/kpi_formula_registry.csv`
- `reports/csv/kpi_source_table_manifest.csv`
- `reports/csv/kpi_raw_table_schema_audit.csv`
- `reports/csv/kpi_reconstruction_summary.csv`
- `reports/csv/kpi_row_contributions_ul.csv`
- `reports/csv/kpi_row_contributions_dl.csv`
- `reports/csv/kpi_harq_delivery_trace_ul.csv`
- `reports/csv/kpi_harq_delivery_trace_dl.csv`
- `reports/csv/kpi_direction_isolation_audit.csv`
- `reports/csv/kpi_legacy_alias_map.csv`
- `reports/csv/kpi_known_bug_regression.csv`
- `reports/csv/kpi_unit_conversion_audit.csv`
- `reports/csv/kpi_duration_source_audit.csv`
- `reports/csv/kpi_objective_binding.csv`

## Regression

The audited bug was `Goodput_UL_max_Mbps` reporting a DL-like value around
`40.137091 Mbps` while raw UL PUSCH trial rows had a maximum around `7.952 Mbps`.
`testKPIULGoodputNotCopiedFromDL` reproduces that mismatch and verifies the
guard rejects the copied value.

## Verification

Focused tests:

```matlab
matlab -batch "setup6GRSimToolkit('Verbose',false); testKPIFormulaRegistry; testKPIRawTableSchemaValidation; testKPIDirectionIsolation; testKPIULGoodputNotCopiedFromDL; testKPIRawToSummaryReconstruction; testKPIHARQDeduplicatedGoodput; testKPIFailedTBNotGoodput; testKPIWeightedBER; testKPIDurationSource; testKPIUnitConversion; testKPILegacyAliasMapping; testKPIArtifactSchemas"
```

Integration tests:

```matlab
matlab -batch "setup6GRSimToolkit('Verbose',false); testLinkExportPipeline; testLLSSummaryRawConsistency; testSchedulerGrantConsistency"
```

## Limits

MAC goodput is unavailable unless MAC SDU delivery rows exist. Application
goodput is unavailable unless application packet delivery rows exist. This KPI
accounting repair does not close the full UL receiver evidence issue or full
MAC/HARQ procedure conformance.
